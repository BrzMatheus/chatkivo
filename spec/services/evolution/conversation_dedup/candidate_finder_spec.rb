require 'rails_helper'

RSpec.describe Evolution::ConversationDedup::CandidateFinder do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:jid) { '5511999999999@s.whatsapp.net' }
  let(:contact) { create(:contact, account: account, identifier: "evolution:#{jid}") }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: jid) }

  describe '#perform' do
    it 'sugere como canonica a conversa com midia quando o par texto x midia existir' do
      conversation_text = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: { historical_import: false }
      )
      conversation_media = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: {
          historical_import: true,
          historical_import_source: 'evolution_super_admin',
          historical_import_jid: jid
        }
      )

      create(:message, account: account, inbox: inbox, conversation: conversation_text, message_type: :incoming, content: 'Texto')
      create(:message, :with_attachment, account: account, inbox: inbox, conversation: conversation_media, message_type: :incoming,
                                         content: 'Com midia')

      groups = described_class.new(account: account, inbox: inbox).perform
      group = groups.first

      expect(groups.size).to eq(1)
      expect(group[:group_key]).to eq(jid)
      expect(group[:suggested_canonical_conversation_id]).to eq(conversation_media.id)
      expect(group[:suggested_target_conversation_ids]).to contain_exactly(conversation_text.id)
    end

    it 'desempata conversa somente texto priorizando integridade estrutural' do
      canonical_conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: { historical_import: false }
      )
      secondary_conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: {
          historical_import: true,
          historical_import_source: 'evolution_super_admin',
          historical_import_jid: jid
        }
      )

      create(:message, account: account, inbox: inbox, conversation: canonical_conversation, message_type: :incoming, source_id: 'WAID:A1',
                       content: 'A')
      create(:message, account: account, inbox: inbox, conversation: secondary_conversation, message_type: :incoming, source_id: nil, content: 'A')

      groups = described_class.new(account: account, inbox: inbox).perform

      expect(groups.first[:suggested_canonical_conversation_id]).to eq(canonical_conversation.id)
    end
  end

  describe '#apply_send_locks!' do
    it 'trava envio nas nao canonicas e remove trava da canonica' do
      canonical_conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: { historical_import: false, dedupe_send_blocked: true }
      )
      secondary_conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: {
          historical_import: true,
          historical_import_source: 'evolution_super_admin',
          historical_import_jid: jid
        }
      )

      create(:message, :with_attachment, account: account, inbox: inbox, conversation: canonical_conversation, message_type: :incoming,
                                         content: 'Com midia')
      create(:message, account: account, inbox: inbox, conversation: secondary_conversation, message_type: :incoming, content: 'Texto')

      finder = described_class.new(account: account, inbox: inbox)
      groups = finder.perform

      expect(finder.apply_send_locks!(groups)).to be >= 1

      canonical_conversation.reload
      secondary_conversation.reload

      expect(canonical_conversation.additional_attributes['dedupe_send_blocked']).to be_nil
      expect(secondary_conversation.additional_attributes['dedupe_send_blocked']).to eq(true)
      expect(secondary_conversation.additional_attributes['dedupe_canonical_conversation_id']).to eq(canonical_conversation.id)
    end
  end
end
