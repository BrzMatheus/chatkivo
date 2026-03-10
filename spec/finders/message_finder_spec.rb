require 'rails_helper'

describe MessageFinder do
  subject(:message_finder) { described_class.new(conversation, params) }

  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, email: nil) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: user, contact: contact)
  end

  before do
    create(:message, account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    # this outgoing message creates 2 additional messages because of the email hook execution service
    create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation)
  end

  describe '#perform' do
    context 'with filter_internal_messages false' do
      let(:params) { { filter_internal_messages: false } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with filter_internal_messages true' do
      let(:params) { { filter_internal_messages: true } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 4
      end
    end

    context 'with before attribute' do
      let!(:outgoing) { create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation) }
      let(:params) { { before: outgoing.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with after attribute' do
      let(:params) { { after: conversation.messages.first.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.first.id).to be conversation.messages.second.id
        expect(result.last.message_type).to eq 'outgoing'
      end
    end

    context 'with after and before attribute' do
      let(:params) do
        {
          after: conversation.messages.first.id,
          before: conversation.messages.last.id
        }
      end

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.last.id).to be conversation.messages[-2].id
      end
    end

    context 'when ids are not aligned with created_at for before cursor' do
      let(:params) { { before: cursor_message.id } }
      let!(:newer_message) do
        create(:message, account: account, inbox: inbox, conversation: conversation, created_at: Time.zone.at(1_700_000_050))
      end
      let!(:cursor_message) do
        create(:message, account: account, inbox: inbox, conversation: conversation, created_at: Time.zone.at(1_700_000_040))
      end
      let!(:older_message_with_higher_id) do
        create(:message, account: account, inbox: inbox, conversation: conversation, created_at: Time.zone.at(1_700_000_030))
      end

      it 'uses created_at and id as cursor to fetch the previous timeline' do
        result_ids = message_finder.perform.pluck(:id)

        expect(result_ids).to include(older_message_with_higher_id.id)
        expect(result_ids).not_to include(newer_message.id)
      end
    end

    context 'when before_id does not exist in the conversation scope' do
      let!(:other_conversation) { create(:conversation, account: account, inbox: inbox) }
      let!(:external_before_message) do
        create(:message, account: account, inbox: inbox, conversation: other_conversation, created_at: Time.zone.at(1_700_000_100))
      end
      let(:params) { { before: external_before_message.id } }

      it 'falls back to id cursor filtering' do
        result_ids = message_finder.perform.pluck(:id)
        expected_ids = conversation.messages
                                   .where('id < ?', external_before_message.id)
                                   .reorder('created_at desc, id desc')
                                   .limit(20)
                                   .reverse
                                   .pluck(:id)

        expect(result_ids).to eq(expected_ids)
      end
    end
  end
end
