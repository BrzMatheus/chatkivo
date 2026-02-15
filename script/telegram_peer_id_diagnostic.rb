# frozen_string_literal: true

# Diagnose Telegram PEER_ID_INVALID failures for old conversations.
#
# Usage:
#   RAILS_ENV=production bundle exec rails runner script/telegram_peer_id_diagnostic.rb [INBOX_ID] [DAYS_BACK] [LIMIT]
#
# Examples:
#   RAILS_ENV=production bundle exec rails runner script/telegram_peer_id_diagnostic.rb
#   RAILS_ENV=production bundle exec rails runner script/telegram_peer_id_diagnostic.rb 123 180 500
#
# Optional env vars:
#   CHECK_TELEGRAM=true|false                 # default: true
#   PROBE_CONVERSATION_BUSINESS_IDS=true|false # default: true
#   MAX_BUSINESS_ID_PROBES=20                 # default: 20

require 'json'
require 'fileutils'

class TelegramPeerIdDiagnostic
  PROBABLE_CAUSE_UNKNOWN = 'unknown'

  def initialize(inbox_id:, days_back:, limit:, check_telegram:, probe_conversation_business_ids:, max_business_id_probes:)
    @inbox_id = inbox_id
    @days_back = days_back
    @limit = limit
    @check_telegram = check_telegram
    @probe_conversation_business_ids = probe_conversation_business_ids
    @max_business_id_probes = max_business_id_probes
    @since_time = days_back.days.ago
  end

  def run
    print_header

    failed_messages = load_failed_messages
    if failed_messages.empty?
      puts 'No failed outgoing Telegram messages with PEER_ID_INVALID found in the selected window.'
      return
    end

    grouped_failures = failed_messages.group_by(&:conversation_id)
    conversations = load_conversations(grouped_failures.keys)
    channel_diagnostics = build_channel_diagnostics(conversations, grouped_failures)
    reports = build_reports(grouped_failures, conversations, channel_diagnostics)

    print_summary(reports)
    print_detailed_report(reports)
    dump_report(reports, channel_diagnostics)
  end

  private

  attr_reader :inbox_id, :days_back, :limit, :check_telegram, :probe_conversation_business_ids, :max_business_id_probes, :since_time

  def print_header
    puts '=' * 100
    puts 'Telegram PEER_ID_INVALID diagnostic'
    puts '=' * 100
    puts "Generated at: #{Time.current.utc.iso8601}"
    puts "Window start: #{since_time.utc.iso8601}"
    puts "Inbox filter: #{inbox_id || 'ALL'}"
    puts "Limit: #{limit}"
    puts "Telegram API checks: #{check_telegram}"
    puts "Conversation business_id probes: #{probe_conversation_business_ids}"
    puts '=' * 100
    puts
  end

  def load_failed_messages
    scope = Message
            .joins(conversation: :inbox)
            .where(inboxes: { channel_type: 'Channel::Telegram' })
            .where(message_type: Message.message_types[:outgoing], status: Message.statuses[:failed])
            .where('messages.created_at >= ?', since_time)
            .where("messages.content_attributes ->> 'external_error' ILIKE ?", '%PEER_ID_INVALID%')

    scope = scope.where(conversations: { inbox_id: inbox_id }) if inbox_id.present?

    scope
      .includes(conversation: [:inbox, :contact, :contact_inbox])
      .order(created_at: :desc)
      .limit(limit)
  end

  def load_conversations(conversation_ids)
    Conversation
      .includes(:inbox, :contact, :contact_inbox)
      .where(id: conversation_ids)
      .index_by(&:id)
  end

  def build_channel_diagnostics(conversations_by_id, grouped_failures)
    channel_map = {}

    conversation_ids_by_channel = grouped_failures.keys.group_by do |conversation_id|
      conversations_by_id[conversation_id]&.inbox&.channel_id
    end

    conversation_ids_by_channel.each do |channel_id, conversation_ids|
      next if channel_id.blank?

      conversation = conversations_by_id[conversation_ids.first]
      channel = conversation&.inbox&.channel
      next unless channel.is_a?(Channel::Telegram)

      channel_map[channel.id] = diagnose_channel(channel, conversation_ids, conversations_by_id)
    end

    channel_map
  end

  def diagnose_channel(channel, conversation_ids, conversations_by_id)
    channel_business_connection_id = channel.additional_attributes&.dig('business_connection_id')

    info = {
      channel_id: channel.id,
      inbox_id: channel.inbox&.id,
      account_id: channel.account_id,
      channel_business_connection_id: channel_business_connection_id,
      channel_business_connection_probe: nil,
      conversation_business_connection_probes: {}
    }

    return info unless check_telegram

    info[:channel_business_connection_probe] = if channel_business_connection_id.present?
                                                 probe_business_connection(channel, channel_business_connection_id)
                                               else
                                                 { ok: false, error: 'channel_business_connection_id_missing' }
                                               end

    return info unless probe_conversation_business_ids

    business_ids = conversation_ids
                   .map { |id| conversations_by_id[id]&.additional_attributes&.dig('business_connection_id') }
                   .compact
                   .map(&:to_s)
                   .uniq
    if business_ids.size > max_business_id_probes
      business_ids = business_ids.first(max_business_id_probes)
      info[:conversation_business_connection_probe_truncated] = true
    end

    business_ids.each do |business_connection_id|
      info[:conversation_business_connection_probes][business_connection_id] = probe_business_connection(channel, business_connection_id)
    end

    info
  end

  def probe_business_connection(channel, business_connection_id)
    response = HTTParty.get(
      "#{channel.telegram_api_url}/getBusinessConnection",
      query: { business_connection_id: business_connection_id },
      timeout: 15
    )
    body = response.parsed_response || {}

    if response.success? && body['ok']
      result = body['result'] || {}
      {
        ok: true,
        id: result['id'],
        is_enabled: result['is_enabled'],
        can_reply: result['can_reply'],
        user_chat_id: result['user_chat_id']
      }
    else
      {
        ok: false,
        error_code: body['error_code'],
        description: body['description']
      }
    end
  rescue StandardError => e
    {
      ok: false,
      error: e.message
    }
  end

  def build_reports(grouped_failures, conversations_by_id, channel_diagnostics)
    grouped_failures.map do |conversation_id, failures|
      conversation = conversations_by_id[conversation_id]
      next unless conversation

      failure_stats = summarize_failures(failures)
      attrs = conversation.additional_attributes || {}
      channel_info = channel_diagnostics[conversation.inbox.channel_id] || {}

      channel_business_connection_id = channel_info[:channel_business_connection_id]
      conversation_business_connection_id = attrs['business_connection_id']

      conversation_business_probe = nil
      probes = channel_info[:conversation_business_connection_probes] || {}
      conversation_business_probe = probes[conversation_business_connection_id.to_s] if conversation_business_connection_id.present?

      last_incoming_message = conversation.messages.incoming.reorder(created_at: :desc).select(:id, :created_at, :source_id).first

      report = {
        conversation_id: conversation.id,
        conversation_display_id: conversation.display_id,
        inbox_id: conversation.inbox_id,
        account_id: conversation.account_id,
        contact_id: conversation.contact_id,
        contact_name: conversation.contact&.name,
        contact_inbox_source_id: conversation.contact_inbox&.source_id,
        conversation_created_at: conversation.created_at,
        conversation_updated_at: conversation.updated_at,
        failure_count: failure_stats[:count],
        first_failure_at: failure_stats[:first_failure_at],
        last_failure_at: failure_stats[:last_failure_at],
        last_failure_message_id: failure_stats[:last_failure_message_id],
        last_failure_external_error: failure_stats[:last_failure_external_error],
        chat_id: attrs['chat_id'],
        conversation_business_connection_id: conversation_business_connection_id,
        channel_business_connection_id: channel_business_connection_id,
        channel_business_connection_probe: channel_info[:channel_business_connection_probe],
        conversation_business_connection_probe: conversation_business_probe,
        message_thread_id: attrs['message_thread_id'],
        direct_messages_topic_id: attrs['direct_messages_topic_id'],
        last_incoming_message_id: last_incoming_message&.id,
        last_incoming_message_at: last_incoming_message&.created_at,
        last_incoming_source_id: last_incoming_message&.source_id
      }

      report[:probable_causes] = infer_probable_causes(report)
      report
    end.compact
  end

  def summarize_failures(failures)
    sorted = failures.sort_by(&:created_at)
    last = sorted.last

    {
      count: sorted.size,
      first_failure_at: sorted.first.created_at,
      last_failure_at: last.created_at,
      last_failure_message_id: last.id,
      last_failure_external_error: last.content_attributes&.dig('external_error')
    }
  end

  def infer_probable_causes(report)
    causes = []
    chat_id = report[:chat_id]
    source_id = report[:contact_inbox_source_id]
    conversation_business_id = report[:conversation_business_connection_id]
    channel_business_id = report[:channel_business_connection_id]

    causes << 'missing_chat_id' if chat_id.blank?
    causes << 'chat_id_differs_from_contact_inbox_source_id' if source_id.present? && chat_id.present? && source_id.to_s != chat_id.to_s

    if conversation_business_id.blank? && channel_business_id.blank?
      causes << 'business_connection_id_missing_everywhere'
    elsif conversation_business_id.blank? && channel_business_id.present?
      causes << 'business_connection_id_missing_in_conversation'
    elsif conversation_business_id.present? && channel_business_id.present? && conversation_business_id.to_s != channel_business_id.to_s
      causes << 'stale_business_connection_id_in_conversation'
    end

    channel_probe = report[:channel_business_connection_probe]
    if channel_probe.is_a?(Hash) && channel_probe[:ok]
      causes << 'channel_business_connection_disabled' if channel_probe[:is_enabled] == false
      causes << 'channel_business_cannot_reply' if channel_probe[:can_reply] == false
    end

    conversation_probe = report[:conversation_business_connection_probe]
    causes << 'conversation_business_connection_id_invalid' if conversation_probe.is_a?(Hash) && conversation_probe[:ok] == false

    causes << 'topic_metadata_not_stored' if report[:message_thread_id].blank? && report[:direct_messages_topic_id].blank?

    causes << 'no_recent_incoming_message_for_resync' if report[:last_incoming_message_at].blank? || report[:last_incoming_message_at] < 90.days.ago

    causes << PROBABLE_CAUSE_UNKNOWN if causes.empty?
    causes
  end

  def print_summary(reports)
    puts
    puts '=' * 100
    puts 'Summary'
    puts '=' * 100
    puts "Affected conversations: #{reports.size}"
    puts "Total PEER_ID_INVALID failures: #{reports.sum { |r| r[:failure_count] }}"

    causes = reports.flat_map { |r| r[:probable_causes] }.tally.sort_by { |_k, v| -v }
    puts 'Probable causes (count):'
    causes.each do |cause, count|
      puts "  - #{cause}: #{count}"
    end
    puts '=' * 100
    puts
  end

  def print_detailed_report(reports)
    puts 'Detailed conversations:'
    puts

    reports.sort_by { |r| [r[:last_failure_at] || Time.at(0), r[:conversation_id]] }.reverse_each do |report|
      puts "conversation_id=#{report[:conversation_id]} display_id=#{report[:conversation_display_id]} inbox_id=#{report[:inbox_id]}"
      puts "  failures=#{report[:failure_count]} first_failure_at=#{format_time(report[:first_failure_at])} last_failure_at=#{format_time(report[:last_failure_at])}"
      puts "  chat_id=#{report[:chat_id].inspect} contact_inbox_source_id=#{report[:contact_inbox_source_id].inspect}"
      puts "  conversation_business_connection_id=#{report[:conversation_business_connection_id].inspect}"
      puts "  channel_business_connection_id=#{report[:channel_business_connection_id].inspect}"
      puts "  message_thread_id=#{report[:message_thread_id].inspect} direct_messages_topic_id=#{report[:direct_messages_topic_id].inspect}"
      puts "  last_incoming_message_at=#{format_time(report[:last_incoming_message_at])} last_incoming_source_id=#{report[:last_incoming_source_id].inspect}"
      puts "  probable_causes=#{report[:probable_causes].join(', ')}"
      puts "  last_failure_external_error=#{report[:last_failure_external_error].inspect}"
      puts '-' * 100
    end
  end

  def dump_report(reports, channel_diagnostics)
    FileUtils.mkdir_p(Rails.root.join('tmp'))
    path = Rails.root.join(
      'tmp',
      "telegram_peer_id_diagnostic_#{Time.current.utc.strftime('%Y%m%d_%H%M%S')}.json"
    )

    payload = {
      generated_at: Time.current.utc.iso8601,
      settings: {
        inbox_id: inbox_id,
        days_back: days_back,
        limit: limit,
        check_telegram: check_telegram,
        probe_conversation_business_ids: probe_conversation_business_ids,
        max_business_id_probes: max_business_id_probes
      },
      channel_diagnostics: channel_diagnostics,
      conversations: reports
    }

    File.write(path, JSON.pretty_generate(payload))
    puts
    puts "JSON report written to: #{path}"
  end

  def format_time(time)
    time&.utc&.iso8601
  end
end

inbox_id_arg = ARGV[0].to_s.strip
inbox_id = inbox_id_arg.empty? ? nil : inbox_id_arg.to_i
days_back = (ARGV[1] || 120).to_i
limit = (ARGV[2] || 300).to_i

check_telegram = ENV.fetch('CHECK_TELEGRAM', 'true') == 'true'
probe_conversation_business_ids = ENV.fetch('PROBE_CONVERSATION_BUSINESS_IDS', 'true') == 'true'
max_business_id_probes = ENV.fetch('MAX_BUSINESS_ID_PROBES', '20').to_i

TelegramPeerIdDiagnostic.new(
  inbox_id: inbox_id,
  days_back: days_back,
  limit: limit,
  check_telegram: check_telegram,
  probe_conversation_business_ids: probe_conversation_business_ids,
  max_business_id_probes: max_business_id_probes
).run
