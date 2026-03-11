require 'rails_helper'

RSpec.describe Conversations::PermissionFilterService do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:another_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }

  # This inbox_member is used to establish the agent's access to the inbox
  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe '#perform' do
    context 'when user is an administrator' do
      it 'returns all conversations' do
        result = described_class.new(
          account.conversations,
          admin,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user is an agent' do
      it 'returns all conversations with no further filtering' do
        inbox_ids = agent.inboxes.where(account_id: account.id).pluck(:id)

        # The base implementation returns all conversations
        # expecting the caller to filter by assigned inboxes
        result = described_class.new(
          account.conversations.where(inbox_id: inbox_ids),
          agent,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user is an agent with flexible team filters' do
      let!(:team_one) { create(:team, account: account) }
      let!(:team_two) { create(:team, account: account) }
      let!(:team_one_conversation) do
        create(:conversation, account: account, inbox: inbox, team: team_one)
      end
      let!(:team_two_conversation) do
        create(:conversation, account: account, inbox: inbox, team: team_two)
      end
      let!(:mine_other_team_conversation) do
        create(:conversation, account: account, inbox: inbox, team: team_two)
      end

      before do
        mine_other_team_conversation.update!(assignee: agent)

        account.account_users.find_by!(user_id: agent.id).update!(
          visible_team_ids: [team_one.id],
          filter_assigned_only: false,
          filter_unassigned_only: false
        )
      end

      it 'keeps teamless and mine conversations while filtering other teams' do
        result = described_class.new(
          account.conversations,
          agent,
          account
        ).perform

        expect(result).to include(team_one_conversation)
        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result).to include(mine_other_team_conversation)
        expect(result).not_to include(team_two_conversation)
      end
    end
  end
end
