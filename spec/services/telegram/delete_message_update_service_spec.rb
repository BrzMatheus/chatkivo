require 'rails_helper'

describe Telegram::DeleteMessageUpdateService do
  describe '#perform' do
    let(:telegram_channel) { create(:channel_telegram) }
    let(:conversation) { create(:conversation, inbox: telegram_channel.inbox, account: telegram_channel.account) }
    let!(:message) do
      create(
        :message,
        message_type: :outgoing,
        content: 'hello',
        conversation: conversation,
        account: telegram_channel.account,
        source_id: '101'
      )
    end

    it 'marks matching messages as deleted' do
      params = {
        deleted_business_messages: {
          message_ids: [101]
        }
      }.with_indifferent_access

      described_class.new(inbox: telegram_channel.inbox, params: params).perform

      expect(message.reload.deleted).to be(true)
      expect(message.content).to eq('This message was deleted')
    end
  end
end
