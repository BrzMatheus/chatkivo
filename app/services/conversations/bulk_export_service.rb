require 'csv'

class Conversations::BulkExportService
  HEADER_KEYS = %i[
    conversation_id
    conversation_created_at
    conversation_status
    inbox_name
    customer_name
    customer_email
    customer_phone_number
    assignee_name
    message_id
    message_created_at
    message_type
    sender_name
    sender_type
    private_message
    content_type
    message_content
  ].freeze

  DANGEROUS_CSV_PREFIX = /\A[=+\-@]/

  pattr_initialize [:conversations!]

  def perform
    CSV.generate do |csv|
      csv << headers
      conversations.each { |conversation| add_conversation_rows(csv, conversation) }
    end
  end

  private

  def headers
    HEADER_KEYS.map { |key| I18n.t("reports.conversation_export_csv.#{key}") }
  end

  def add_conversation_rows(csv, conversation)
    messages = conversation.messages.reject(&:activity?)

    return csv << safe_row(conversation_columns(conversation) + empty_message_columns) if messages.blank?

    messages.each do |message|
      csv << safe_row(conversation_columns(conversation) + message_columns(message, conversation))
    end
  end

  def conversation_columns(conversation)
    contact = conversation.contact

    [
      conversation.display_id,
      conversation.created_at,
      conversation.status,
      conversation.inbox&.name,
      contact&.name,
      contact&.email,
      contact&.phone_number,
      conversation.assigned_entity&.name
    ]
  end

  def message_columns(message, conversation)
    [
      message.id,
      message.created_at,
      message.message_type,
      sender_name(message, conversation),
      sender_type(message),
      message.private?,
      message.content_type,
      message.processed_message_content.presence || message.content
    ]
  end

  def empty_message_columns
    Array.new(HEADER_KEYS.length - conversation_columns_count)
  end

  def conversation_columns_count
    8
  end

  def sender_name(message, conversation)
    message.sender&.try(:name).presence || (conversation.contact&.name if message.incoming?)
  end

  def sender_type(message)
    return 'customer' if message.incoming?
    return 'agent' if message.sender_type == 'User'
    return 'bot' if message.sender_type == 'AgentBot'

    message.sender_type.presence || message.message_type
  end

  def safe_row(row)
    row.map { |value| safe_cell(value) }
  end

  def safe_cell(value)
    return if value.nil?

    string_value = value.to_s
    return "'#{string_value}" if string_value.match?(DANGEROUS_CSV_PREFIX)

    string_value
  end
end
