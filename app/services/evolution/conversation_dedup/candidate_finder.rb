# frozen_string_literal: true

class Evolution::ConversationDedup::CandidateFinder
  pattr_initialize [:account!, :inbox!]

  PUBLIC_CHAT_MESSAGE_TYPES = [
    Message.message_types[:incoming],
    Message.message_types[:outgoing],
    Message.message_types[:template]
  ].freeze

  DEDUPE_ATTRIBUTE_KEYS = %w[
    dedupe_send_blocked
    dedupe_canonical_conversation_id
    dedupe_canonical_conversation_display_id
    dedupe_group_key
    dedupe_blocked_at
  ].freeze

  def perform
    raise 'Inbox must be an API inbox' unless inbox.api?

    grouped_candidates.filter_map do |contact_id, conversations|
      next if contact_id.blank?
      next if conversations.size < 2
      next unless evolution_related_group?(conversations)

      build_group(contact_id, conversations)
    end.sort_by { |group| [-group[:conversations].size, group[:contact_id], group[:group_key]] }
  end

  def apply_send_locks!(groups = perform)
    grouped_conversation_ids = groups.flat_map { |group| group[:conversation_ids] }.uniq
    return 0 if grouped_conversation_ids.blank?

    conversations_by_id = Conversation.where(
      account_id: account.id,
      inbox_id: inbox.id,
      id: grouped_conversation_ids
    ).index_by(&:id)

    updated_records = 0
    now = Time.current

    groups.each do |group|
      canonical = conversations_by_id[group[:suggested_canonical_conversation_id]]
      next unless canonical

      group[:conversation_ids].each do |conversation_id|
        conversation = conversations_by_id[conversation_id]
        next unless conversation

        updated_attributes = conversation.additional_attributes.to_h.deep_dup

        if conversation_id == canonical.id
          DEDUPE_ATTRIBUTE_KEYS.each { |key| updated_attributes.delete(key) }
        else
          updated_attributes['dedupe_send_blocked'] = true
          updated_attributes['dedupe_canonical_conversation_id'] = canonical.id
          updated_attributes['dedupe_canonical_conversation_display_id'] = canonical.display_id
          updated_attributes['dedupe_group_key'] = group[:group_key]
          updated_attributes['dedupe_blocked_at'] = now.utc.iso8601
        end

        next if updated_attributes == conversation.additional_attributes.to_h

        # rubocop:disable Rails/SkipsModelValidations
        conversation.update_columns(additional_attributes: updated_attributes, updated_at: now)
        # rubocop:enable Rails/SkipsModelValidations
        updated_records += 1
      end
    end

    updated_records
  end

  private

  def grouped_candidates
    api_inbox_conversations.where.not(contact_id: nil).group_by(&:contact_id)
  end

  def api_inbox_conversations
    @api_inbox_conversations ||= Conversation
                                 .includes(:contact_inbox, :contact)
                                 .where(account_id: account.id, inbox_id: inbox.id)
  end

  def build_group(contact_id, conversations)
    canonical = choose_canonical(conversations)
    sorted_conversations = conversations.sort_by(&:id)
    contact = sorted_conversations.first&.contact

    {
      group_key: "contact:#{contact_id}",
      contact_id: contact_id,
      contact_identifier: contact&.identifier,
      contact_name: contact&.name,
      conversation_ids: sorted_conversations.map(&:id),
      suggested_canonical_conversation_id: canonical.id,
      suggested_target_conversation_ids: sorted_conversations.map(&:id) - [canonical.id],
      conversations: sorted_conversations.map { |conversation| conversation_payload(conversation, canonical.id) }
    }
  end

  def choose_canonical(conversations)
    with_media = conversations.select { |conversation| has_media?(conversation) }
    canonical_pool = if with_media.any? && with_media.size != conversations.size
                       with_media
                     else
                       conversations
                     end

    canonical_pool.sort_by do |conversation|
      [
        historical_import?(conversation) ? 1 : 0,
        -source_id_coverage(conversation),
        -conversation.last_activity_at.to_i,
        conversation.id
      ]
    end.first
  end

  def conversation_payload(conversation, canonical_id)
    {
      id: conversation.id,
      display_id: conversation.display_id,
      status: conversation.status,
      historical_import: historical_import?(conversation),
      has_media: has_media?(conversation),
      source_id_coverage: source_id_coverage(conversation),
      last_activity_at: conversation.last_activity_at,
      contact_id: conversation.contact_id,
      contact_identifier: conversation.contact&.identifier,
      contact_inbox_source_id: conversation.contact_inbox&.source_id,
      dedupe_send_blocked: dedupe_send_blocked?(conversation),
      suggested_canonical: conversation.id == canonical_id
    }
  end

  def dedupe_send_blocked?(conversation)
    value = conversation.additional_attributes.to_h['dedupe_send_blocked']
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def historical_import?(conversation)
    value = conversation.additional_attributes.to_h['historical_import']
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def has_media?(conversation)
    @has_media ||= {}
    @has_media[conversation.id] ||= Message.where(
      conversation_id: conversation.id,
      private: false,
      message_type: PUBLIC_CHAT_MESSAGE_TYPES
    ).joins(:attachments).exists?
  end

  def source_id_coverage(conversation)
    @source_id_coverage ||= {}
    @source_id_coverage[conversation.id] ||= begin
      base_scope = Message.where(
        conversation_id: conversation.id,
        private: false,
        message_type: PUBLIC_CHAT_MESSAGE_TYPES
      )
      total_count = base_scope.count
      if total_count.zero?
        0.0
      else
        with_source_id_count = base_scope.where.not(source_id: [nil, '']).count
        (with_source_id_count.to_f / total_count).round(6)
      end
    end
  end

  def evolution_related_group?(conversations)
    conversations.any? { |conversation| evolution_related_conversation?(conversation) }
  end

  def evolution_related_conversation?(conversation)
    attrs = conversation.additional_attributes.to_h
    return true if ActiveModel::Type::Boolean.new.cast(attrs['historical_import'])
    return true if attrs['historical_import_source'] == 'evolution_super_admin'
    return true if attrs['historical_import_jid'].present?

    contact = conversation.contact
    return false unless contact

    return true if contact.identifier.to_s.start_with?('evolution:')
    return true if contact.identifier.to_s.end_with?('@s.whatsapp.net')

    contact.custom_attributes.to_h['evolution_remote_jid'].present?
  end
end
