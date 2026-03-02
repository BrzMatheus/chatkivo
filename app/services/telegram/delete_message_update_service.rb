class Telegram::DeleteMessageUpdateService
  pattr_initialize [:inbox!, :params!]

  def perform
    source_ids.each do |source_id|
      message = inbox.messages.find_by(source_id: source_id)
      next if message.blank? || message_deleted?(message)

      Messages::DeleteService.apply_local_deletion!(message)
    end
  end

  private

  def source_ids
    Array(params.dig(:deleted_business_messages, :message_ids)).map(&:to_s).reject(&:blank?)
  end

  def message_deleted?(message)
    ActiveModel::Type::Boolean.new.cast(message.deleted)
  end
end
