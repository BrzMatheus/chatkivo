class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    apply_filters_with_safety
  end

  private

  def apply_filters_with_safety
    return conversations if skip_permission_filter?

    apply_conversation_filters
  rescue StandardError => e
    log_filter_error(e)
    conversations
  end

  def skip_permission_filter?
    user_role == 'administrator' || account_user.nil?
  end

  def log_filter_error(error)
    Rails.logger.error "PermissionFilterService error: #{error.message}"
    Rails.logger.error "  User: #{user&.id}, Account: #{account&.id}, AccountUser: #{account_user&.id}"
    Rails.logger.error "  Backtrace: #{error.backtrace&.first(5)&.join("\n")}"
  end

  def apply_conversation_filters
    base_conversations = accessible_conversations

    if flexible_filters_active?
      apply_flexible_filters(base_conversations)
    else
      apply_legacy_filters(base_conversations)
    end
  end

  def flexible_filters_active?
    account_user.visible_team_ids.present? ||
      account_user.filter_assigned_only ||
      account_user.filter_unassigned_only
  end

  def apply_flexible_filters(base_conversations)
    filtered = apply_visible_team_filter(base_conversations)
    apply_assignee_filters(filtered)
  end

  def apply_visible_team_filter(base_conversations)
    return base_conversations if account_user.visible_team_ids.blank?

    # Keep team-less conversations visible and preserve agent-owned
    # conversations even when team filters are active.
    base_conversations.where(
      'conversations.team_id IN (:team_ids) OR conversations.team_id IS NULL OR conversations.assignee_id = :user_id',
      team_ids: account_user.visible_team_ids,
      user_id: user.id
    )
  end

  def apply_assignee_filters(filtered_conversations)
    if account_user.filter_assigned_only && account_user.filter_unassigned_only
      return filtered_conversations.where('assignee_id IS NULL OR assignee_id = ?', user.id)
    end

    return filtered_conversations.where(assignee_id: user.id) if account_user.filter_assigned_only
    return filtered_conversations.where(assignee_id: nil) if account_user.filter_unassigned_only

    filtered_conversations
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

    # Team conversations that are unassigned OR assigned to the current user.
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
