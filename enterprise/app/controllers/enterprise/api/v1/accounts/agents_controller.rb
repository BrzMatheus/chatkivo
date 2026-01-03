module Enterprise::Api::V1::Accounts::AgentsController
  def create
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb:2',
                 message: 'Entrando no Enterprise::AgentsController#create', data: { params: params.to_unsafe_h }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run1', hypothesisId: 'H3' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    super
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb:5', message: 'Super executado com sucesso',
                 data: { agent_id: @agent&.id }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run1', hypothesisId: 'H3' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    associate_agent_with_custom_role
  end

  def update
    super
    associate_agent_with_custom_role
  end

  private

  def associate_agent_with_custom_role
    @agent.current_account_user.update!(custom_role_id: params[:custom_role_id])
  end
end
