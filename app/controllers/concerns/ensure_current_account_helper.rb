module EnsureCurrentAccountHelper
  private

  def current_account
    @current_account ||= ensure_current_account
    Current.account = @current_account
  end

  def ensure_current_account
    account = Account.find(params[:account_id])
    render_unauthorized('Account is suspended') and return unless account.active?

    if current_user
      return unless account_accessible_for_user?(account)
    elsif @resource.is_a?(AgentBot)
      return unless account_accessible_for_bot?(account)
    end
    account
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
    return true if @resource.account_id == account.id
    return true if @resource.agent_bot_inboxes.find_by(account_id: account.id)

    render_unauthorized('Bot is not authorized to access this account')
    false
  end
end
