# Find the various telegram payload samples here: https://core.telegram.org/bots/webhooks#testing-your-bot-with-updates
# https://core.telegram.org/bots/api#available-types

class Telegram::UpdateMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    transform_business_message!
    find_message
    update_message
  rescue StandardError => e
    Rails.logger.error "Error while processing telegram message update #{e.message}"
  end

  private

  def find_message
    @message = inbox.messages.find_by(source_id: params[:edited_message][:message_id].to_s)
  end

  def update_message
    return if @message.blank?

    edited_message = params[:edited_message]

    if edited_message[:text].present?
      @message.update!(content: edited_message[:text])
    elsif edited_message[:caption].present?
      @message.update!(content: edited_message[:caption])
    end
  end

  def transform_business_message!
    params[:edited_message] = params[:edited_business_message] if params[:edited_business_message].present?
  end
end
