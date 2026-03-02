class Telegram::EditMessageService
  INVALID_CHANNEL_ERROR = 'Invalid telegram channel'.freeze

  pattr_initialize [:message!, :content!]

  def perform
    return failure(INVALID_CHANNEL_ERROR) unless message.inbox.channel.is_a?(Channel::Telegram)

    message.inbox.channel.edit_message_on_telegram(message, content)
  rescue StandardError => e
    failure(e.message)
  end

  private

  def failure(error)
    { success: false, error: error }
  end
end
