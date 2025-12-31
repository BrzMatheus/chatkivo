module Telegram::IncomingMessageServiceHelpers
  def find_message_by_source_id(source_id)
    return unless source_id

    # Buscar apenas dentro da inbox atual para evitar colisões de source_id entre inboxes
    @existing_message = inbox.messages.find_by(source_id: source_id)
  end

  def message_under_process?
    message_id = telegram_params_message_id.to_s
    return false if message_id.blank?

    # Incluir inbox_id na chave para evitar colisões entre inboxes
    key = redis_message_key(message_id)
    Redis::Alfred.get(key)
  end

  def cache_message_source_id_in_redis
    message_id = telegram_params_message_id.to_s
    return if message_id.blank?

    key = redis_message_key(message_id)
    ::Redis::Alfred.setex(key, true)
  end

  def clear_message_source_id_from_redis
    message_id = telegram_params_message_id.to_s
    return if message_id.blank?

    key = redis_message_key(message_id)
    ::Redis::Alfred.delete(key)
  end

  private

  def redis_message_key(message_id)
    # Incluir inbox_id para evitar colisões de message_id entre diferentes inboxes
    format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: "telegram_#{inbox.id}_#{message_id}")
  end
end
