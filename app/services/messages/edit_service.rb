class Messages::EditService
  CHANNEL_NOT_SUPPORTED_ERROR = 'Message edit is only allowed for API and Telegram inboxes'.freeze
  MESSAGE_NOT_EDITABLE_ERROR = 'This message cannot be edited'.freeze
  BLANK_CONTENT_ERROR = 'Message content cannot be blank'.freeze
  GENERIC_ERROR = 'Unable to edit the message'.freeze

  pattr_initialize [:message!, :content!]

  def perform
    return failure(MESSAGE_NOT_EDITABLE_ERROR, :forbidden) unless editable_message?
    return failure(CHANNEL_NOT_SUPPORTED_ERROR, :forbidden) unless supported_inbox?
    return failure(BLANK_CONTENT_ERROR, :unprocessable_entity) if content.to_s.strip.blank?

    if message.inbox.telegram?
      result = Telegram::EditMessageService.new(message: message, content: content).perform
      return failure(result[:error], :unprocessable_entity) unless result[:success]
    end

    message.update!(content: content)
    success
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages.to_sentence.presence || GENERIC_ERROR, :unprocessable_entity)
  rescue StandardError => e
    failure(e.message.presence || GENERIC_ERROR, :unprocessable_entity)
  end

  private

  def editable_message?
    message.outgoing? &&
      !message.private? &&
      !message.activity? &&
      !message_deleted? &&
      message.text? &&
      message.attachments.blank?
  end

  def supported_inbox?
    message.inbox.api? || message.inbox.telegram?
  end

  def message_deleted?
    ActiveModel::Type::Boolean.new.cast(message.deleted)
  end

  def success
    { success: true }
  end

  def failure(error, status)
    { success: false, error: error, status: status }
  end
end
