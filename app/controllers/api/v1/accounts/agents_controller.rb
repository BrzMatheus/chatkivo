class Api::V1::Accounts::AgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_agent, except: [:create, :index, :bulk_create]
  before_action :check_authorization
  before_action :validate_limit, only: [:create]
  before_action :validate_limit_for_bulk_create, only: [:bulk_create]

  def index
    @agents = agents
  end

  def create
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'app/controllers/api/v1/accounts/agents_controller.rb:11', message: 'Entrando no AgentsController#create',
                 data: { params: params.to_unsafe_h, account_id: Current.account&.id }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run1', hypothesisId: 'H1' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
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

    update_success = @agent.current_account_user.update(account_user_params.compact)

    render :update if update_success
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
    # #region agent log
    count = agents.count
    max_limit = Current.account.usage_limits[:agents]
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'app/controllers/api/v1/accounts/agents_controller.rb:125', message: 'Calculando available_agent_count',
                 data: { current_count: count, max_limit: max_limit }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run1', hypothesisId: 'H1' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    max_limit - count
  end

  def can_add_agent?
    available_agent_count.positive?
  end

  def delete_user_record(agent)
    DeleteObjectJob.perform_later(agent) if agent.reload.account_users.blank?
  end
end

Api::V1::Accounts::AgentsController.prepend_mod_with('Api::V1::Accounts::AgentsController')
