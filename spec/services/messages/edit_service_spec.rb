require 'rails_helper'

describe Messages::EditService do
  describe '#perform' do
    context 'when api inbox and editable outgoing message' do
      let(:channel_api) { create(:channel_api) }
      let(:conversation) { create(:conversation, inbox: channel_api.inbox, account: channel_api.account) }
      let(:message) { create(:message, message_type: :outgoing, conversation: conversation, account: channel_api.account, content: 'old') }

      it 'updates the content locally' do
        result = described_class.new(message: message, content: 'new content').perform

        expect(result[:success]).to be(true)
        expect(message.reload.content).to eq('new content')
      end
    end

    context 'when message is not editable' do
      let(:message) { create(:message, message_type: :incoming, content: 'incoming') }

      it 'returns forbidden' do
        result = described_class.new(message: message, content: 'new').perform

        expect(result[:success]).to be(false)
        expect(result[:status]).to eq(:forbidden)
      end
    end

    context 'when content is blank' do
      let(:channel_api) { create(:channel_api) }
      let(:conversation) { create(:conversation, inbox: channel_api.inbox, account: channel_api.account) }
      let(:message) { create(:message, message_type: :outgoing, conversation: conversation, account: channel_api.account, content: 'old') }

      it 'returns unprocessable_entity' do
        result = described_class.new(message: message, content: '   ').perform

        expect(result[:success]).to be(false)
        expect(result[:status]).to eq(:unprocessable_entity)
      end
    end

    context 'when telegram remote edit fails' do
      let(:telegram_channel) { create(:channel_telegram) }
      let(:conversation) do
        create(:conversation, inbox: telegram_channel.inbox, account: telegram_channel.account, additional_attributes: { 'chat_id' => '123' })
      end
      let(:message) do
        create(:message, message_type: :outgoing, conversation: conversation, account: telegram_channel.account, content: 'old', source_id: '111')
      end

      it 'does not update local message content' do
        allow(Telegram::EditMessageService).to receive(:new)
          .and_return(instance_double(Telegram::EditMessageService, perform: { success: false, error: 'telegram failed' }))

        result = described_class.new(message: message, content: 'new').perform

        expect(result[:success]).to be(false)
        expect(result[:status]).to eq(:unprocessable_entity)
        expect(message.reload.content).to eq('old')
      end
    end
  end
end
