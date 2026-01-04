json.id resource.id
# could be nil for a deleted agent hence the safe operator before account id
json.account_id Current.account&.id
json.availability_status resource.availability_status
json.auto_offline resource.auto_offline
json.confirmed resource.confirmed?
json.email resource.email
json.provider resource.provider
json.available_name resource.available_name
json.custom_attributes resource.custom_attributes if resource.custom_attributes.present?
json.name resource.name
json.role resource.role
json.thumbnail resource.avatar_url
json.custom_role_id resource.current_account_user&.custom_role_id if ChatwootApp.enterprise?
json.conversation_filter_mode resource.current_account_user&.conversation_filter_mode
json.filter_assigned_only resource.current_account_user&.filter_assigned_only
json.filter_unassigned_only resource.current_account_user&.filter_unassigned_only
json.visible_team_ids resource.current_account_user&.try(:visible_team_ids) || []
