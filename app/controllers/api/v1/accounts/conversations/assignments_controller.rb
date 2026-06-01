class Api::V1::Accounts::Conversations::AssignmentsController < Api::V1::Accounts::Conversations::BaseController
  # assigns agent/team to a conversation
  def create
    if params.key?(:assignee_id) || agent_bot_assignment?
      set_agent
    elsif params.key?(:team_id)
      set_team
    else
      render json: nil
    end
  end

  private

  def set_agent
    assigned_agent_id = csat_assigned_agent_id
    resource = Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform

    send_csat_survey(assigned_agent_id) if send_csat_survey_after_unassign?

    render_agent(resource)
  end

  def render_agent(resource)
    case resource
    when User
      render partial: 'api/v1/models/agent', formats: [:json], locals: { resource: resource }
    when AgentBot
      render partial: 'api/v1/models/agent_bot_slim', formats: [:json], locals: { resource: resource }
    else
      render json: nil
    end
  end

  def set_team
    @team = Current.account.teams.find_by(id: params[:team_id])
    @conversation.update!(team: @team)
    render json: @team
  end

  def agent_bot_assignment?
    params[:assignee_type].to_s == 'AgentBot'
  end

  def send_csat_survey_after_unassign?
    ActiveModel::Type::Boolean.new.cast(params[:send_csat_survey]) && params.key?(:assignee_id) && params[:assignee_id].blank?
  end

  def csat_assigned_agent_id
    return @conversation.assignee_id if @conversation.assignee_id.present?
    return Current.user.id if Current.user.is_a?(User)
  end

  def send_csat_survey(assigned_agent_id)
    CsatSurveyService.new(
      conversation: @conversation,
      assigned_agent_id: assigned_agent_id,
      allow_unresolved: true
    ).perform
  end
end
