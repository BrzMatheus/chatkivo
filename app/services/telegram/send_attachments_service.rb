require 'faraday/multipart'
require 'ostruct'

# Telegram Attachment APIs: ref: https://core.telegram.org/bots/api#inputfile

# All attachments are sent individually using multipart upload to avoid URL accessibility issues.
# This ensures files are always delivered regardless of Active Storage configuration.

# ref: `https://core.telegram.org/bots/api#sendphoto`
# ref: `https://core.telegram.org/bots/api#sendvideo`
# ref: `https://core.telegram.org/bots/api#sendaudio`
# ref: `https://core.telegram.org/bots/api#senddocument`

# The service will terminate if any of the attachment requests fail when the message has multiple attachments
class Telegram::SendAttachmentsService
  pattr_initialize [:message!]

  def perform
    attachment_message_id = nil

    message.attachments.each do |attachment|
      attachment_message_id = send_attachment(attachment)
      break if attachment_message_id.nil?
    end

    attachment_message_id
  end

  private

  def send_attachment(attachment)
    response = send_attachment_by_type(attachment)
    return extract_attachment_message_id(response) if handle_response(response)

    nil
  end

  def send_attachment_by_type(attachment)
    type = attachment_type(attachment[:file_type])
    chat_id = channel.chat_id(message)
    reply_parameters = channel.reply_parameters(message)

    temp_file_path = save_attachment_to_tempfile(attachment)
    begin
      response = send_file_by_type(type, chat_id, temp_file_path, reply_parameters)
    ensure
      File.delete(temp_file_path) if File.exist?(temp_file_path)
    end
    response
  end

  def attachment_type(file_type)
    { 'audio' => 'audio', 'image' => 'photo', 'file' => 'document', 'video' => 'video' }[file_type] || 'document'
  end

  def send_file_by_type(type, chat_id, file_path, reply_parameters)
    endpoint = endpoint_for_type(type)
    upload_key = upload_key_for_type(type)

    File.open(file_path, 'rb') do |file|
      file_name = File.basename(file_path)
      mime_type = Marcel::MimeType.for(name: file_name) || 'application/octet-stream'

      payload = {
        chat_id: chat_id,
        **business_connection_body,
        **topic_body,
        upload_key => Faraday::Multipart::FilePart.new(file, mime_type, file_name),
        **reply_parameters
      }

      response = multipart_post_connection.post("#{channel.telegram_api_url}/#{endpoint}", payload)
      parse_faraday_response(response)
    end
  end

  def endpoint_for_type(type)
    {
      'photo' => 'sendPhoto',
      'video' => 'sendVideo',
      'audio' => 'sendAudio'
    }[type] || 'sendDocument'
  end

  def upload_key_for_type(type)
    {
      'photo' => :photo,
      'video' => :video,
      'audio' => :audio
    }[type] || :document
  end

  def multipart_post_connection
    @multipart_post_connection ||= Faraday.new do |f|
      f.request :multipart
      f.options.timeout = 300
      f.options.open_timeout = 60
    end
  end

  def parse_faraday_response(response)
    parsed = JSON.parse(response.body)
    OpenStruct.new(success?: response.success?, parsed_response: parsed)
  rescue JSON::ParserError
    OpenStruct.new(
      success?: false,
      parsed_response: {
        'ok' => false,
        'error_code' => response.status,
        'description' => response.reason_phrase
      }
    )
  end

  # Telegram picks up the file name from original field name, so we need to save the file with the original name.
  # Hence not using Tempfile here.
  def save_attachment_to_tempfile(attachment)
    temp_dir = Rails.root.join('tmp/uploads', "telegram-#{attachment.message_id}")
    FileUtils.mkdir_p(temp_dir)
    temp_file_path = File.join(temp_dir, attachment.file.filename.to_s)

    File.open(temp_file_path, 'wb') do |file|
      attachment.file.blob.open do |blob_file|
        IO.copy_stream(blob_file, file)
      end
    end

    temp_file_path
  end

  def handle_response(response)
    return true if response.success?

    Rails.logger.error "Message Id: #{message.id}  - Error sending attachment to telegram:  #{response.parsed_response}"
    channel.process_error(message, response)
    false
  end

  def extract_attachment_message_id(response)
    return unless response.success?

    result = response.parsed_response['result']
    # response will be an array if the request for media group
    # response will be a hash if the request for document
    result.is_a?(Array) ? result.first['message_id'] : result['message_id']
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def business_connection_id
    @business_connection_id ||= channel.business_connection_id(message)
  end

  def message_thread_id
    @message_thread_id ||= channel.message_thread_id(message)
  end

  def direct_messages_topic_id
    @direct_messages_topic_id ||= channel.direct_messages_topic_id(message)
  end

  def business_connection_body
    body = {}
    body[:business_connection_id] = business_connection_id if business_connection_id
    body
  end

  def topic_body
    body = {}
    body[:message_thread_id] = message_thread_id if message_thread_id
    body[:direct_messages_topic_id] = direct_messages_topic_id if direct_messages_topic_id
    body
  end
end
