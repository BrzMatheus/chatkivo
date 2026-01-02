class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'
    return conversations if account_user.nil?

    apply_conversation_filters
  rescue StandardError => e
    Rails.logger.error "PermissionFilterService error: #{e.message}"
    Rails.logger.error "  User: #{user&.id}, Account: #{account&.id}, AccountUser: #{account_user&.id}"
    Rails.logger.error "  Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
    conversations
  end

  private

  def apply_conversation_filters
    base_conversations = accessible_conversations

    if flexible_filters_active?
      apply_flexible_filters(base_conversations)
    else
      apply_legacy_filters(base_conversations)
    end
  end

  def flexible_filters_active?
    account_user.visible_team_ids.present? || account_user.filter_assigned_only || account_user.filter_unassigned_only
  end

  def apply_flexible_filters(base_conversations)
    filtered = base_conversations

    # Filtro de Times
    filtered = filtered.where(team_id: account_user.visible_team_ids) if account_user.visible_team_ids.present?

    # Filtro de Atribuição (combinado)
    if account_user.filter_assigned_only && account_user.filter_unassigned_only
      filtered = filtered.where('assignee_id IS NULL OR assignee_id = ?', user.id)
    elsif account_user.filter_assigned_only
      filtered = filtered.where(assignee_id: user.id)
    elsif account_user.filter_unassigned_only
      filtered = filtered.where(assignee_id: nil)
    end

    filtered
  end

  def apply_legacy_filters(base_conversations)
    case account_user&.conversation_filter_mode
    when 'team_conversations_only'
      filter_by_team(base_conversations)
    when 'assigned_conversations_only'
      filter_by_assigned(base_conversations)
    when 'unassigned_conversations_only'
      filter_by_unassigned(base_conversations)
    when 'team_unassigned_or_mine'
      filter_by_team_unassigned_or_mine(base_conversations)
    else
      base_conversations
    end
  end

  def accessible_conversations
    return conversations if account.nil?

    user_inboxes = user.inboxes.where(account_id: account.id)
    return conversations.none if user_inboxes.blank?

    conversations.where(inbox: user_inboxes)
  end

  def filter_by_team(base_conversations)
    team_ids = user.teams.where(account_id: account.id).pluck(:id)
    return base_conversations.none if team_ids.empty?

    base_conversations.where(team_id: team_ids)
  end

  def filter_by_assigned(base_conversations)
    base_conversations.where(assignee_id: user.id)
  end

  def filter_by_unassigned(base_conversations)
    base_conversations.where(assignee_id: nil)
  end

  def filter_by_team_unassigned_or_mine(base_conversations)
    team_ids = user.teams.where(account_id: account.id).pluck(:id)
    return base_conversations.none if team_ids.empty?

    # Conversas do time que estão sem agente OU atribuídas ao usuário atual
    base_conversations.where(team_id: team_ids)
                      .where('assignee_id IS NULL OR assignee_id = ?', user.id)
  end

  def account_user
    @account_user ||= AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
