class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    cursor = cursor_for(after_id)
    scoped_messages = messages.reorder('created_at asc, id asc')

    scoped_messages =
      if cursor
        scoped_messages.where(
          '(created_at > ?) OR (created_at = ? AND id > ?)',
          cursor.created_at, cursor.created_at, cursor.id
        )
      else
        scoped_messages.where('id > ?', after_id)
      end

    scoped_messages.limit(100)
  end

  def messages_before(before_id)
    cursor = cursor_for(before_id)
    scoped_messages = messages.reorder('created_at desc, id desc')

    scoped_messages =
      if cursor
        scoped_messages.where(
          '(created_at < ?) OR (created_at = ? AND id < ?)',
          cursor.created_at, cursor.created_at, cursor.id
        )
      else
        scoped_messages.where('id < ?', before_id)
      end

    scoped_messages.limit(20).reverse
  end

  def cursor_messages
    messages.unscope(:includes, :preload, :eager_load)
  end

  def messages_between(after_id, before_id)
    after_cursor = cursor_for(after_id)
    before_cursor = cursor_for(before_id)
    scoped_messages = messages.reorder('created_at asc, id asc')

    scoped_messages =
      if after_cursor
        scoped_messages.where(
          '(created_at > ?) OR (created_at = ? AND id >= ?)',
          after_cursor.created_at, after_cursor.created_at, after_cursor.id
        )
      else
        scoped_messages.where('id >= ?', after_id)
      end

    scoped_messages =
      if before_cursor
        scoped_messages.where(
          '(created_at < ?) OR (created_at = ? AND id < ?)',
          before_cursor.created_at, before_cursor.created_at, before_cursor.id
        )
      else
        scoped_messages.where('id < ?', before_id)
      end

    scoped_messages.limit(1000)
  end

  def messages_latest
    messages.reorder('created_at desc, id desc').limit(20).reverse
  end

  def cursor_for(message_id)
    cursor_messages.select(:id, :created_at).find_by(id: message_id)
  end
end
