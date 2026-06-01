require 'rails_helper'

RSpec.describe V2::Reports::AgentSummaryBuilder do
  let(:account) { create(:account) }
  let(:user1) { create(:user, account: account, role: :agent) }
  let(:user2) { create(:user, account: account, role: :agent) }
  let(:default_whatsapp_template_usage) do
    {
      authentication: 0,
      marketing: 0,
      utility: 0,
      service: 0,
      other: 0,
      total: 0
    }
  end

  let(:params) do
    {
      business_hours: business_hours,
      since: 1.week.ago.beginning_of_day,
      until: Time.current.end_of_day
    }
  end
  let(:builder) { described_class.new(account: account, params: params) }

  describe '#build' do
    context 'when there is team data' do
      before do
        c1 = create(:conversation, account: account, assignee: user1, created_at: Time.current)
        c2 = create(:conversation, account: account, assignee: user2, created_at: Time.current)
        create(
          :reporting_event,
          account: account,
          conversation: c2,
          user: user2,
          name: 'conversation_resolved',
          value: 50,
          value_in_business_hours: 40,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          conversation: c1,
          user: user1,
          name: 'first_response',
          value: 20,
          value_in_business_hours: 10,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          conversation: c1,
          user: user1,
          name: 'reply_time',
          value: 30,
          value_in_business_hours: 15,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          conversation: c1,
          user: user1,
          name: 'reply_time',
          value: 40,
          value_in_business_hours: 25,
          created_at: Time.current
        )
      end

      context 'when business hours is disabled' do
        let(:business_hours) { false }

        it 'returns the correct team stats' do
          report = builder.build

          expect(report).to eq(
            [
              {
                id: user1.id,
                conversations_count: 1,
                resolved_conversations_count: 0,
                avg_resolution_time: nil,
                avg_first_response_time: 20.0,
                avg_reply_time: 35.0,
                whatsapp_template_usage: default_whatsapp_template_usage
              },
              {
                id: user2.id,
                conversations_count: 1,
                resolved_conversations_count: 1,
                avg_resolution_time: 50.0,
                avg_first_response_time: nil,
                avg_reply_time: nil,
                whatsapp_template_usage: default_whatsapp_template_usage
              }
            ]
          )
        end
      end

      context 'when business hours is enabled' do
        let(:business_hours) { true }

        it 'uses business hours values' do
          report = builder.build

          expect(report).to eq(
            [
              {
                id: user1.id,
                conversations_count: 1,
                resolved_conversations_count: 0,
                avg_resolution_time: nil,
                avg_first_response_time: 10.0,
                avg_reply_time: 20.0,
                whatsapp_template_usage: default_whatsapp_template_usage
              },
              {
                id: user2.id,
                conversations_count: 1,
                resolved_conversations_count: 1,
                avg_resolution_time: 40.0,
                avg_first_response_time: nil,
                avg_reply_time: nil,
                whatsapp_template_usage: default_whatsapp_template_usage
              }
            ]
          )
        end
      end
    end

    context 'when there is no team data' do
      let!(:new_user) { create(:user, account: account, role: :agent) }
      let(:business_hours) { false }

      it 'returns zero values' do
        report = builder.build

        expect(report).to include(
          {
            id: new_user.id,
            conversations_count: 0,
            resolved_conversations_count: 0,
            avg_resolution_time: nil,
            avg_first_response_time: nil,
            avg_reply_time: nil,
            whatsapp_template_usage: default_whatsapp_template_usage
          }
        )
      end
    end

    context 'when there are WhatsApp template messages' do
      let(:business_hours) { false }
      let(:whatsapp_channel) do
        create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      end
      let(:whatsapp_inbox) { whatsapp_channel.inbox }
      let(:conversation1) { create(:conversation, account: account, inbox: whatsapp_inbox, assignee: user1) }
      let(:conversation2) { create(:conversation, account: account, inbox: whatsapp_inbox, assignee: user2) }

      before do
        create_template_message(conversation: conversation1, sender: user1, category: 'MARKETING')
        create_template_message(conversation: conversation1, sender: user1, category: 'UTILITY', status: :read)
        create_template_message(conversation: conversation2, sender: user2, category: 'ALERT_UPDATE')
        create_template_message(conversation: conversation2, sender: user2, category: 'AUTHENTICATION', message_type: :template)
        create_template_message(conversation: conversation1, sender: user1, category: 'MARKETING', status: :failed)
        create_template_message(conversation: conversation1, sender: user1, category: 'UTILITY', created_at: 2.weeks.ago)
        create(
          :message,
          account: account,
          conversation: conversation1,
          inbox: whatsapp_inbox,
          sender: user1,
          message_type: :outgoing
        )
      end

      it 'returns template usage grouped by agent and category' do
        report = builder.build

        expect(report.find { |row| row[:id] == user1.id }[:whatsapp_template_usage]).to eq(
          default_whatsapp_template_usage.merge(marketing: 1, utility: 1, total: 2)
        )
        expect(report.find { |row| row[:id] == user2.id }[:whatsapp_template_usage]).to eq(
          default_whatsapp_template_usage.merge(authentication: 1, other: 1, total: 2)
        )
      end
    end
  end

  def create_template_message(conversation:, sender:, category:, **options)
    create(
      :message,
      account: conversation.account,
      conversation: conversation,
      inbox: conversation.inbox,
      sender: sender,
      message_type: options.fetch(:message_type, :outgoing),
      status: options.fetch(:status, :sent),
      content: 'Template message',
      created_at: options.fetch(:created_at, Time.current),
      additional_attributes: {
        'template_params' => {
          'name' => 'sample_template',
          'category' => category,
          'language' => 'pt_BR',
          'processed_params' => {}
        }
      }
    )
  end
end
