class Messages::StatusUpdateService
  attr_reader :message, :status, :external_error, :source_id

  def initialize(message, status = nil, external_error = nil, source_id = nil)
    @message = message
    @status = status
    @external_error = external_error
    @source_id = source_id
  end

  def perform
    return false unless valid_update_request?

    update_message_status
  end

  private

  def update_message_status
    attrs = {}
    if status.present?
      attrs[:status] = status
      attrs[:external_error] = (status == 'failed' ? external_error : nil)
    end
    attrs[:source_id] = source_id if source_id.present?

    message.update!(attrs)
  end

  def valid_update_request?
    return false if status.blank? && source_id.blank?
    return true if status.blank?
    return false unless Message.statuses.key?(status)

    # Don't allow changing from 'read' to 'delivered'
    return false if message.read? && status == 'delivered'

    true
  end
end
