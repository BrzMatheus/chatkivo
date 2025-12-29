class Webhooks::TelegramEventsJob < ApplicationJob
  queue_as :default

  def perform(params = {})
    return unless params[:bot_token]

    channel = Channel::Telegram.find_by(bot_token: params[:bot_token])

    if channel_is_inactive?(channel)
      log_inactive_channel(channel, params)
      return
    end

    process_event_params(channel, params)
  end

  private

  def channel_is_inactive?(channel)
    return true if channel.blank?
    return true unless channel.account.active?

    false
  end

  def log_inactive_channel(channel, params)
    message = if channel&.id
                "Account #{channel.account.id} is not active for channel #{channel.id}"
              else
                "Channel not found for bot_token: #{params[:bot_token]}"
              end
    Rails.logger.warn("Telegram event discarded: #{message}")
  end

  def process_event_params(channel, params)
    return unless params[:telegram]

    # Ignorar mensagens deletadas - não precisam ser processadas
    if params.dig(:telegram, :deleted_business_messages).present? || params.dig(:telegram, :deleted_message).present?
      Rails.logger.info "Telegram: Ignorando mensagens deletadas - update_id: #{params[:telegram][:update_id]}"
      return
    end

    if params.dig(:telegram, :edited_message).present? || params.dig(:telegram, :edited_business_message).present?
      Telegram::UpdateMessageService.new(inbox: channel.inbox, params: params['telegram'].with_indifferent_access).perform
    elsif params.dig(:telegram, :message).present? || params.dig(:telegram, :business_message).present?
      Telegram::IncomingMessageService.new(inbox: channel.inbox, params: params['telegram'].with_indifferent_access).perform
    else
      Rails.logger.warn "Telegram: Tipo de evento não reconhecido - update_id: #{params[:telegram][:update_id]}, params: #{params[:telegram].keys.inspect}"
    end
  end
end
