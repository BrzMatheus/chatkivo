module EnsureCurrentAccountHelper
  private

  def current_account
    @current_account ||= ensure_current_account
    Current.account = @current_account
  end

  def ensure_current_account
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'app/controllers/concerns/ensure_current_account_helper.rb:9', message: 'Iniciando ensure_current_account',
                 data: { account_id: params[:account_id], current_user_id: current_user&.id }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run2', hypothesisId: 'H1' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    account = Account.find(params[:account_id])
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'app/controllers/concerns/ensure_current_account_helper.rb:13', message: 'Conta encontrada',
                 data: { account_id: account.id, status: account.status }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run2', hypothesisId: 'H1' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    render_unauthorized('Account is suspended') and return unless account.active?

    if current_user
      account_accessible_for_user?(account)
    elsif @resource.is_a?(AgentBot)
      account_accessible_for_bot?(account)
    end
    account
  rescue StandardError => e
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'app/controllers/concerns/ensure_current_account_helper.rb:24', message: 'Erro em ensure_current_account',
                 data: { error: e.message, backtrace: e.backtrace[0..5] }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run2', hypothesisId: 'H1' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    raise e
  end

  def account_accessible_for_user?(account)
    @current_account_user = account.account_users.find_by(user_id: current_user.id)
    Current.account_user = @current_account_user
    unless @current_account_user
      render_unauthorized('You are not authorized to access this account')
      return false
    end
    true
  end

  def account_accessible_for_bot?(account)
    return if @resource.account_id == account.id
    return if @resource.agent_bot_inboxes.find_by(account_id: account.id)

    render_unauthorized('Bot is not authorized to access this account')
  end
end
