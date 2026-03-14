require 'csv'
require 'json'

# rubocop:disable Metrics/ClassLength
class Evolution::ImportHistoryService
  pattr_initialize [:account!, :inbox!, :import_file_data!, :dry_run]

  REPORT_HEADERS = %w[
    row_no jid status reason
    source_conversation_id new_conversation_id resolved_contact_id resolved_contact_inbox_id
    chatwoot_count evolution_count merged_count inserted_count
    collision_preference first_at last_at
  ].freeze

  PROCESSED_STATUSES = %w[dry_run inserted].freeze

  def perform
    raise 'Inbox must be an API inbox' unless inbox.api?

    rows = parse_json_file.each_with_index.map { |chat, index| process_chat(chat, index + 1) }

    {
      processed_records: rows.count { |row| PROCESSED_STATUSES.include?(row[:status]) },
      total_records: rows.count,
      errors: rows.select { |row| row[:status] == 'error' }.map { |row| "[row #{row[:row_no]}] #{row[:reason]}" },
      report_csv: build_report_csv(rows)
    }
  end

  private

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def process_chat(chat, row_no)
    row = default_row(row_no, chat)
    jid = normalize_jid(chat['remoteJid'])
    records = Array(chat['records'])

    row[:jid] = jid

    unless canonical_jid?(jid)
      row[:status] = 'skipped'
      row[:reason] = 'jid nao canonico; apenas @s.whatsapp.net e suportado'
      return row
    end

    if records.empty?
      row[:status] = 'skipped'
      row[:reason] = 'chat sem registros'
      return row
    end

    contact_inbox = resolve_contact_inbox(jid, chat, records)
    source_conversation = resolve_source_conversation(contact_inbox)
    contact_id = contact_inbox&.contact_id
    chatwoot_messages = normalize_chatwoot_messages(source_conversation, contact_id)
    evolution_messages = normalize_evolution_records(records, contact_id)

    row[:source_conversation_id] = source_conversation&.id
    row[:resolved_contact_id] = contact_id
    row[:resolved_contact_inbox_id] = contact_inbox&.id
    row[:chatwoot_count] = chatwoot_messages.size
    row[:evolution_count] = evolution_messages.size

    if chatwoot_messages.empty? && evolution_messages.empty?
      row[:status] = 'skipped'
      row[:reason] = 'nenhuma mensagem valida para importar'
      return row
    end

    preference = choose_collision_preference(chatwoot_messages.size, evolution_messages.size)
    merged_messages = merge_timelines(chatwoot_messages, evolution_messages, preference)

    row[:collision_preference] = preference
    row[:merged_count] = merged_messages.size
    row[:first_at] = merged_messages.first&.dig(:created_at)&.utc&.iso8601
    row[:last_at] = merged_messages.last&.dig(:created_at)&.utc&.iso8601

    if merged_messages.empty?
      row[:status] = 'skipped'
      row[:reason] = 'merge resultou em zero mensagens'
      return row
    end

    if dry_run_mode?
      row[:status] = 'dry_run'
      row[:reason] = 'dry run habilitado; sem insercao'
      return row
    end

    target_conversation = resolve_target_conversation!(contact_inbox, source_conversation, jid)
    insertable_messages = filter_insertable_messages(chatwoot_messages, merged_messages)
    insert_rows = build_insert_rows(target_conversation, insertable_messages)

    # rubocop:disable Rails/SkipsModelValidations
    Message.insert_all!(insert_rows) if insert_rows.any?
    # rubocop:enable Rails/SkipsModelValidations

    row[:new_conversation_id] = target_conversation.id
    row[:inserted_count] = insert_rows.size
    row[:status] = 'inserted'
    row
  rescue StandardError => e
    row[:status] = 'error'
    row[:reason] = e.message
    row
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  def default_row(row_no, chat)
    {
      row_no: row_no,
      jid: normalize_jid(chat['remoteJid']),
      status: 'pending',
      reason: nil,
      source_conversation_id: nil,
      new_conversation_id: nil,
      resolved_contact_id: nil,
      resolved_contact_inbox_id: nil,
      chatwoot_count: 0,
      evolution_count: 0,
      merged_count: 0,
      inserted_count: 0,
      collision_preference: nil,
      first_at: nil,
      last_at: nil
    }
  end

  def parse_json_file
    data = import_file_data.to_s.force_encoding('UTF-8')
    clean_data = data.valid_encoding? ? data : data.encode('UTF-16le', invalid: :replace, replace: '').encode('UTF-8')
    parsed = JSON.parse(clean_data)

    raise 'Formato JSON invalido: esperado um array de chats' unless parsed.is_a?(Array)

    parsed
  rescue JSON::ParserError => e
    raise "Arquivo JSON invalido: #{e.message}"
  end

  def build_report_csv(rows)
    CSV.generate do |csv|
      csv << REPORT_HEADERS
      rows.each do |row|
        csv << REPORT_HEADERS.map { |header| row[header.to_sym] }
      end
    end
  end

  def normalize_jid(jid)
    jid.to_s.strip.downcase
  end

  def canonical_jid?(jid)
    jid.end_with?('@s.whatsapp.net')
  end

  def resolve_contact_inbox(jid, chat, records)
    existing_contact_inbox = inbox.contact_inboxes.find_by(source_id: jid)
    return existing_contact_inbox if existing_contact_inbox
    return nil if dry_run_mode?

    ContactInboxWithContactBuilder.new(
      inbox: inbox,
      source_id: jid,
      contact_attributes: {
        identifier: "evolution:#{jid}",
        name: contact_name_from(chat, records, jid),
        phone_number: phone_number_from_jid(jid),
        custom_attributes: { evolution_remote_jid: jid }
      }.compact
    ).perform
  end

  def contact_name_from(chat, records, jid)
    return chat['name'].to_s.strip if chat['name'].present?

    push_name = records.find { |record| record['pushName'].present? }&.dig('pushName').to_s.strip
    return push_name if push_name.present? && push_name != 'Voce'

    "Evolution #{jid.split('@').first}"
  end

  def phone_number_from_jid(jid)
    number = jid.split('@').first.to_s.strip
    return if number.blank? || number.match?(/\D/)

    "+#{number}"
  end

  def resolve_source_conversation(contact_inbox)
    return nil unless contact_inbox

    conversations = Conversation.where(
      account_id: account.id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id
    ).order(updated_at: :desc, id: :desc)

    conversations.detect { |conversation| conversation.additional_attributes.to_h['historical_import'] != true } || conversations.first
  end

  # rubocop:disable Metrics/MethodLength
  def normalize_chatwoot_messages(source_conversation, contact_id)
    return [] unless source_conversation

    Message.where(conversation_id: source_conversation.id)
           .where(private: false)
           .where.not(message_type: Message.message_types[:activity])
           .order(:created_at, :id)
           .filter_map do |message|
      message_type = normalize_chatwoot_message_type(message)
      content = message.content.to_s.strip
      next if content.blank?

      created_at = message.created_at || Time.current
      {
        source: 'chatwoot',
        source_id: canonical_source_id(message.source_id),
        fallback_key: fallback_key(created_at, message_type, content),
        created_at: created_at,
        message_type: message_type,
        content: content,
        sender_id: message_type.zero? ? contact_id : nil,
        sender_type: message_type.zero? ? 'Contact' : nil
      }
    end
  end
  # rubocop:enable Metrics/MethodLength

  def normalize_chatwoot_message_type(message)
    raw_type = if message.respond_to?(:message_type_before_type_cast)
                 message.message_type_before_type_cast
               else
                 message[:message_type]
               end

    case raw_type
    when 1, '1', 'outgoing', 3, '3', 'template' then 1
    when 0, '0', 'incoming' then 0
    else
      message.outgoing? ? 1 : 0
    end
  end

  # rubocop:disable Metrics/MethodLength
  def normalize_evolution_records(records, contact_id)
    sorted_records = Array(records).sort_by do |record|
      [record['messageTimestamp'].to_i, record['wa_id'].to_s, record['evo_id'].to_s]
    end

    sorted_records.filter_map do |record|
      content = extract_content(record)
      next if content.blank?

      message_type = ActiveModel::Type::Boolean.new.cast(record['fromMe']) ? 1 : 0
      created_at = created_at_from_timestamp(record['messageTimestamp'])
      source_id = canonical_source_id_from_evolution(record)

      {
        source: 'evolution',
        source_id: source_id,
        fallback_key: fallback_key(created_at, message_type, content),
        created_at: created_at,
        message_type: message_type,
        content: content,
        sender_id: message_type.zero? ? contact_id : nil,
        sender_type: message_type.zero? ? 'Contact' : nil
      }
    end
  end
  # rubocop:enable Metrics/MethodLength

  def extract_content(record)
    return record['content'].to_s.strip if record['content'].present?

    message_payload = record['message'] || record['data'] || {}
    [
      message_payload['conversation'],
      message_payload.dig('extendedTextMessage', 'text'),
      message_payload.dig('imageMessage', 'caption'),
      message_payload.dig('videoMessage', 'caption'),
      message_payload.dig('documentMessage', 'caption')
    ].compact.map(&:to_s).map(&:strip).find(&:present?).to_s
  end

  def created_at_from_timestamp(raw_timestamp)
    timestamp = raw_timestamp.to_i
    return Time.current if timestamp <= 0

    Time.at(timestamp).utc
  end

  def canonical_source_id_from_evolution(record)
    wa_id = record['wa_id'].to_s.strip
    return "WAID:#{wa_id}" if wa_id.present?

    source_id = canonical_source_id(record['source_id'])
    return source_id if source_id.present?

    evo_id = record['evo_id'].to_s.strip
    return "EVO:#{evo_id}" if evo_id.present?

    nil
  end

  def canonical_source_id(raw_source_id)
    source_id = raw_source_id.to_s.strip
    return if source_id.blank?

    match = source_id.match(/\A(?:waid:|wa:|evo:wa:)(.+)\z/i)
    return "WAID:#{match[1]}" if match

    source_id
  end

  def fallback_key(created_at, message_type, content)
    direction = message_type == 1 ? 'outgoing' : 'incoming'
    normalized_content = content.to_s.gsub(/\s+/, ' ').strip
    "fb:#{created_at.to_i}:#{direction}:#{normalized_content}"
  end

  def choose_collision_preference(chatwoot_count, evolution_count)
    chatwoot_count >= evolution_count ? 'chatwoot' : 'evolution'
  end

  def merge_timelines(chatwoot_messages, evolution_messages, preference)
    merged_messages = {}

    (chatwoot_messages + evolution_messages).each do |message|
      key = message[:source_id].presence || message[:fallback_key]
      existing = merged_messages[key]

      merged_messages[key] = choose_winner(existing, message, preference)
    end

    merged_messages.values.sort_by do |message|
      [message[:created_at].to_f, message[:message_type], message[:source_id].to_s, message[:content].to_s]
    end
  end

  def choose_winner(existing, candidate, preference)
    return candidate unless existing

    preferred_source = preference if %w[chatwoot evolution].include?(preference)
    return existing if preferred_source && existing[:source] == preferred_source
    return candidate if preferred_source && candidate[:source] == preferred_source

    existing
  end

  def resolve_target_conversation!(contact_inbox, source_conversation, jid)
    return source_conversation.tap { |conversation| ensure_import_metadata!(conversation, jid) } if source_conversation

    Conversation.create!(
      account: account,
      inbox: inbox,
      contact: contact_inbox.contact,
      contact_inbox: contact_inbox,
      status: :open,
      additional_attributes: {
        'historical_import_source' => 'evolution_super_admin',
        'historical_import_jid' => jid
      }
    )
  end

  def ensure_import_metadata!(conversation, jid)
    attrs = conversation.additional_attributes.to_h
    updated_attrs = attrs.merge(
      'historical_import_source' => 'evolution_super_admin',
      'historical_import_jid' => jid
    )
    return if attrs == updated_attrs

    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_columns(additional_attributes: updated_attrs, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def filter_insertable_messages(chatwoot_messages, merged_messages)
    existing_keys = chatwoot_messages.each_with_object({}) do |message, keys|
      key = message_identity_key(message)
      keys[key] = true if key.present?
    end

    merged_messages.filter_map do |message|
      key = message_identity_key(message)
      next if key.present? && existing_keys[key]

      message
    end
  end

  def message_identity_key(message)
    message[:source_id].presence || message[:fallback_key]
  end

  def build_insert_rows(target_conversation, merged_messages)
    now = Time.current

    merged_messages.map do |message|
      {
        account_id: account.id,
        inbox_id: inbox.id,
        conversation_id: target_conversation.id,
        message_type: message[:message_type],
        content: message[:content],
        content_type: Message.content_types[:text],
        private: false,
        source_id: message[:source_id],
        created_at: message[:created_at],
        updated_at: now,
        sender_id: message[:sender_id],
        sender_type: message[:sender_type]
      }
    end
  end

  def dry_run_mode?
    dry_run_value = dry_run
    dry_run_value = true if dry_run_value.nil?

    ActiveModel::Type::Boolean.new.cast(dry_run_value)
  end

  # rubocop:enable Metrics/ClassLength
end
