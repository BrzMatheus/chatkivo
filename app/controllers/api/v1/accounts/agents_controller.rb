class Api::V1::Accounts::AgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_agent, except: [:create, :index, :bulk_create]
  before_action :check_authorization
  before_action :validate_limit, only: [:create]
  before_action :validate_limit_for_bulk_create, only: [:bulk_create]

  def index
    @agents = agents
  end

  def create
    builder = AgentBuilder.new(
      email: new_agent_params['email'],
      name: new_agent_params['name'],
      role: new_agent_params['role'],
      availability: new_agent_params['availability'],
      auto_offline: new_agent_params['auto_offline'],
      inviter: current_user,
      account: Current.account
    )

    @agent = builder.perform
  end

  def update
    @agent.update!(agent_params.slice(:name).compact)

    # Extract account user params explicitly instead of using slice with complex keys
    account_user_params = agent_params.slice(:role, :availability, :auto_offline, :conversation_filter_mode, :filter_assigned_only,
                                             :filter_unassigned_only)
    account_user_params[:visible_team_ids] = agent_params[:visible_team_ids] if agent_params.key?(:visible_team_ids)
    account_user_params[:conversation_filter_mode] = normalized_conversation_filter_mode(account_user_params)
    @agent.current_account_user.update!(account_user_params.compact)
  end

  def destroy
    @agent.current_account_user.destroy!
    delete_user_record(@agent)
    head :ok
  end

  def bulk_create
    emails = params[:emails]

    emails.each do |email|
      builder = AgentBuilder.new(
        email: email,
        name: email.split('@').first,
        inviter: current_user,
        account: Current.account
      )
      begin
        builder.perform
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.info "[Agent#bulk_create] ignoring email #{email}, errors: #{e.record.errors}"
      end
    end

    # This endpoint is used to bulk create agents during onboarding
    # onboarding_step key in present in Current account custom attributes, since this is a one time operation
    Current.account.custom_attributes.delete('onboarding_step')
    Current.account.save!
    head :ok
  end

  private

  def check_authorization
    super(User)
  end

  def fetch_agent
    @agent = agents.find(params[:id])
  end

  def account_user_attributes
    [
      :role,
      :availability,
      :auto_offline,
      :conversation_filter_mode,
      :filter_assigned_only,
      :filter_unassigned_only,
      { visible_team_ids: [] }
    ]
  end

  def allowed_agent_params
    [
      :name,
      :email,
      :role,
      :availability,
      :auto_offline,
      :conversation_filter_mode,
      :filter_assigned_only,
      :filter_unassigned_only,
      { visible_team_ids: [] }
    ]
  end

  def agent_params
    params.require(:agent).permit(allowed_agent_params)
  end

  def new_agent_params
    params.require(:agent).permit(:email, :name, :role, :availability, :auto_offline)
  end

  def normalized_conversation_filter_mode(account_user_params)
    return account_user_params[:conversation_filter_mode] unless flexible_filter_params_provided?

    visible_team_ids = account_user_params[:visible_team_ids] || []
    has_visible_teams = visible_team_ids.present?
    filter_assigned_only = ActiveModel::Type::Boolean.new.cast(
      account_user_params[:filter_assigned_only]
    )
    filter_unassigned_only = ActiveModel::Type::Boolean.new.cast(
      account_user_params[:filter_unassigned_only]
    )

    normalized_modes = {
      [true, true, true] => :team_unassigned_or_mine,
      [true, false, false] => :team_conversations_only,
      [false, true, false] => :assigned_conversations_only,
      [false, false, true] => :unassigned_conversations_only
    }

    normalized_modes.fetch(
      [has_visible_teams, filter_assigned_only, filter_unassigned_only],
      :all_conversations
    )
  end

  def flexible_filter_params_provided?
    agent_params.key?(:visible_team_ids) || agent_params.key?(:filter_assigned_only) || agent_params.key?(:filter_unassigned_only)
  end

  def agents
    @agents ||= Current.account.users.order_by_full_name.includes(:account_users, { avatar_attachment: [:blob] })
  end

  def validate_limit_for_bulk_create
    limit_available = params[:emails].count <= available_agent_count

    render_payment_required('Account limit exceeded. Please purchase more licenses') unless limit_available
  end

  def validate_limit
    render_payment_required('Account limit exceeded. Please purchase more licenses') unless can_add_agent?
  end

  def available_agent_count
    Current.account.usage_limits[:agents] - agents.count
  end

  def can_add_agent?
    available_agent_count.positive?
  end

  def delete_user_record(agent)
    DeleteObjectJob.perform_later(agent) if agent.reload.account_users.blank?
  end
end

Api::V1::Accounts::AgentsController.prepend_mod_with('Api::V1::Accounts::AgentsController')
