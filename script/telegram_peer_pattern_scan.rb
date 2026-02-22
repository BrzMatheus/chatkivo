# frozen_string_literal: true

# Batch-scan Telegram conversations to compare why some old conversations still send
# while others fail with PEER_ID_INVALID / chat not found.
#
# Usage examples:
#   RAILS_ENV=production bundle exec rails runner script/telegram_peer_pattern_scan.rb
#   ACCOUNT_ID=17 RAILS_ENV=production bundle exec rails runner script/telegram_peer_pattern_scan.rb
#   ACCOUNT_ID=17 INBOX_ID=22 DAYS_BACK=30 LIMIT=100 RAILS_ENV=production bundle exec rails runner script/telegram_peer_pattern_scan.rb
#   ACCOUNT_ID=17 INBOX_ID=22 DAYS_BACK=60 LIMIT=200 STALE_HOURS=24 ONLY_STALE=true RAILS_ENV=production bundle exec rails runner script/telegram_peer_pattern_scan.rb
#
# Optional env vars:
#   ACCOUNT_ID=<id>             # filter by account
#   INBOX_ID=<id>               # filter by inbox
#   DAYS_BACK=30                # conversations updated in last N days
#   LIMIT=50                    # number of conversations to scan
#   STALE_HOURS=24              # threshold to compare "old but still sends"
#   ONLY_STALE=true|false       # only include conversations older than STALE_HOURS by last incoming
#   PROBE_TELEGRAM=true|false   # if false, only prints DB metadata (no API probes)
#   TIMEOUT=10                  # per-request timeout in seconds
#   SAMPLE_PER_GROUP=10         # rows shown per summary group

require 'json'
require 'fileutils'

