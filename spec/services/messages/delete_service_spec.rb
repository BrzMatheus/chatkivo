require 'rails_helper'

describe Messages::DeleteService do
  describe '#perform' do
    context 'when outgoing message can be deleted locally' do
      let(:message) { create(:message, message_type: :outgoing, content: 'hello') }

      it 'applies local tombstone' do
        result = described_class.new(message: message).perform

        expect(result[:success]).to be(true)
        expect(message.reload.deleted).to be(true)
        expect(message.content).to eq('This message was deleted')
      end
    end

    context 'when message is not deletable' do
      let(:message) { create(:message, message_type: :incoming, content: 'hello') }

      it 'returns forbidden' do
        result = described_class.new(message: message).perform

        expect(result[:success]).to be(false)
        expect(result[:status]).to eq(:forbidden)
      end
    end

    context 'when telegram remote delete fails' do
      let(:telegram_channel) { create(:channel_telegram) }
      let(:conversation) do
        create(:conversation, inbox: telegram_channel.inbox, account: telegram_channel.account, additional_attributes: { 'chat_id' => '123' })
      end
      let(:message) do
        create(:message, message_type: :outgoing, conversation: conversation, account: telegram_channel.account, content: 'old', source_id: '111')
      end

      it 'does not apply local deletion' do
        allow(Telegram::DeleteMessageService).to receive(:new)
          .and_return(instance_double(Telegram::DeleteMessageService, perform: { success: false, error: 'telegram failed' }))

        result = described_class.new(message: message).perform

        expect(result[:success]).to be(false)
        expect(result[:status]).to eq(:unprocessable_entity)
        expect(message.reload.deleted).to be_nil
        expect(message.content).to eq('old')
      end
    end
  end
end
