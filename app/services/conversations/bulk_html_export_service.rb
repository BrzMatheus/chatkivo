require 'erb'

class Conversations::BulkHtmlExportService
  TEMPLATE_PATH = Rails.root.join('app/services/conversations/bulk_html_export/template.html.erb')
  STYLESHEET_PATH = Rails.root.join('app/services/conversations/bulk_html_export/style.css')

  pattr_initialize [:conversations!]

  def perform
    ERB.new(TEMPLATE_PATH.read, trim_mode: '-').result(binding)
  end

  private

  def stylesheet
    STYLESHEET_PATH.read
  end

  def messages_for(conversation)
    conversation.messages.reject(&:activity?)
  end

  def definition_value(value)
    value.presence || '-'
  end

  def message_content(message)
    message.processed_message_content.presence || message.content
  end

  def attachment_label(attachment)
    attachment.fallback_title.presence || attachment.file_type || 'attachment'
  end

  def message_row_classes(message)
    classes = ['message-row']
    classes << (message.incoming? ? 'incoming' : 'outgoing')
    classes << 'private' if message.private?
    classes.join(' ')
  end

  def contact_name(conversation)
    conversation.contact&.name.presence || 'Unknown customer'
  end

  def sender_name(message, conversation)
    message.sender&.try(:name).presence || (conversation.contact&.name if message.incoming?) || 'System'
  end

  def initials(name)
    value = name.presence || '?'
    words = value.split.first(2)
    words.filter_map { |word| word.first&.upcase }.join.presence || '?'
  end

  def format_datetime(datetime)
    datetime&.in_time_zone&.strftime('%d %b %Y, %H:%M')
  end

  def format_date(datetime)
    datetime&.in_time_zone&.strftime('%d %b %Y')
  end

  def format_time(datetime)
    datetime&.in_time_zone&.strftime('%H:%M')
  end

  def h(value)
    ERB::Util.html_escape(value.to_s)
  end
end
