class AddFlexibleFiltersToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :visible_team_ids, :integer, array: true, default: []
    add_column :account_users, :filter_assigned_only, :boolean, default: false
    add_column :account_users, :filter_unassigned_only, :boolean, default: false
  end
end
