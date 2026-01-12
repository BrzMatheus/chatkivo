class Email::SendOnEmailService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Email
  end

  def perform_reply
    return unless message.email_notifiable_message?

    reply_mail = ConversationReplyMailer.with(account: message.account).email_reply(message).deliver_now
    Rails.logger.info("Email message #{message.id} sent with source_id: #{reply_mail.message_id}")
    message.update(source_id: reply_mail.message_id)
  rescue Net::ReadTimeout => e
    # Some SMTP servers can successfully accept and deliver the email, but close the socket
    # before the client receives the final response, causing a ReadTimeout / Socket closed error.
    # In this scenario, marking the message as failed is a false negative.
    if e.message.include?('Socket:(closed)')
      smtp_host = message.inbox&.channel&.try(:smtp_address)
      Rails.logger.warn(
        '[Email::SendOnEmailService] SMTP timeout after accept (treating as success). ' \
        "message_id=#{message.id} inbox_id=#{message.inbox_id} smtp_host=#{smtp_host} error=#{e.class}: #{e.message}"
      )
      return
    end

    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
    Messages::StatusUpdateService.new(message, 'failed', "#{e.class}: #{e.message}").perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
    Messages::StatusUpdateService.new(message, 'failed', "#{e.class}: #{e.message}").perform
  end
end
