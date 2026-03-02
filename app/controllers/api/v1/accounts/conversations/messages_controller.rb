class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  TRANSIENT_API_FAILED_EXTERNAL_ERRORS = [
    'timed out reading data from server'
  ].freeze

  before_action :ensure_api_inbox_for_status_update, only: :update, if: :status_update_request?
  before_action :ensure_supported_inbox_for_content_edit, only: :update, if: :content_edit_request?

  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    return handle_status_update if status_update_request?
    return handle_content_edit if content_edit_request?

    render json: { error: 'Either status or content should be provided' }, status: :unprocessable_entity
  end

  def destroy
    result = Messages::DeleteService.new(message: message).perform
    if result[:success]
      @message = message
    else
      render json: { error: result[:error] }, status: result[:status]
    end
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, :content)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  def transient_api_failed_status_update?
    return false unless permitted_params[:status] == 'failed'

    normalized_error = permitted_params[:external_error].to_s.downcase
    TRANSIENT_API_FAILED_EXTERNAL_ERRORS.any? do |error|
      normalized_error.include?(error)
    end
  end

  def status_update_request?
    permitted_params[:status].present?
  end

  def content_edit_request?
    params.key?(:content)
  end

  def handle_status_update
    if transient_api_failed_status_update?
      Rails.logger.warn(
        '[Api::MessagesController] Ignoring transient failed status update for API inbox message ' \
        "message_id=#{message.id} conversation_id=#{@conversation.id} error=#{permitted_params[:external_error]}"
      )
    else
      Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    end
    @message = message
  end

  def handle_content_edit
    result = Messages::EditService.new(message: message, content: permitted_params[:content]).perform
    if result[:success]
      @message = message
    else
      render json: { error: result[:error] }, status: result[:status]
    end
  end

  # Only API inboxes can use the status update flow
  def ensure_api_inbox_for_status_update
    return if @conversation.inbox.api?

    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden
  end

  def ensure_supported_inbox_for_content_edit
    return if @conversation.inbox.api? || @conversation.inbox.telegram?

    render json: { error: 'Message edit is only allowed for API and Telegram inboxes' }, status: :forbidden
  end
end
