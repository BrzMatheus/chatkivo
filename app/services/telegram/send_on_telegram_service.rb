class Telegram::SendOnTelegramService < Base::SendOnChannelService
  # Exceção para quando chat_id não está disponível ainda
  # Isso permite que o job faça retry após a conversa ser sincronizada
  class ChatIdNotAvailableError < StandardError; end

  private

  def channel_class
    Channel::Telegram
  end

  def perform_reply
    validate_chat_id!

    ## send reply to telegram message api
    # https://core.telegram.org/bots/api#sendmessage
    message_id = channel.send_message_on_telegram(message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def validate_chat_id!
    chat_id_value = conversation.additional_attributes&.dig('chat_id')

    return if chat_id_value.present?
    return if sync_chat_id_from_contact_inbox!

    # Se chat_id não está disponível, pode ser porque a conversa foi criada
    # mas ainda não recebeu a primeira mensagem do cliente via Telegram Business
    Rails.logger.warn "[Telegram] SendOnTelegramService: chat_id não disponível para conversa #{conversation.id}. " \
                      'Tentando sincronizar ou aguardando retry.'

    # Tentar recarregar a conversa para pegar atualizações recentes
    conversation.reload
    chat_id_value = conversation.additional_attributes&.dig('chat_id')

    return if chat_id_value.present?
    return if sync_chat_id_from_contact_inbox!

    # Se ainda não está disponível, lançar exceção para retry
    raise ChatIdNotAvailableError, "chat_id não disponível para conversa #{conversation.id}"
  end

  def sync_chat_id_from_contact_inbox!
    source_chat_id = conversation.contact_inbox&.source_id
    return false if source_chat_id.blank?

    conversation.additional_attributes ||= {}
    return false if conversation.additional_attributes['chat_id'].to_s == source_chat_id.to_s

    conversation.additional_attributes['chat_id'] = source_chat_id.to_s
    conversation.save!
    true
  end

  def inbox
    @inbox ||= message.inbox
  end

  def channel
    @channel ||= inbox.channel
  end
end
