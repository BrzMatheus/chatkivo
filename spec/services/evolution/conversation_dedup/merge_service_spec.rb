require 'rails_helper'

RSpec.describe Evolution::ConversationDedup::MergeService do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:jid) { '5511888888888@s.whatsapp.net' }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: jid) }

  let!(:canonical_conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let!(:secondary_conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      additional_attributes: { historical_import: true, historical_import_source: 'evolution_super_admin', historical_import_jid: jid }
    )
  end

  describe '#perform' do
    it 'mescla mensagens publicas, deduplica e remove conversa secundaria' do
      duplicate_source_id = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: canonical_conversation,
        message_type: :incoming,
        source_id: 'WAID:DUP',
        content: 'Original'
      )
      fallback_without_media = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: canonical_conversation,
        message_type: :incoming,
        source_id: nil,
        content: 'Mesmo fallback',
        created_at: Time.zone.at(1_700_000_000)
      )

      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: secondary_conversation,
        message_type: :incoming,
        source_id: 'WAID:DUP',
        content: 'Duplicada'
      )
      unique_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: secondary_conversation,
        message_type: :incoming,
        source_id: 'WAID:UNICA',
        content: 'Unica'
      )
      fallback_with_media = create(
        :message,
        :with_attachment,
        account: account,
        inbox: inbox,
        conversation: secondary_conversation,
        message_type: :incoming,
        source_id: nil,
        content: 'Mesmo fallback',
        created_at: fallback_without_media.created_at
      )

      result = described_class.new(
        account: account,
        inbox: inbox,
        canonical_conversation_id: canonical_conversation.id,
        target_conversation_ids: [secondary_conversation.id],
        operation: 'merge'
      ).perform

      canonical_conversation.reload

      expect(result[:moved_messages]).to eq(2)
      expect(result[:deduplicated_messages]).to eq(2)
      expect(result[:replaced_messages]).to eq(1)
      expect(result[:deleted_conversations]).to eq(1)
      expect { secondary_conversation.reload }.to raise_error(ActiveRecord::RecordNotFound)

      expect(canonical_conversation.messages.where(source_id: duplicate_source_id.source_id).count).to eq(1)
      expect(canonical_conversation.messages.where(source_id: unique_message.source_id).count).to eq(1)

      merged_fallback = canonical_conversation.messages.find_by(content: 'Mesmo fallback')
      expect(merged_fallback.attachments).to be_present
      expect(merged_fallback.id).to eq(fallback_with_media.id)
      expect { fallback_without_media.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#preview' do
    it 'nao altera dados quando em simulacao' do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: secondary_conversation,
        message_type: :incoming,
        source_id: 'WAID:PREVIEW',
        content: 'Preview'
      )

      result = described_class.new(
        account: account,
        inbox: inbox,
        canonical_conversation_id: canonical_conversation.id,
        target_conversation_ids: [secondary_conversation.id],
        operation: 'merge'
      ).preview

      expect(result[:deleted_conversations]).to eq(1)
      expect(canonical_conversation.reload.messages.where(source_id: 'WAID:PREVIEW')).to be_blank
      expect(secondary_conversation.reload).to be_present
    end
  end
end
