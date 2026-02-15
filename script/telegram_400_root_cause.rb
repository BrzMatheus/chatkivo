# frozen_string_literal: true

# Deep probe for Telegram 400 errors on one specific conversation.
#
# Usage:
#   CID=4472 RAILS_ENV=production bundle exec rails runner script/telegram_400_root_cause.rb
#
# Optional:
#   SEND_PROBE=true   # also performs sendMessage probe and deletes it when possible

def safe_channel_additional_attributes(channel)
  return {} unless channel.respond_to?(:has_attribute?) && channel.has_attribute?(:additional_attributes)

  value = channel[:additional_attributes]
  value.is_a?(Hash) ? value : {}
rescue StandardError
  {}
end

def print_probe(label, response)
  body = response.parsed_response || {}
  puts "#{label}: http=#{response.code} ok=#{body['ok'].inspect} error_code=#{body['error_code'].inspect} description=#{body['description'].inspect}"
  body
end

cid = ENV.fetch('CID', '').to_i
display_id = ENV.fetch('DISPLAY_ID', '').to_i
account_id = ENV.fetch('ACCOUNT_ID', '').to_i

send_probe = ENV.fetch('SEND_PROBE', 'false') == 'true'

conversation = if cid.positive?
                 Conversation.includes(:inbox, :contact_inbox).find(cid)
               elsif display_id.positive?
                 scope = Conversation.includes(:inbox, :contact_inbox).where(display_id: display_id)
                 scope = scope.where(account_id: account_id) if account_id.positive?
                 scope.order(id: :desc).first
               end

raise 'Use CID=<conversation_id> OR DISPLAY_ID=<display_id> [ACCOUNT_ID=<account_id>]' if conversation.blank?
raise "Conversation #{cid} is not Telegram" unless conversation.inbox.channel_type == 'Channel::Telegram'

channel = conversation.inbox.channel
api = channel.telegram_api_url

conversation_attrs = conversation.additional_attributes || {}
channel_attrs = safe_channel_additional_attributes(channel)

chat_id = conversation_attrs['chat_id']
conv_business_connection_id = conversation_attrs['business_connection_id']
channel_business_connection_id = channel_attrs['business_connection_id']
message_thread_id = conversation_attrs['message_thread_id']
direct_messages_topic_id = conversation_attrs['direct_messages_topic_id']

puts '=' * 100
puts "Telegram 400 root-cause probe | conversation_id=#{conversation.id} display_id=#{conversation.display_id} inbox_id=#{conversation.inbox_id} account_id=#{conversation.account_id}"
puts '=' * 100
puts "chat_id=#{chat_id.inspect} | contact_inbox_source_id=#{conversation.contact_inbox&.source_id.inspect}"
puts "conversation_business_connection_id=#{conv_business_connection_id.inspect}"
puts "channel_business_connection_id=#{channel_business_connection_id.inspect}"
puts "message_thread_id=#{message_thread_id.inspect} | direct_messages_topic_id=#{direct_messages_topic_id.inspect}"
puts

recent_failed = conversation.messages
                            .where(message_type: Message.message_types[:outgoing], status: Message.statuses[:failed])
                            .order(created_at: :desc)
                            .limit(5)

puts "last_failed_outgoing_count=#{recent_failed.size}"
recent_failed.each do |message|
  puts "  message_id=#{message.id} at=#{message.created_at.utc.iso8601} external_error=#{message.content_attributes&.dig('external_error').inspect}"
end
puts

if chat_id.blank?
  puts 'chat_id is blank -> this alone can cause 400/PEER_ID_INVALID.'
  exit
end

begin
  response = HTTParty.get("#{api}/getChat", query: { chat_id: chat_id }, timeout: 15)
  print_probe('getChat(chat_id)', response)
rescue StandardError => e
  puts "getChat(chat_id): exception=#{e.class}: #{e.message}"
end

[conv_business_connection_id, channel_business_connection_id].compact.map(&:to_s).uniq.each do |business_connection_id|
  response = HTTParty.get(
    "#{api}/getBusinessConnection",
    query: { business_connection_id: business_connection_id },
    timeout: 15
  )
  print_probe("getBusinessConnection(#{business_connection_id})", response)
rescue StandardError => e
  puts "getBusinessConnection(#{business_connection_id}): exception=#{e.class}: #{e.message}"
end

puts
puts 'sendChatAction probes (non-invasive):'
payloads = []
payloads << { chat_id: chat_id, action: 'typing' }
payloads << { chat_id: chat_id, action: 'typing', business_connection_id: conv_business_connection_id } if conv_business_connection_id.present?
payloads << { chat_id: chat_id, action: 'typing', business_connection_id: channel_business_connection_id } if channel_business_connection_id.present?

payloads.each_with_index do |payload, index|
  response = HTTParty.post("#{api}/sendChatAction", body: payload, timeout: 15)
  print_probe("sendChatAction##{index + 1}(#{payload.keys.join(',')})", response)
rescue StandardError => e
  puts "sendChatAction##{index + 1}: exception=#{e.class}: #{e.message}"
end

unless send_probe
  puts
  puts 'SEND_PROBE=false -> skipping sendMessage test.'
  exit
end

puts
puts 'sendMessage probe (creates and then tries to delete):'
send_payload = {
  chat_id: chat_id,
  text: "[diagnostic #{Time.current.utc.iso8601}] telegram_400_root_cause",
  disable_notification: true
}

business_for_send = channel_business_connection_id.presence || conv_business_connection_id
send_payload[:business_connection_id] = business_for_send if business_for_send.present?
send_payload[:message_thread_id] = message_thread_id if message_thread_id.present?
send_payload[:direct_messages_topic_id] = direct_messages_topic_id if direct_messages_topic_id.present?

begin
  send_response = HTTParty.post("#{api}/sendMessage", body: send_payload, timeout: 20)
  send_body = print_probe("sendMessage(keys=#{send_payload.keys.join(',')})", send_response)

  sent_message_id = send_body.dig('result', 'message_id')
  if send_body['ok'] && sent_message_id.present?
    delete_response = HTTParty.post(
      "#{api}/deleteMessage",
      body: { chat_id: chat_id, message_id: sent_message_id },
      timeout: 15
    )
    print_probe("deleteMessage(sent_message_id=#{sent_message_id})", delete_response)
  end
rescue StandardError => e
  puts "sendMessage probe: exception=#{e.class}: #{e.message}"
end
