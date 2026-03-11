# frozen_string_literal: true

class Evolution::ConversationDedup::MergeService
  pattr_initialize [:account!, :inbox!, :canonical_conversation_id!, :target_conversation_ids!, :operation, :dry_run]

  PUBLIC_CHAT_MESSAGE_TYPES = [
    Message.message_types[:incoming],
    Message.message_types[:outgoing],
    Message.message_types[:template]
  ].freeze
  VALID_OPERATIONS = %w[merge keep_only].freeze
  DEDUPE_ATTRIBUTE_KEYS = %w[
    dedupe_send_blocked
    dedupe_canonical_conversation_id
    dedupe_canonical_conversation_display_id
    dedupe_group_key
    dedupe_blocked_at
  ].freeze

  def preview
    execute(simulate: true)
  end

  def perform
    execute(simulate: dry_run_mode?)
  end

  private

  def execute(simulate:)
    validate!

    result = {
      operation: selected_operation,
      canonical_conversation_id: canonical_conversation.id,
      target_conversation_ids: target_conversations.map(&:id),
      moved_messages: 0,
      deduplicated_messages: 0,
      replaced_messages: 0,
      deleted_conversations: 0
    }

    ActiveRecord::Base.transaction do
      target_conversations.each do |target_conversation|
        process_target_conversation(target_conversation, result, simulate: simulate)
      end

      ensure_canonical_unblocked!(simulate: simulate)

      raise ActiveRecord::Rollback if simulate
    end

    result
  end

  def process_target_conversation(target_conversation, result, simulate:)
    merge_messages_from_target(target_conversation, result, simulate: simulate) if selected_operation == 'merge'
    delete_conversation(target_conversation, simulate: simulate)
    result[:deleted_conversations] += 1
  end

  def merge_messages_from_target(target_conversation, result, simulate:)
    canonical_lookup = build_canonical_lookup
    source_messages = public_chat_messages_for(target_conversation)

    source_messages.each do |source_message|
      signature = message_signature(source_message)
      existing_message = canonical_lookup[signature]

      if existing_message
        handle_collision(existing_message, source_message, signature, canonical_lookup, result, simulate: simulate)
      else
        move_message_to_canonical(source_message, simulate: simulate)
        canonical_lookup[signature] = source_message
        result[:moved_messages] += 1
      end
    end
  end

  def handle_collision(existing_message, source_message, signature, canonical_lookup, result, simulate:)
    winner = choose_collision_winner(existing_message, source_message)

    if winner.id == source_message.id
      move_message_to_canonical(source_message, simulate: simulate)
      destroy_message(existing_message, simulate: simulate)
      canonical_lookup[signature] = source_message
      result[:moved_messages] += 1
      result[:replaced_messages] += 1
      result[:deduplicated_messages] += 1
      return
    end

    destroy_message(source_message, simulate: simulate)
    result[:deduplicated_messages] += 1
  end

  def choose_collision_winner(existing_message, source_message)
    existing_has_media = has_media?(existing_message)
    source_has_media = has_media?(source_message)
    return source_message if source_has_media && !existing_has_media

    existing_message
  end

  def build_canonical_lookup
    public_chat_messages_for(canonical_conversation).each_with_object({}) do |message, lookup|
      signature = message_signature(message)
      existing_message = lookup[signature]
      lookup[signature] = choose_collision_winner(existing_message, message) if existing_message
      lookup[signature] ||= message
    end
  end

  def public_chat_messages_for(conversation)
    Message.includes(:attachments)
           .where(conversation_id: conversation.id, private: false, message_type: PUBLIC_CHAT_MESSAGE_TYPES)
           .order(:created_at, :id)
  end

  def message_signature(message)
    source_id = message.source_id.to_s.strip
    return "sid:#{source_id.downcase}" if source_id.present?

    timestamp = message.created_at&.to_i || 0
    direction = message.outgoing? || message.template? ? 'outgoing' : 'incoming'
    normalized_content = message.content.to_s.gsub(/\s+/, ' ').strip
    "fb:#{timestamp}:#{direction}:#{normalized_content}"
  end

  def has_media?(message)
    message.attachments.any?
  end

  def move_message_to_canonical(message, simulate:)
    return if simulate

    # rubocop:disable Rails/SkipsModelValidations
    message.update_columns(conversation_id: canonical_conversation.id, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def destroy_message(message, simulate:)
    return if simulate

    message.destroy!
  end

  def delete_conversation(conversation, simulate:)
    return if simulate

    conversation.destroy!
  end

  def ensure_canonical_unblocked!(simulate:)
    attrs = canonical_conversation.additional_attributes.to_h
    updated_attrs = attrs.except(*DEDUPE_ATTRIBUTE_KEYS)
    return if attrs == updated_attrs
    return if simulate

    # rubocop:disable Rails/SkipsModelValidations
    canonical_conversation.update_columns(additional_attributes: updated_attrs, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def validate!
    raise 'Inbox must be an API inbox' unless inbox.api?
    raise 'Invalid operation' unless VALID_OPERATIONS.include?(selected_operation)
    raise 'Canonical conversation not found' unless canonical_conversation
    raise 'Target conversations cannot be empty' if target_ids.blank?
    raise 'One or more target conversations were not found' if target_conversations.size != target_ids.size
  end

  def selected_operation
    operation_value = operation.to_s
    operation_value = 'merge' if operation_value.blank?
    operation_value
  end

  def canonical_conversation
    @canonical_conversation ||= Conversation.find_by(
      id: canonical_conversation_id,
      account_id: account.id,
      inbox_id: inbox.id
    )
  end

  def target_ids
    @target_ids ||= begin
      ids = Array(target_conversation_ids).map(&:to_i).uniq
      ids - [canonical_conversation_id.to_i]
    end
  end

  def target_conversations
    @target_conversations ||= Conversation.where(
      id: target_ids,
      account_id: account.id,
      inbox_id: inbox.id
    ).order(:id).to_a
  end

  def dry_run_mode?
    ActiveModel::Type::Boolean.new.cast(dry_run)
  end
end