class TelegramPeerPatternScan
  def initialize
    @account_id = int_env('ACCOUNT_ID')
    @inbox_id = int_env('INBOX_ID')
    @days_back = int_env('DAYS_BACK', 30)
    @limit = int_env('LIMIT', 50)
    @stale_hours = int_env('STALE_HOURS', 24)
    @only_stale = bool_env('ONLY_STALE', false)
    @probe_telegram = bool_env('PROBE_TELEGRAM', true)
    @timeout = int_env('TIMEOUT', 10)
    @sample_per_group = int_env('SAMPLE_PER_GROUP', 10)
    @now = Time.current
    @since_time = @days_back.days.ago
  end

  def run
    print_header

    conversations = load_conversations
    if conversations.empty?
      puts 'No Telegram conversations matched the selected filters.'
      return
    end

    reports = conversations.map { |conversation| analyze_conversation(conversation) }.compact
    reports = reports.select { |report| include_report?(report) }

    if reports.empty?
      puts 'No conversations left after post-filtering (likely ONLY_STALE=true and no stale conversations matched).'
      return
    end

    print_summary(reports)
    print_group_samples(reports)
    dump_json(reports)
  end

  private

  attr_reader :account_id, :inbox_id, :days_back, :limit, :stale_hours, :only_stale, :probe_telegram, :timeout, :sample_per_group, :now, :since_time

  def int_env(key, default = nil)
    raw = ENV.fetch(key, nil)
    return default if raw.nil? || raw == ''

    raw.to_i
  end

  def bool_env(key, default = false)
    raw = ENV.fetch(key, nil)
    return default if raw.nil? || raw == ''

    raw.to_s.downcase == 'true'
  end

  def safe_channel_additional_attributes(channel)
    return {} unless channel.respond_to?(:has_attribute?) && channel.has_attribute?(:additional_attributes)

    value = channel[:additional_attributes]
    value.is_a?(Hash) ? value : {}
  rescue StandardError
    {}
  end

  def load_conversations
    scope = Conversation
            .joins(:inbox)
            .where(inboxes: { channel_type: 'Channel::Telegram' })
            .where('conversations.updated_at >= ?', since_time)

    scope = scope.where(account_id: account_id) if account_id.present?
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?

    scope
      .includes(:inbox, :contact, :contact_inbox)
      .order(updated_at: :desc)
      .limit(limit)
  end

  def analyze_conversation(conversation)
    return nil unless conversation.inbox&.channel.is_a?(Channel::Telegram)

    attrs = conversation.additional_attributes || {}
    channel = conversation.inbox.channel
    channel_attrs = safe_channel_additional_attributes(channel)

    conv_bc = attrs['business_connection_id'].presence
    channel_bc = channel_attrs['business_connection_id'].presence
    effective_bc = channel_bc || conv_bc

    chat_id = attrs['chat_id'].presence || conversation.contact_inbox&.source_id.presence
    last_incoming = conversation.messages.incoming.reorder(created_at: :desc).select(:id, :created_at, :source_id).first
    last_outgoing = conversation.messages.outgoing.reorder(created_at: :desc).select(:id, :created_at, :status, :source_id).first
    last_failed_outgoing = conversation.messages
                                       .where(message_type: Message.message_types[:outgoing], status: Message.statuses[:failed])
                                       .reorder(created_at: :desc)
                                       .select(:id, :created_at, :content_attributes)
                                       .first
    peer_id_invalid_failures_count = conversation.messages
                                                 .where(message_type: Message.message_types[:outgoing], status: Message.statuses[:failed])
                                                 .where("messages.content_attributes ->> 'external_error' ILIKE ?", '%PEER_ID_INVALID%')
                                                 .count

    report = {
      conversation_id: conversation.id,
      display_id: conversation.display_id,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      status: conversation.status,
      updated_at: conversation.updated_at,
      contact_id: conversation.contact_id,
      contact_name: conversation.contact&.name,
      contact_inbox_source_id: conversation.contact_inbox&.source_id,
      chat_id: chat_id,
      raw_chat_id: attrs['chat_id'],
      conversation_business_connection_id: conv_bc,
      channel_business_connection_id: channel_bc,
      effective_business_connection_id: effective_bc,
      message_thread_id: attrs['message_thread_id'],
      direct_messages_topic_id: attrs['direct_messages_topic_id'],
      last_incoming_at: last_incoming&.created_at,
      last_incoming_message_id: last_incoming&.id,
      last_outgoing_at: last_outgoing&.created_at,
      last_outgoing_message_id: last_outgoing&.id,
      last_outgoing_status: last_outgoing ? Message.statuses.key(last_outgoing.status) : nil,
      last_failed_outgoing_id: last_failed_outgoing&.id,
      last_failed_outgoing_at: last_failed_outgoing&.created_at,
      last_failed_outgoing_error: last_failed_outgoing&.content_attributes&.dig('external_error'),
      peer_id_invalid_failures_count: peer_id_invalid_failures_count,
      probes: {}
    }

    if report[:last_incoming_at].present?
      report[:last_incoming_age_hours] = ((now - report[:last_incoming_at]) / 3600.0).round(2)
      report[:last_incoming_age_bucket] = age_bucket(report[:last_incoming_age_hours])
    else
      report[:last_incoming_age_hours] = nil
      report[:last_incoming_age_bucket] = 'no_incoming'
    end

    if probe_telegram
      run_probes!(report, channel)
    else
      report[:classification] = 'db_only_unprobed'
      report[:classification_reasons] = ['probe_telegram_disabled']
    end

    report
  end

  def include_report?(report)
    return true unless only_stale

    age = report[:last_incoming_age_hours]
    age.present? && age >= stale_hours
  end

  def age_bucket(hours)
    return 'no_incoming' if hours.nil?
    return '<24h' if hours < 24
    return '24h-72h' if hours < 72
    return '72h-7d' if hours < 168
    return '7d-30d' if hours < 720

    '>30d'
  end

  def run_probes!(report, channel)
    chat_id = report[:chat_id]
    conv_bc = report[:conversation_business_connection_id]
    channel_bc = report[:channel_business_connection_id]
    effective_bc = report[:effective_business_connection_id]

    report[:probes][:get_chat] = chat_id.present? ? probe_get_chat(channel, chat_id) : { ok: false, error: 'chat_id_missing' }

    bc_candidates = [conv_bc, channel_bc].compact.map(&:to_s).uniq
    report[:probes][:get_business_connection] = {}
    bc_candidates.each do |bc|
      report[:probes][:get_business_connection][bc] = probe_get_business_connection(channel, bc)
    end

    report[:probes][:send_chat_action_without_bc] =
      chat_id.present? ? probe_send_chat_action(channel, chat_id: chat_id) : { ok: false, error: 'chat_id_missing' }

    if conv_bc.present?
      report[:probes][:send_chat_action_with_conversation_bc] = probe_send_chat_action(channel, chat_id: chat_id, business_connection_id: conv_bc)
    end

    if channel_bc.present?
      report[:probes][:send_chat_action_with_channel_bc] = probe_send_chat_action(channel, chat_id: chat_id, business_connection_id: channel_bc)
    end

    report[:probes][:send_chat_action_with_effective_bc] = if effective_bc.present?
                                                             probe_send_chat_action(channel, chat_id: chat_id, business_connection_id: effective_bc)
                                                           else
                                                             { ok: false, error: 'business_connection_id_missing' }
                                                           end

    classify!(report)
  end

  def probe_get_chat(channel, chat_id)
    response = HTTParty.get("#{channel.telegram_api_url}/getChat", query: { chat_id: chat_id }, timeout: timeout)
    body = response.parsed_response || {}

    {
      http: response.code,
      ok: body['ok'] == true,
      error_code: body['error_code'],
      description: body['description']
    }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def probe_get_business_connection(channel, business_connection_id)
    response = HTTParty.get(
      "#{channel.telegram_api_url}/getBusinessConnection",
      query: { business_connection_id: business_connection_id },
      timeout: timeout
    )
    body = response.parsed_response || {}
    result = body['result'] || {}

    {
      http: response.code,
      ok: body['ok'] == true,
      error_code: body['error_code'],
      description: body['description'],
      id: result['id'],
      is_enabled: result['is_enabled'],
      can_reply: result['can_reply'],
      user_chat_id: result['user_chat_id']
    }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def probe_send_chat_action(channel, chat_id:, business_connection_id: nil)
    return { ok: false, error: 'chat_id_missing' } if chat_id.blank?

    payload = { chat_id: chat_id, action: 'typing' }
    payload[:business_connection_id] = business_connection_id if business_connection_id.present?

    response = HTTParty.post("#{channel.telegram_api_url}/sendChatAction", body: payload, timeout: timeout)
    body = response.parsed_response || {}

    {
      http: response.code,
      ok: body['ok'] == true,
      error_code: body['error_code'],
      description: body['description']
    }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def classify!(report)
    reasons = []
    chat_id = report[:chat_id]
    source_id = report[:contact_inbox_source_id]
    probes = report[:probes] || {}

    get_chat = probes[:get_chat] || {}
    send_without_bc = probes[:send_chat_action_without_bc] || {}
    send_with_effective_bc = probes[:send_chat_action_with_effective_bc] || {}

    effective_bc = report[:effective_business_connection_id]
    bc_probe = effective_bc.present? ? (probes.dig(:get_business_connection, effective_bc.to_s) || {}) : {}

    reasons << 'chat_id_missing' if chat_id.blank?
    reasons << 'chat_id_differs_from_contact_inbox_source_id' if chat_id.present? && source_id.present? && chat_id.to_s != source_id.to_s
    reasons << 'business_connection_id_missing' if effective_bc.blank?
    reasons << 'chat_not_found' if get_chat[:description].to_s.downcase.include?('chat not found')
    reasons << 'send_without_bc_peer_id_invalid' if send_without_bc[:description].to_s.include?('PEER_ID_INVALID')
    reasons << 'send_with_bc_peer_id_invalid' if send_with_effective_bc[:description].to_s.include?('PEER_ID_INVALID')
    reasons << 'business_connection_not_ok' if effective_bc.present? && bc_probe[:ok] == false
    reasons << 'business_connection_disabled' if bc_probe[:ok] == true && bc_probe[:is_enabled] == false
    reasons << 'business_connection_can_reply_false' if bc_probe[:ok] == true && bc_probe.key?(:can_reply) && bc_probe[:can_reply] == false
    reasons << 'stale_over_threshold' if report[:last_incoming_age_hours].present? && report[:last_incoming_age_hours] >= stale_hours

    classification =
      if send_with_effective_bc[:ok] == true
        if effective_bc.present? && send_without_bc[:ok] != true
          'works_only_with_business_connection'
        else
          'works_without_business_connection'
        end
      elsif chat_id.blank?
        'missing_chat_id'
      elsif effective_bc.blank?
        'missing_business_connection_id'
      elsif get_chat[:description].to_s.downcase.include?('chat not found')
        'chat_not_found'
      elsif bc_probe[:ok] == false
        'business_connection_invalid'
      elsif send_with_effective_bc[:description].to_s.include?('PEER_ID_INVALID')
        'peer_id_invalid_with_business_connection'
      elsif bc_probe[:ok] == true && bc_probe[:is_enabled] == false
        'business_connection_disabled'
      elsif bc_probe[:ok] == true && bc_probe.key?(:can_reply) && bc_probe[:can_reply] == false
        'business_connection_cannot_reply'
      elsif send_with_effective_bc[:error_code].present?
        'other_telegram_send_error'
      else
        'unknown'
      end

    report[:classification] = classification
    report[:classification_reasons] = reasons.uniq
    report[:stale_over_threshold] = report[:last_incoming_age_hours].present? && report[:last_incoming_age_hours] >= stale_hours
    report[:works_with_effective_bc] = send_with_effective_bc[:ok] == true
    report[:works_without_bc] = send_without_bc[:ok] == true
    report[:get_chat_ok] = get_chat[:ok] == true
    report[:bc_probe_ok] = bc_probe[:ok] == true
    report[:bc_probe_can_reply] = bc_probe[:can_reply] if bc_probe.key?(:can_reply)
    report[:bc_probe_is_enabled] = bc_probe[:is_enabled] if bc_probe.key?(:is_enabled)
  end

  def print_header
    puts '=' * 110
    puts 'Telegram peer pattern scan (batch compare: "old but works" vs "old and fails")'
    puts '=' * 110
    puts "Generated at: #{now.utc.iso8601}"
    puts "Filters: account_id=#{account_id || 'ALL'} inbox_id=#{inbox_id || 'ALL'} updated_since=#{since_time.utc.iso8601} limit=#{limit}"
    puts "Probe Telegram API: #{probe_telegram} | stale_threshold=#{stale_hours}h | only_stale=#{only_stale}"
    puts '=' * 110
    puts
  end

  def print_summary(reports)
    puts 'Summary'
    puts '-' * 110
    puts "Total scanned: #{reports.size}"

    stale_count = reports.count { |r| r[:stale_over_threshold] }
    stale_working = reports.count { |r| r[:stale_over_threshold] && r[:works_with_effective_bc] }
    stale_failing = reports.count { |r| r[:stale_over_threshold] && !r[:works_with_effective_bc] }
    puts "Stale (>= #{stale_hours}h since last incoming): #{stale_count}"
    puts "Stale + works with business_connection_id: #{stale_working}"
    puts "Stale + fails even with business_connection_id: #{stale_failing}"
    puts

    puts 'By classification:'
    reports.group_by { |r| r[:classification] }.sort_by { |_, rows| -rows.size }.each do |classification, rows|
      stale = rows.count { |r| r[:stale_over_threshold] }
      puts "  #{classification.ljust(40)} total=#{rows.size.to_s.ljust(5)} stale=#{stale}"
    end
    puts

    puts 'Age bucket x outcome (with effective business_connection_id):'
    buckets = reports.group_by { |r| r[:last_incoming_age_bucket] }
    %w[<24h 24h-72h 72h-7d 7d-30d >30d no_incoming].each do |bucket|
      rows = buckets[bucket] || []
      next if rows.empty?

      ok = rows.count { |r| r[:works_with_effective_bc] }
      fail = rows.count { |r| !r[:works_with_effective_bc] }
      puts "  #{bucket.ljust(10)} total=#{rows.size.to_s.ljust(5)} ok=#{ok.to_s.ljust(5)} fail=#{fail}"
    end
    puts

    puts 'Key signals among stale conversations:'
    stale_rows = reports.select { |r| r[:stale_over_threshold] }
    if stale_rows.empty?
      puts '  (none)'
    else
      puts "  getChat ok: #{stale_rows.count { |r| r[:get_chat_ok] }}/#{stale_rows.size}"
      puts "  getBusinessConnection ok: #{stale_rows.count { |r| r[:bc_probe_ok] }}/#{stale_rows.size}"
      puts "  bc can_reply=true: #{stale_rows.count { |r| r[:bc_probe_can_reply] == true }}/#{stale_rows.size}"
      puts "  chat_id != contact_inbox.source_id: #{stale_rows.count do |r|
        r[:chat_id].present? && r[:contact_inbox_source_id].present? && r[:chat_id].to_s != r[:contact_inbox_source_id].to_s
      end}/#{stale_rows.size}"
    end
    puts
  end

  def print_group_samples(reports)
    groups = [
      ['Stale + works', reports.select { |r| r[:stale_over_threshold] && r[:works_with_effective_bc] }],
      ['Stale + fails', reports.select { |r| r[:stale_over_threshold] && !r[:works_with_effective_bc] }],
      ['Peer invalid', reports.select { |r| r[:classification] == 'peer_id_invalid_with_business_connection' }],
      ['Chat not found', reports.select { |r| r[:classification] == 'chat_not_found' }]
    ]

    groups.each do |title, rows|
      next if rows.empty?

      puts title
      puts '-' * 110
      rows.first(sample_per_group).each { |row| print_row(row) }
      puts
    end
  end

  def print_row(row)
    puts [
      "disp=#{row[:display_id]}",
      "conv=#{row[:conversation_id]}",
      "inbox=#{row[:inbox_id]}",
      "status=#{row[:status]}",
      "age_h=#{row[:last_incoming_age_hours].inspect}",
      "class=#{row[:classification]}",
      "getChat=#{row[:get_chat_ok] ? 'ok' : 'fail'}",
      "bc=#{row[:bc_probe_ok] ? 'ok' : 'fail'}",
      "can_reply=#{row[:bc_probe_can_reply].inspect}",
      "send+bc=#{row[:works_with_effective_bc] ? 'ok' : 'fail'}",
      "chat_id=#{row[:chat_id].inspect}",
      "bc_id=#{row[:effective_business_connection_id].inspect}",
      "last_fail=#{row[:last_failed_outgoing_error].inspect}"
    ].join(' | ')
  end

  def dump_json(reports)
    FileUtils.mkdir_p(Rails.root.join('tmp'))
    file_path = Rails.root.join('tmp', "telegram_peer_pattern_scan_#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.json")
    payload = {
      generated_at: Time.current.utc.iso8601,
      filters: {
        account_id: account_id,
        inbox_id: inbox_id,
        days_back: days_back,
        limit: limit,
        stale_hours: stale_hours,
        only_stale: only_stale,
        probe_telegram: probe_telegram
      },
      reports: reports
    }
    File.write(file_path, JSON.pretty_generate(payload))
    puts "JSON report saved to #{file_path}"
  end
end

TelegramPeerPatternScan.new.run
