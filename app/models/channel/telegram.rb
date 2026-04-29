# == Schema Information
#
# Table name: channel_telegram
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb
#  bot_name              :string
#  bot_token             :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#
# Indexes
#
#  index_channel_telegram_on_bot_token  (bot_token) UNIQUE
#

class Channel::Telegram < ApplicationRecord
  include Channelable

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :bot_token, deterministic: true if Chatwoot.encryption_configured?

  self.table_name = 'channel_telegram'
  EDITABLE_ATTRS = [:bot_token].freeze

  before_validation :ensure_valid_bot_token, on: :create
  validates :bot_token, presence: true, uniqueness: true
  before_save :setup_telegram_webhook

  def name
    'Telegram'
  end

  def telegram_api_url
    "https://api.telegram.org/bot#{bot_token}"
  end

  def send_message_on_telegram(message)
    message_id = send_message(message) if message.outgoing_content.present?
    message_id = Telegram::SendAttachmentsService.new(message: message).perform if message.attachments.present?
    message_id
  end

  def edit_message_on_telegram(message, content)
    chat_id_value = chat_id(message)
    return failed_result('Telegram chat_id is missing for this conversation') if chat_id_value.blank?
    return failed_result('Telegram source_id is missing for this message') if message.source_id.blank?

    response = HTTParty.post(
      "#{telegram_api_url}/editMessageText",
      body: {
        chat_id: chat_id_value,
        message_id: message.source_id,
        text: convert_markdown_to_telegram_html(content),
        parse_mode: 'HTML'
      }.merge(optional_business_connection_id(message))
    )

    return success_result if telegram_response_success?(response)

    failed_result(telegram_error_message(response))
  rescue StandardError => e
    failed_result(e.message)
  end

  def delete_message_on_telegram(message)
    return failed_result('Telegram source_id is missing for this message') if message.source_id.blank?

    response = if business_connection_id(message).present?
                 message_id_value = Integer(message.source_id, exception: false)
                 return failed_result('Telegram source_id is invalid for business deletion') if message_id_value.blank?

                 HTTParty.post(
                   "#{telegram_api_url}/deleteBusinessMessages",
                   body: {
                     business_connection_id: business_connection_id(message),
                     message_ids: [message_id_value]
                   }.to_json,
                   headers: {
                     'Content-Type' => 'application/json'
                   }
                 )
               else
                 chat_id_value = chat_id(message)
                 return failed_result('Telegram chat_id is missing for this conversation') if chat_id_value.blank?

                 HTTParty.post(
                   "#{telegram_api_url}/deleteMessage",
                   body: {
                     chat_id: chat_id_value,
                     message_id: message.source_id
                   }
                 )
               end

    return success_result if telegram_response_success?(response)

    failed_result(telegram_error_message(response))
  rescue StandardError => e
    failed_result(e.message)
  end

  def get_telegram_profile_image(user_id)
    # get profile image from telegram
    response = HTTParty.get("#{telegram_api_url}/getUserProfilePhotos", query: { user_id: user_id })
    return nil unless response.success?

    photos = response.parsed_response.dig('result', 'photos')
    return if photos.blank?

    get_telegram_file_path(photos.first.last['file_id'])
  end

  def get_telegram_file_path(file_id)
    response = HTTParty.get("#{telegram_api_url}/getFile", query: { file_id: file_id })
    return nil unless response.success?

    "https://api.telegram.org/file/bot#{bot_token}/#{response.parsed_response['result']['file_path']}"
  end

  def process_error(message, response)
    return unless response.parsed_response['ok'] == false

    # https://github.com/TelegramBotAPI/errors/tree/master/json
    message.external_error = "#{response.parsed_response['error_code']}, #{response.parsed_response['description']}"
    message.status = :failed
    message.save!
  end

  def chat_id(message)
    chat_id_value = message.conversation.additional_attributes&.[]('chat_id')
    Rails.logger.info "Telegram chat_id: conversation_id=#{message.conversation.id}, chat_id=#{chat_id_value.inspect}, additional_attributes=#{message.conversation.additional_attributes.inspect}"
    chat_id_value
  end

  def business_connection_id(message)
    channel_business_connection_id = telegram_channel_additional_attributes['business_connection_id']
    conversation_business_connection_id = message.conversation.additional_attributes&.[]('business_connection_id')

    channel_business_connection_id.presence || conversation_business_connection_id
  end

  def persist_business_connection_id!(business_connection_id)
    return false if business_connection_id.blank?
    return false unless telegram_channel_supports_additional_attributes?

    channel_attributes = telegram_channel_additional_attributes
    return false if channel_attributes['business_connection_id'] == business_connection_id

    update_columns(
      additional_attributes: channel_attributes.merge('business_connection_id' => business_connection_id),
      updated_at: Time.current
    )
    true
  rescue StandardError => e
    Rails.logger.warn "[Telegram] Failed to persist business_connection_id on channel #{id}: #{e.message}"
    false
  end

  def message_thread_id(message)
    message.conversation.additional_attributes&.[]('message_thread_id')
  end

  def direct_messages_topic_id(message)
    message.conversation.additional_attributes&.[]('direct_messages_topic_id')
  end

  def reply_parameters(message)
    reply_to_message_id = message.content_attributes&.[]('in_reply_to_external_id')
    return {} if reply_to_message_id.blank?

    { reply_parameters: { message_id: reply_to_message_id }.to_json }
  end

  private

  def success_result
    { success: true }
  end

  def failed_result(error)
    { success: false, error: error }
  end

  def telegram_response_success?(response)
    response.success? && response.parsed_response['ok'] != false
  end

  def telegram_error_message(response)
    return 'Unknown Telegram error' if response.blank?

    parsed_response = response.parsed_response || {}
    return "#{parsed_response['error_code']}, #{parsed_response['description']}" if parsed_response['description'].present?

    response.body.to_s.presence || 'Unknown Telegram error'
  end

  def optional_business_connection_id(message)
    value = business_connection_id(message)
    value.present? ? { business_connection_id: value } : {}
  end

  def telegram_channel_supports_additional_attributes?
    has_attribute?(:additional_attributes)
  rescue StandardError
    false
  end

  def telegram_channel_additional_attributes
    return {} unless telegram_channel_supports_additional_attributes?

    value = self[:additional_attributes]
    value.is_a?(Hash) ? value : {}
  rescue StandardError
    {}
  end

  def ensure_valid_bot_token
    response = HTTParty.get("#{telegram_api_url}/getMe")
    unless response.success?
      errors.add(:bot_token, 'invalid token')
      return
    end

    self.bot_name = response.parsed_response['result']['username']
  end

  def setup_telegram_webhook
    HTTParty.post("#{telegram_api_url}/deleteWebhook")
    response = HTTParty.post("#{telegram_api_url}/setWebhook",
                             body: {
                               url: "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/telegram/#{bot_token}"
                             })
    errors.add(:bot_token, 'error setting up the webook') unless response.success?
  end

  def send_message(message)
    chat_id_value = chat_id(message)
    biz_conn_id = business_connection_id(message)
    message_thread_id_value = message_thread_id(message)
    direct_messages_topic_id_value = direct_messages_topic_id(message)

    Rails.logger.info "Telegram send_message: message_id=#{message.id}, conversation_id=#{message.conversation_id}, " \
                      "chat_id=#{chat_id_value.inspect}, business_connection_id=#{biz_conn_id.inspect}, " \
                      "message_thread_id=#{message_thread_id_value.inspect}, direct_messages_topic_id=#{direct_messages_topic_id_value.inspect}, " \
                      "content=#{message.outgoing_content[0..50]}"

    if chat_id_value.blank?
      Rails.logger.error "Telegram send_message: chat_id vazio para conversa #{message.conversation_id}, additional_attributes=#{message.conversation.additional_attributes.inspect}"
      return nil
    end

    if biz_conn_id.blank?
      Rails.logger.warn "Telegram send_message: business_connection_id vazio para conversa #{message.conversation_id} - aguardando primeira mensagem real do cliente para sincronizar"
    end

    response = message_request(
      chat_id_value,
      message.outgoing_content,
      reply_markup(message),
      reply_parameters(message),
      business_connection_id: biz_conn_id,
      message_thread_id: message_thread_id_value,
      direct_messages_topic_id: direct_messages_topic_id_value
    )
    process_error(message, response)
    message_id = response.parsed_response['result']['message_id'] if response.success?
    Rails.logger.info "Telegram send_message result: success=#{response.success?}, telegram_message_id=#{message_id}, response=#{response.parsed_response.inspect}"
    message_id
  end

  def reply_markup(message)
    return unless message.content_type == 'input_select'

    {
      one_time_keyboard: true,
      inline_keyboard: message.content_attributes['items'].map do |item|
        [{
          text: item['title'],
          callback_data: item['value']
        }]
      end
    }.to_json
  end

  def convert_markdown_to_telegram_html(text)
    # ref: https://core.telegram.org/bots/api#html-style

    # Escape HTML entities first to prevent HTML injection
    # This ensures only markdown syntax is converted, not raw HTML
    escaped_text = CGI.escapeHTML(text)

    # Parse markdown with extensions:
    # - strikethrough: support ~~text~~
    # - hardbreaks: preserve all newlines as <br>
    html = CommonMarker.render_html(escaped_text, [:HARDBREAKS], [:strikethrough]).strip

    # Convert paragraph breaks to double newlines to preserve them
    # CommonMarker creates <p> tags for paragraph breaks, but Telegram doesn't support <p>
    html_with_breaks = html.gsub(%r{</p>\s*<p>}, "\n\n")

    # Remove opening and closing <p> tags
    html_with_breaks = html_with_breaks.gsub(%r{</?p>}, '')

    # Sanitize to only allowed tags
    stripped_html = Rails::HTML5::SafeListSanitizer.new.sanitize(html_with_breaks, tags: %w[b strong i em u ins s strike del a code pre blockquote],
                                                                                   attributes: %w[href])

    # Convert <br /> tags to newlines for Telegram
    stripped_html.gsub(%r{<br\s*/?>}, "\n")
  end

  def message_request(chat_id, text, reply_markup = nil, reply_parameters = {}, business_connection_id: nil,
                      message_thread_id: nil, direct_messages_topic_id: nil)
    optional_body = {}
    optional_body[:business_connection_id] = business_connection_id if business_connection_id
    optional_body[:message_thread_id] = message_thread_id if message_thread_id
    optional_body[:direct_messages_topic_id] = direct_messages_topic_id if direct_messages_topic_id

    body = {
      chat_id: chat_id,
      text: text,
      parse_mode: 'HTML'
    }.merge(optional_body).merge(reply_parameters)
    body[:reply_markup] = reply_markup if reply_markup.present?

    HTTParty.post("#{telegram_api_url}/sendMessage",
                  body: body)
  end
end
