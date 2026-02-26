# frozen_string_literal: true

# READ-ONLY diagnostic helper for Chatwoot + Evolution (WhatsApp) message auditing.
#
# Usage in rails console (production/staging):
#   load Rails.root.join('script/diagnostics/evolution_message_diagnostics.rb')
#   EvolutionMessageDiagnostics.run!(account_id: 1, hours: 24)
#   EvolutionMessageDiagnostics.run!(account_id: 1, inbox_id: 123, hours: 48)
#   EvolutionMessageDiagnostics.timeline!(account_id: 1, conversation_display_id: 4567)
#
# Note:
# - This inspects how messages were persisted in the DB.
# - It does NOT recover the raw HTTP payload originally received from Evolution.

module EvolutionMessageDiagnostics
  extend self

  CHANNEL_TYPE = 'Channel::Whatsapp'

  def run!(account_id:, hours: 24, inbox_id: nil, conversation_display_id: nil, limit: 200)
    scope = base_scope(
      account_id: account_id,
      hours: hours,
      inbox_id: inbox_id,
      conversation_display_id: conversation_display_id
    )

    puts "\n=== Evolution / WhatsApp Message Diagnostics (READ-ONLY) ==="
    puts "account_id=#{account_id} channel_type=#{CHANNEL_TYPE} hours=#{hours} inbox_id=#{inbox_id || '-'} " \
         "conversation_display_id=#{conversation_display_id || '-'}"
    puts "now=#{Time.current.iso8601}"
    puts "window_start=#{hours.hours.ago.iso8601}"

    print_summary(scope)

    rows = scope.reorder('messages.created_at DESC').limit(limit).to_a
    puts "\n=== Recent samples (#{rows.size}) ==="
    print_rows(rows)

    puts "\n=== Suspects: outgoing + source_id + sender_type=User ==="
    print_rows(rows.select { |message| classify(message) == 'OUT_ATTRIB_USER' })

    puts "\n=== External OK: outgoing + source_id + sender=nil ==="
    print_rows(rows.select { |message| classify(message) == 'OUT_EXT_OK' })

    puts "\nDone. No data was modified."
    nil
  end

  def timeline!(account_id:, conversation_display_id:, limit: 100)
    conversation = Conversation.find_by!(account_id: account_id, display_id: conversation_display_id)

    rows = Message.preload(:sender, :inbox, conversation: :contact_inbox)
                  .where(conversation_id: conversation.id)
                  .reorder('messages.created_at DESC')
                  .limit(limit)
                  .to_a
                  .reverse

    puts "\n=== Conversation timeline (READ-ONLY) ==="
    puts "account_id=#{account_id} conversation_display_id=#{conversation_display_id} conversation_id=#{conversation.id}"
    puts "inbox_id=#{conversation.inbox_id} channel_type=#{conversation.inbox&.channel_type} status=#{conversation.status}"
    puts "assignee_id=#{conversation.assignee_id || '-'} contact_id=#{conversation.contact_id}"
    puts "contact_inbox_source_id=#{conversation.contact_inbox&.source_id || '-'}"

    print_rows(rows)

    puts "\nDone. No data was modified."
    nil
  end

  private

  def base_scope(account_id:, hours:, inbox_id:, conversation_display_id:)
    scope = Message.joins(:inbox)
                   .preload(:sender, :inbox, conversation: :contact_inbox)
                   .where(messages: { account_id: account_id })
                   .where(inboxes: { channel_type: CHANNEL_TYPE })
                   .where('messages.created_at >= ?', hours.hours.ago)

    scope = scope.where(messages: { inbox_id: inbox_id }) if inbox_id.present?

    if conversation_display_id.present?
      conversation = Conversation.find_by!(account_id: account_id, display_id: conversation_display_id)
      scope = scope.where(messages: { conversation_id: conversation.id })
    end

    scope
  end

  def print_summary(scope)
    puts "\n=== Summary ==="
    puts "- total: #{scope.count}"
    puts "- incoming: #{scope.where(message_type: Message.message_types[:incoming]).count}"
    puts "- outgoing: #{scope.where(message_type: Message.message_types[:outgoing]).count}"
    puts "- outgoing with source_id: #{outgoing_with_source_scope(scope).count}"
    puts "- outgoing with source_id and sender=nil (external ok): #{outgoing_with_source_scope(scope).where(sender_id: nil, sender_type: nil).count}"
    puts "- outgoing with source_id and sender_type=User (suspect): #{outgoing_with_source_scope(scope).where(sender_type: 'User').count}"
    puts "- outgoing without source_id and sender_type=User: #{outgoing_without_source_scope(scope).where(sender_type: 'User').count}"
  end

  def outgoing_with_source_scope(scope)
    scope.where(message_type: Message.message_types[:outgoing])
         .where("messages.source_id IS NOT NULL AND messages.source_id <> ''")
  end

  def outgoing_without_source_scope(scope)
    scope.where(message_type: Message.message_types[:outgoing])
         .where("messages.source_id IS NULL OR messages.source_id = ''")
  end

  def print_rows(rows)
    if rows.blank?
      puts '(no rows)'
      return
    end

    rows.each { |message| puts format_row(message) }
  end

  def format_row(message)
    external_created_at = dig_value(message.content_attributes, :external_created_at)
    automation_rule_id = dig_value(message.content_attributes, :automation_rule_id)
    campaign_id = dig_value(message.additional_attributes, :campaign_id)

    [
      "[#{classify(message)}]",
      "id=#{message.id}",
      "at=#{message.created_at&.iso8601}",
      "conv=#{message.conversation&.display_id}",
      "inbox=#{message.inbox_id}",
      "type=#{message.message_type}",
      "status=#{message.status}",
      "private=#{message.private}",
      "sender_type=#{message.sender_type || '-'}",
      "sender_id=#{message.sender_id || '-'}",
      "sender_name=#{truncate(message.sender&.name, 40) || '-'}",
      "source_id=#{truncate(message.source_id, 80) || '-'}",
      "contact_source_id=#{truncate(message.conversation&.contact_inbox&.source_id, 40) || '-'}",
      "external_created_at=#{external_created_at || '-'}",
      "automation_rule_id=#{automation_rule_id || '-'}",
      "campaign_id=#{campaign_id || '-'}",
      "content=#{truncate(message.content, 90) || '-'}",
      "content_attrs=#{truncate(json_text(message.content_attributes), 140)}",
      "additional_attrs=#{truncate(json_text(message.additional_attributes), 140)}"
    ].join(' | ')
  end

  def classify(message)
    return 'INCOMING' if message.incoming?
    return 'ACTIVITY' if message.activity?
    return 'TEMPLATE' if message.template?
    return 'OUT_OTHER' unless message.outgoing?
    return 'OUT_NO_SOURCE' if message.source_id.blank?
    return 'OUT_EXT_OK' if message.sender.nil?
    return 'OUT_ATTRIB_USER' if message.sender_type == 'User'
    return 'OUT_AGENTBOT' if message.sender_type == 'AgentBot'

    'OUT_OTHER'
  end

  def truncate(value, max)
    return '-' if value.nil?

    text = value.to_s
    text.length > max ? "#{text[0...max]}..." : text
  end

  def json_text(value)
    (value.presence || {}).to_json
  rescue StandardError
    '<json_error>'
  end

  def dig_value(hash, key)
    return nil unless hash.respond_to?(:dig)

    hash.dig(key) || hash.dig(key.to_s)
  end
end
