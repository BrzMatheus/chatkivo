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

    # rubocop:disable RSpec/MultipleExpectations
    it 'uses chatwoot preference when chatwoot_count is greater or equal' do
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
      target_conversation = Conversation.where(account: account, inbox: inbox, contact: contact).order(:id).last

      expect(source_conversation.reload).to be_present
      expect(target_conversation.id).not_to eq(source_conversation.id)
      expect(target_conversation.additional_attributes['historical_import']).to be(true)

      duplicated_message = target_conversation.messages.find_by(source_id: 'WAID:DUP1')
      incoming_message = target_conversation.messages.find_by(source_id: 'WAID:ONLY_EVO')

      expect(duplicated_message.content).to eq('Chatwoot duplicate')
      expect(incoming_message.sender_id).to eq(contact.id)
      expect(incoming_message.sender_type).to eq('Contact')
      expect(target_conversation.messages.outgoing.pluck(:sender_id).compact).to be_empty

      report_row = CSV.parse(result[:report_csv], headers: true).first.to_h
      expect(report_row['collision_preference']).to eq('chatwoot')
    end
    # rubocop:enable RSpec/MultipleExpectations

    it 'uses evolution preference when evolution_count is greater' do
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
      target_conversation = Conversation.where(account: account, inbox: inbox, contact: contact).order(:id).last
      duplicated_message = target_conversation.messages.find_by(source_id: 'WAID:DUP2')
      report_row = CSV.parse(result[:report_csv], headers: true).first.to_h

      expect(duplicated_message.content).to eq('Evolution preferred duplicate')
      expect(report_row['collision_preference']).to eq('evolution')
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
