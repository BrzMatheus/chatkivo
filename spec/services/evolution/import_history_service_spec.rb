require 'rails_helper'
require 'csv'

RSpec.describe Evolution::ImportHistoryService do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account, webhook_url: nil) }
  let(:inbox) { api_channel.inbox }

  describe '#perform' do
    it 'filters non canonical jids and does not write records in dry run' do
      payload = [
        {
          'remoteJid' => '5511999999999@s.whatsapp.net',
          'records' => [
            { 'wa_id' => 'A1', 'fromMe' => false, 'messageTimestamp' => 1_700_000_000, 'content' => 'Oi' }
          ]
        },
        {
          'remoteJid' => '120363403612008323@g.us',
          'records' => [
            { 'wa_id' => 'A2', 'fromMe' => true, 'messageTimestamp' => 1_700_000_010, 'content' => 'Grupo' }
          ]
        }
      ]

      service = described_class.new(
        account: account,
        inbox: inbox,
        import_file_data: payload.to_json,
        dry_run: true
      )

      contact_inboxes_before = ContactInbox.count
      conversations_before = Conversation.count
      messages_before = Message.count

      result = service.perform

      expect(ContactInbox.count).to eq(contact_inboxes_before)
      expect(Conversation.count).to eq(conversations_before)
      expect(Message.count).to eq(messages_before)

      report_rows = CSV.parse(result[:report_csv], headers: true).map(&:to_h)
      skipped_row = report_rows.find { |row| row['jid'] == '120363403612008323@g.us' }

      expect(result[:total_records]).to eq(2)
      expect(result[:processed_records]).to eq(1)
      expect(skipped_row['status']).to eq('skipped')
      expect(skipped_row['reason']).to include('jid nao canonico')
    end

    it 'uses the canonical conversation and chatwoot preference when chatwoot_count is greater or equal' do
      jid = '5511999999999@s.whatsapp.net'
      contact = create(:contact, account: account, phone_number: '+5511999999999')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: jid)
      source_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      create(:message,
             account: account,
             inbox: inbox,
             conversation: source_conversation,
             message_type: :outgoing,
             source_id: 'WAID:DUP1',
             content: 'Chatwoot duplicate',
             created_at: Time.zone.at(1_700_000_000))
      create(:message,
             account: account,
             inbox: inbox,
             conversation: source_conversation,
             message_type: :outgoing,
             source_id: 'WAID:ONLY_CHATWOOT',
             content: 'Only chatwoot',
             created_at: Time.zone.at(1_700_000_005))

      payload = [
        {
          'remoteJid' => jid,
          'records' => [
            { 'wa_id' => 'DUP1', 'fromMe' => true, 'messageTimestamp' => 1_700_000_006, 'content' => 'Evolution duplicate' },
            { 'wa_id' => 'ONLY_EVO', 'fromMe' => false, 'messageTimestamp' => 1_700_000_010, 'content' => 'Only evolution' }
          ]
        }
      ]

      service = described_class.new(
        account: account,
        inbox: inbox,
        import_file_data: payload.to_json,
        dry_run: false
      )

      result = service.perform
      target_conversation = source_conversation.reload

      expect(Conversation.where(account: account, inbox: inbox, contact: contact).count).to eq(1)
      expect(target_conversation.additional_attributes['historical_import_source']).to eq('evolution_super_admin')
      expect(target_conversation.additional_attributes['historical_import_jid']).to eq(jid)

      duplicated_message = target_conversation.messages.find_by(source_id: 'WAID:DUP1')
      incoming_message = target_conversation.messages.find_by(source_id: 'WAID:ONLY_EVO')

      expect(duplicated_message.content).to eq('Chatwoot duplicate')
      expect(incoming_message.sender_id).to eq(contact.id)
      expect(incoming_message.sender_type).to eq('Contact')

      report_row = CSV.parse(result[:report_csv], headers: true).first.to_h
      expect(report_row['collision_preference']).to eq('chatwoot')
    end

    it 'keeps existing duplicates untouched and inserts only missing messages when evolution_count is greater' do
      jid = '5511888888888@s.whatsapp.net'
      contact = create(:contact, account: account, phone_number: '+5511888888888')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: jid)
      source_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      create(:message,
             account: account,
             inbox: inbox,
             conversation: source_conversation,
             message_type: :outgoing,
             source_id: 'WAID:DUP2',
             content: 'Chatwoot wins only if preferred',
             created_at: Time.zone.at(1_700_000_000))

      payload = [
        {
          'remoteJid' => jid,
          'records' => [
            { 'wa_id' => 'DUP2', 'fromMe' => true, 'messageTimestamp' => 1_700_000_001, 'content' => 'Evolution preferred duplicate' },
            { 'wa_id' => 'EVO2', 'fromMe' => true, 'messageTimestamp' => 1_700_000_002, 'content' => 'Evolution 2' },
            { 'wa_id' => 'EVO3', 'fromMe' => false, 'messageTimestamp' => 1_700_000_003, 'content' => 'Evolution 3' }
          ]
        }
      ]

      service = described_class.new(
        account: account,
        inbox: inbox,
        import_file_data: payload.to_json,
        dry_run: false
      )

      result = service.perform
      target_conversation = source_conversation.reload
      duplicated_message = target_conversation.messages.find_by(source_id: 'WAID:DUP2')
      report_row = CSV.parse(result[:report_csv], headers: true).first.to_h

      expect(Conversation.where(account: account, inbox: inbox, contact: contact).count).to eq(1)
      expect(duplicated_message.content).to eq('Chatwoot wins only if preferred')
      expect(target_conversation.messages.where(source_id: 'WAID:DUP2').count).to eq(1)
      expect(target_conversation.messages.find_by(source_id: 'WAID:EVO2').content).to eq('Evolution 2')
      expect(target_conversation.messages.find_by(source_id: 'WAID:EVO3').content).to eq('Evolution 3')
      expect(report_row['collision_preference']).to eq('evolution')
    end

    it 'is idempotent and does not create shadow conversations on repeated imports' do
      jid = '5511666666666@s.whatsapp.net'
      contact = create(:contact, account: account, phone_number: '+5511666666666')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: jid)
      source_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      create(:message,
             account: account,
             inbox: inbox,
             conversation: source_conversation,
             message_type: :outgoing,
             source_id: 'WAID:IDEMPOTENT',
             content: 'Original',
             created_at: Time.zone.at(1_700_000_000))

      payload = [
        {
          'remoteJid' => jid,
          'records' => [
            { 'wa_id' => 'IDEMPOTENT', 'fromMe' => true, 'messageTimestamp' => 1_700_000_000, 'content' => 'Original' },
            { 'wa_id' => 'IDEMPOTENT_2', 'fromMe' => false, 'messageTimestamp' => 1_700_000_010, 'content' => 'Novo' }
          ]
        }
      ]

      described_class.new(account: account, inbox: inbox, import_file_data: payload.to_json, dry_run: false).perform
      described_class.new(account: account, inbox: inbox, import_file_data: payload.to_json, dry_run: false).perform

      conversations = Conversation.where(account: account, inbox: inbox, contact: contact).order(:id)

      expect(conversations.count).to eq(1)
      expect(source_conversation.reload.messages.where(source_id: 'WAID:IDEMPOTENT').count).to eq(1)
      expect(source_conversation.messages.where(source_id: 'WAID:IDEMPOTENT_2').count).to eq(1)
      expect(source_conversation.additional_attributes['historical_import_source']).to eq('evolution_super_admin')
      expect(source_conversation.additional_attributes['historical_import_jid']).to eq(jid)
    end

    it 'creates a rebuilt conversation and preserves the original timeline when mode is rebuild' do
      jid = '5511444444444@s.whatsapp.net'
      contact = create(:contact, account: account, phone_number: '+5511444444444')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: jid)
      source_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: source_conversation,
        message_type: :outgoing,
        source_id: 'WAID:ORIGINAL_ONLY',
        content: 'Original only',
        created_at: Time.zone.at(1_700_000_020)
      )

      payload = [
        {
          'remoteJid' => jid,
          'records' => [
            { 'wa_id' => 'ORIGINAL_ONLY', 'fromMe' => true, 'messageTimestamp' => 1_700_000_020, 'content' => 'Original only' },
            { 'wa_id' => 'REBUILD_ONLY', 'fromMe' => false, 'messageTimestamp' => 1_700_000_010, 'content' => 'Historical rebuild' }
          ]
        }
      ]

      described_class.new(
        account: account,
        inbox: inbox,
        import_file_data: payload.to_json,
        dry_run: false,
        mode: 'rebuild'
      ).perform

      conversations = Conversation.where(account: account, inbox: inbox, contact: contact).order(:id)
      rebuilt_conversation = conversations.where.not(id: source_conversation.id).last

      expect(conversations.count).to eq(2)
      expect(source_conversation.reload.messages.where(source_id: 'WAID:REBUILD_ONLY')).to be_blank
      expect(rebuilt_conversation.messages.where(source_id: 'WAID:ORIGINAL_ONLY').count).to eq(1)
      expect(rebuilt_conversation.messages.where(source_id: 'WAID:REBUILD_ONLY').count).to eq(1)
      expect(rebuilt_conversation.additional_attributes['historical_import']).to be(true)
      expect(rebuilt_conversation.additional_attributes['historical_import_mode']).to eq('rebuild')
      expect(rebuilt_conversation.additional_attributes['historical_import_rebuilt_from_conversation_id']).to eq(source_conversation.id)
      expect(rebuilt_conversation.created_at.to_i).to eq(1_700_000_010)
      expect(rebuilt_conversation.last_activity_at.to_i).to eq(1_700_000_020)
    end

    it 'reuses the canonical conversation for the same contact even when the existing contact_inbox uses UUID' do
      jid = '5521968515070@s.whatsapp.net'
      contact = create(:contact, account: account, phone_number: '+5521968515070')
      uuid_contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '31d697e2-ee8f-420a-ac6c-2258b793790c')
      source_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: uuid_contact_inbox)

      create(:message,
             account: account,
             inbox: inbox,
             conversation: source_conversation,
             message_type: :incoming,
             source_id: 'WAID:BASE',
             content: 'Base',
             created_at: Time.zone.at(1_700_000_000))

      payload = [
        {
          'remoteJid' => jid,
          'records' => [
            { 'wa_id' => 'IMPORT_1', 'fromMe' => false, 'messageTimestamp' => 1_700_000_010, 'content' => 'Historico importado' }
          ]
        }
      ]

      described_class.new(account: account, inbox: inbox, import_file_data: payload.to_json, dry_run: false).perform

      expect(Conversation.where(account: account, inbox: inbox, contact: contact).count).to eq(1)
      expect(source_conversation.reload.messages.where(source_id: 'WAID:IMPORT_1').count).to eq(1)
      expect(source_conversation.contact_inbox_id).to eq(uuid_contact_inbox.id)
      expect(source_conversation.additional_attributes['historical_import_jid']).to eq(jid)
    end

    it 'does not enqueue delivery or webhook jobs during message insert_all import' do
      jid = '5511777777777@s.whatsapp.net'
      contact = create(:contact, account: account, phone_number: '+5511777777777')
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: jid)

      payload = [
        {
          'remoteJid' => jid,
          'records' => [
            { 'wa_id' => 'NO_CALLBACK_1', 'fromMe' => false, 'messageTimestamp' => 1_700_000_010, 'content' => 'Incoming' },
            { 'wa_id' => 'NO_CALLBACK_2', 'fromMe' => true, 'messageTimestamp' => 1_700_000_020, 'content' => 'Outgoing' }
          ]
        }
      ]

      clear_enqueued_jobs

      described_class.new(
        account: account,
        inbox: inbox,
        import_file_data: payload.to_json,
        dry_run: false
      ).perform

      job_classes = enqueued_jobs.map { |job| job[:job] }
      expect(job_classes).not_to include(SendReplyJob)
      expect(job_classes).not_to include(WebhookJob)
    end
  end
end
