class Api::V1::Accounts::BulkActionsController < Api::V1::Accounts::BaseController
  def create
    case normalized_type
    when 'Conversation'
      enqueue_conversation_job
      head :ok
    when 'Contact'
      check_authorization_for_contact_action
      enqueue_contact_job
      head :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def export_conversations
    conversations = exportable_conversations
    authorize_conversation_exports(conversations)

    send_data(
      Conversations::BulkExportService.new(conversations: conversations).perform,
      filename: "selected-conversations-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv",
      type: 'text/csv; charset=utf-8',
      disposition: 'attachment'
    )
  end

  private

  def normalized_type
    params[:type].to_s.camelize
  end

  def enqueue_conversation_job
    ::BulkActionsJob.perform_later(
      account: @current_account,
      user: current_user,
      params: conversation_params
    )
  end

  def enqueue_contact_job
    Contacts::BulkActionJob.perform_later(
      @current_account.id,
      current_user.id,
      contact_params
    )
  end

  def exportable_conversations
    @current_account.conversations
                    .where(display_id: export_conversation_params[:ids])
                    .includes(:contact, :inbox, :assignee, :assignee_agent_bot, messages: :sender)
                    .order(:display_id)
  end

  def authorize_conversation_exports(conversations)
    conversations.each { |conversation| authorize conversation, :show? }
  end

  def export_conversation_params
    params.permit(ids: [])
  end

  def delete_contact_action?
    params[:action_name] == 'delete'
  end

  def check_authorization_for_contact_action
    authorize(Contact, :destroy?) if delete_contact_action?
  end

  def conversation_params
    # TODO: Align conversation payloads with the `{ action_name, action_attributes }`
    # and then remove this method in favor of a common params method.
    base = params.permit(
      :snoozed_until,
      fields: [:status, :assignee_id, :team_id]
    )
    append_common_bulk_attributes(base)
  end

  def contact_params
    # TODO: remove this method in favor of a common params method.
    # once legacy conversation payloads are migrated.
    append_common_bulk_attributes({})
  end

  def append_common_bulk_attributes(base_params)
    # NOTE: Conversation payloads historically diverged per action. Going forward we
    # want all objects to share a common contract: `{ action_name, action_attributes }`
    common = params.permit(:type, :action_name, ids: [], labels: [add: [], remove: []])
    base_params.merge(common)
  end
end
