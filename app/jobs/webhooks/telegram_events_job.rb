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
    unless params[:telegram]
      Rails.logger.warn "[Telegram] Job ignorado - params[:telegram] ausente: #{params.keys.inspect}"
      return
    end

    telegram_params = params['telegram'].with_indifferent_access
    Rails.logger.info "[Telegram] Processando evento: inbox_id=#{channel.inbox.id}, " \
                      "message_id=#{telegram_params.dig(:message, :message_id) || telegram_params.dig(:business_message, :message_id)}, " \
                      "has_message=#{telegram_params[:message].present?}, " \
                      "has_business_message=#{telegram_params[:business_message].present?}, " \
                      "has_business_connection=#{telegram_params[:business_connection].present?}, " \
                      "has_edited=#{telegram_params[:edited_message].present? || telegram_params[:edited_business_message].present?}, " \
                      "has_deleted=#{telegram_params[:deleted_business_messages].present?}"

    if telegram_params[:business_connection].present?
      sync_channel_business_connection_id(channel, telegram_params[:business_connection])
      return
    end

    if telegram_params[:deleted_business_messages].present?
      Telegram::DeleteMessageUpdateService.new(inbox: channel.inbox, params: telegram_params).perform
    elsif telegram_params[:edited_message].present? || telegram_params[:edited_business_message].present?
      Telegram::UpdateMessageService.new(inbox: channel.inbox, params: telegram_params).perform
    else
      Telegram::IncomingMessageService.new(inbox: channel.inbox, params: telegram_params).perform
    end
  end

  def sync_channel_business_connection_id(channel, business_connection_params)
    business_connection_id = business_connection_params[:id]
    return if business_connection_id.blank?

    return unless channel.persist_business_connection_id!(business_connection_id)

    Rails.logger.info "[Telegram] Atualizado business_connection_id no canal #{channel.id}: #{business_connection_id}"
  end
end
