class Messages::DeleteService
  MESSAGE_NOT_DELETABLE_ERROR = 'This message cannot be deleted'.freeze
  GENERIC_ERROR = 'Unable to delete the message'.freeze

  pattr_initialize [:message!]

  def self.apply_local_deletion!(message)
    return apply_preserved_local_deletion!(message) if preserve_deleted_content?(message)

    ActiveRecord::Base.transaction do
      message.update!(
        content: I18n.t('conversations.messages.deleted'),
        content_type: :text,
        content_attributes: deleted_content_attributes(message)
      )
      message.attachments.destroy_all
    end
  end

  def self.apply_preserved_local_deletion!(message)
    message.update!(content_attributes: deleted_content_attributes(message, preserve_content: true))
  end

  def self.preserve_deleted_content?(message)
    ActiveModel::Type::Boolean.new.cast(message.account.preserve_deleted_message_content)
  end

  def self.deleted_content_attributes(message, preserve_content: false)
    message.content_attributes.to_h.merge(
      deleted: true,
      deleted_content_preserved: preserve_content
    )
  end

  def perform
    return failure(MESSAGE_NOT_DELETABLE_ERROR, :forbidden) unless deletable_message?

    if message.inbox.telegram?
      result = Telegram::DeleteMessageService.new(message: message).perform
      return failure(result[:error], :unprocessable_entity) unless result[:success]
    end

    self.class.apply_local_deletion!(message)
    success
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages.to_sentence.presence || GENERIC_ERROR, :unprocessable_entity)
  rescue StandardError => e
    failure(e.message.presence || GENERIC_ERROR, :unprocessable_entity)
  end

  private

  def deletable_message?
    return deletable_api_message? if message.inbox.api?

    message.outgoing? &&
      !message.private? &&
      !message.activity? &&
      !message_deleted?
  end

  def message_deleted?
    ActiveModel::Type::Boolean.new.cast(message.deleted)
  end

  def deletable_api_message?
    !message.private? &&
      !message.activity? &&
      !message_deleted?
  end

  def success
    { success: true }
  end

  def failure(error, status)
    { success: false, error: error, status: status }
  end
end
