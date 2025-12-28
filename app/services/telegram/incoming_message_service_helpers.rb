module Telegram::IncomingMessageServiceHelpers
  def find_message_by_source_id(source_id)
    return unless source_id

    @existing_message = Message.find_by(source_id: source_id)
  end

  def message_under_process?
    message_id = telegram_params_message_id.to_s
    return false if message_id.blank?

    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    Redis::Alfred.get(key)
  end

  def cache_message_source_id_in_redis
    message_id = telegram_params_message_id.to_s
    return if message_id.blank?

    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    ::Redis::Alfred.setex(key, true)
  end

  def clear_message_source_id_from_redis
    message_id = telegram_params_message_id.to_s
    return if message_id.blank?

    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    ::Redis::Alfred.delete(key)
  end
end
