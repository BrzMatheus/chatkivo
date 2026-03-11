require 'rails_helper'

RSpec.describe 'Conversation Messages API', type: :request do
  let!(:account) { create(:account) }

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/messages' do
    let!(:inbox) { create(:inbox, account: account) }
    let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'creates a new outgoing message' do
        params = { content: 'test-message', private: true }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content).to eq(params[:content])
      end

      it 'bloqueia envio em conversa marcada para deduplicacao' do
        conversation.update!(
          additional_attributes: {
            dedupe_send_blocked: true,
            dedupe_canonical_conversation_display_id: 999
          }
        )

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { content: 'nao deve enviar' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(
          'Conversa bloqueada para envio durante reconciliacao de duplicidade. Use a conversa #999.'
        )
      end

      it 'does not create the message' do
        params = { content: "#{'h' * 150 * 1000}a", private: true }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = response.parsed_body

        expect(json_response['error']).to eq('Validation failed: Content is too long (maximum is 150000 characters)')
      end

      it 'creates an outgoing text message with a specific bot sender' do
        agent_bot = create(:agent_bot)
        time_stamp = Time.now.utc.to_s
        params = { content: 'test-message', external_created_at: time_stamp, sender_type: 'AgentBot', sender_id: agent_bot.id }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['content_attributes']['external_created_at']).to eq time_stamp
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.last.sender_id).to eq(agent_bot.id)
        expect(conversation.messages.last.content_type).to eq('text')
      end

      it 'creates a new outgoing message with attachment' do
        file = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
        params = { content: 'test-message', attachments: [file] }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(conversation.messages.last.attachments.first.file.present?).to be(true)
        expect(conversation.messages.last.attachments.first.file_type).to eq('image')
      end

      context 'when message is mirrored from an external whatsapp channel with source_id' do
        let(:whatsapp_channel) do
          create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
        end
        let!(:inbox) { whatsapp_channel.inbox }
        let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

        it 'creates a sender-less outgoing message' do
          params = { content: 'external message', source_id: 'wamid.external.123' }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          created_message = conversation.reload.messages.last
          expect(created_message.sender_id).to be_nil
          expect(created_message.sender_type).to be_nil
          expect(created_message.source_id).to eq('wamid.external.123')
        end
      end

      context 'when message is mirrored from an external whatsapp source on api inbox' do
        let(:api_channel) { create(:channel_api, account: account) }
        let!(:inbox) { api_channel.inbox }
        let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

        it 'creates a sender-less outgoing message for WAID source_id' do
          params = { content: 'external message', source_id: 'WAID:3EB02752948EF725763C87' }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          created_message = conversation.reload.messages.last
          expect(created_message.sender_id).to be_nil
          expect(created_message.sender_type).to be_nil
          expect(created_message.source_id).to eq('WAID:3EB02752948EF725763C87')
        end

        it 'creates a sender-less outgoing message even if sender_type is User' do
          params = {
            content: 'external message',
            source_id: 'WAID:3EB02752948EF725763C87',
            sender_type: 'User',
            sender_id: agent.id
          }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          created_message = conversation.reload.messages.last
          expect(created_message.sender_id).to be_nil
          expect(created_message.sender_type).to be_nil
          expect(created_message.source_id).to eq('WAID:3EB02752948EF725763C87')
        end
      end

      context 'when api inbox uses the configured external echo user' do
        let(:agent) { create(:user, id: 3, account: account, role: :agent) }
        let(:api_channel) { create(:channel_api, account: account) }
        let!(:inbox) { api_channel.inbox }
        let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

        it 'creates a sender-less outgoing message without source_id' do
          params = { content: 'external message without source id' }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          created_message = conversation.reload.messages.last
          expect(created_message.sender_id).to be_nil
          expect(created_message.sender_type).to be_nil
          expect(created_message.source_id).to be_nil
        end

        it 'creates a sender-less outgoing message when sender_type is User and source_id is missing' do
          params = {
            content: 'external message without source id',
            sender_type: 'User',
            sender_id: agent.id
          }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          created_message = conversation.reload.messages.last
          expect(created_message.sender_id).to be_nil
          expect(created_message.sender_type).to be_nil
          expect(created_message.source_id).to be_nil
        end

        it 'creates a sender-less outgoing message when sender_type is non-User and source_id is missing' do
          params = {
            content: 'external message without source id',
            sender_type: 'Contact',
            sender_id: conversation.contact_id
          }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          created_message = conversation.reload.messages.last
          expect(created_message.sender_id).to be_nil
          expect(created_message.sender_type).to be_nil
          expect(created_message.source_id).to be_nil
        end
      end

      context 'when api inbox' do
        let(:api_channel) { create(:channel_api, account: account) }
        let(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
        let(:conversation) { create(:conversation, inbox: api_inbox, account: account) }

        it 'reopens the conversation with new incoming message' do
          create(:message, conversation: conversation, account: account)
          conversation.resolved!

          params = { content: 'test-message', private: false, message_type: 'incoming' }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)
          expect(conversation.reload.status).to eq('open')
          expect(Conversations::ActivityMessageJob)
            .to(have_been_enqueued.at_least(:once)
              .with(conversation, { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
                                    content: 'System reopened the conversation due to a new incoming message.' }))
        end
      end
    end

    context 'when it is an authenticated agent bot' do
      let!(:agent_bot) { create(:agent_bot) }

      it 'creates a new outgoing message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        params = { content: 'test-message' }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content).to eq(params[:content])
      end

      it 'creates a new outgoing input select message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        select_item1 = build(:bot_message_select)
        select_item2 = build(:bot_message_select)
        params = { content_type: 'input_select', content_attributes: { items: [select_item1, select_item2] } }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content_type).to eq(params[:content_type])
        expect(conversation.messages.first.content).to be_nil
      end

      it 'creates a new outgoing cards message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        card = build(:bot_message_card)
        params = { content_type: 'cards', content_attributes: { items: [card] } }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content_type).to eq(params[:content_type])
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/:id/messages' do
    let(:conversation) { create(:conversation, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'shows the conversation' do
        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:meta][:contact][:id]).to eq(conversation.contact_id)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id' do
    let(:message) do
      create(
        :message,
        account: account,
        message_type: :outgoing,
        sender: create(:user, account: account),
        content_attributes: { bcc_emails: ['hello@chatwoot.com'] }
      )
    end
    let(:conversation) { message.conversation }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'deletes the message' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(message.reload.content).to eq 'This message was deleted'
        expect(message.reload.deleted).to be true
        expect(message.reload.content_attributes['bcc_emails']).to be_nil
      end

      it 'deletes interactive messages' do
        interactive_message = create(
          :message, message_type: :outgoing, content: 'test', content_type: 'input_select',
                    content_attributes: { 'items' => [{ 'title' => 'test', 'value' => 'test' }] },
                    conversation: conversation
        )

        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{interactive_message.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(interactive_message.reload.deleted).to be true
      end
    end

    context 'when the message id is invalid' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'returns not found error' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/99999",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id/retry' do
    let(:message) { create(:message, account: account, status: :failed, content_attributes: { external_error: 'error' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: message.conversation.inbox, user: agent)
      end

      it 'retries the message' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(message.reload.status).to eq('sent')
        expect(message.reload.content_attributes['external_error']).to be_nil
      end
    end

    context 'when the message id is invalid' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: message.conversation.inbox, user: agent)
      end

      it 'returns not found error' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/99999/retry",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id' do
    let(:api_channel) { create(:channel_api, account: account) }
    let(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:conversation) { create(:conversation, inbox: api_inbox, account: account) }
    let!(:message) { create(:message, conversation: conversation, account: account, status: :sent) }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch api_v1_account_conversation_message_url(account_id: account.id, conversation_id: conversation.display_id, id: message.id)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated agent' do
      context 'when agent has non-API inbox' do
        let(:inbox) { create(:inbox, account: account) }
        let(:agent) { create(:user, account: account, role: :agent) }
        let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

        before { create(:inbox_member, inbox: inbox, user: agent) }

        it 'returns forbidden' do
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err' }, headers: agent.create_new_auth_token, as: :json
          expect(response).to have_http_status(:forbidden)
        end

        it 'returns forbidden for content edit on unsupported inbox type' do
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { content: 'updated' }, headers: agent.create_new_auth_token, as: :json
          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when agent has API inbox' do
        before { create(:inbox_member, inbox: api_inbox, user: agent) }

        it 'uses StatusUpdateService to perform status update' do
          service = instance_double(Messages::StatusUpdateService)
          expect(Messages::StatusUpdateService).to receive(:new)
            .with(message, 'failed', 'err123')
            .and_return(service)
          expect(service).to receive(:perform)
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err123' }, headers: agent.create_new_auth_token, as: :json
        end

        it 'updates status to failed with external_error' do
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err123' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('err123')
        end

        it 'ignores transient timeout errors for failed status updates' do
          expect(Messages::StatusUpdateService).not_to receive(:new)

          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ),
                params: { status: 'failed', external_error: 'Timed out reading data from server' },
                headers: agent.create_new_auth_token,
                as: :json

          expect(response).to have_http_status(:success)
          expect(message.reload.status).to eq('sent')
          expect(message.reload.external_error).to be_nil
        end

        context 'when editing content' do
          let!(:message) do
            create(
              :message,
              conversation: conversation,
              account: account,
              message_type: :outgoing,
              sender: agent,
              content: 'original content'
            )
          end

          it 'updates message content' do
            patch api_v1_account_conversation_message_url(
              account_id: account.id,
              conversation_id: conversation.display_id,
              id: message.id
            ), params: { content: 'updated content' }, headers: agent.create_new_auth_token, as: :json

            expect(response).to have_http_status(:success)
            expect(message.reload.content).to eq('updated content')
          end

          it 'returns unprocessable_entity when content is blank' do
            patch api_v1_account_conversation_message_url(
              account_id: account.id,
              conversation_id: conversation.display_id,
              id: message.id
            ), params: { content: '   ' }, headers: agent.create_new_auth_token, as: :json

            expect(response).to have_http_status(:unprocessable_entity)
            expect(message.reload.content).to eq('original content')
          end
        end
      end

      context 'when agent has Telegram inbox' do
        let(:telegram_channel) { create(:channel_telegram, account: account) }
        let(:telegram_inbox) { telegram_channel.inbox }
        let!(:conversation) { create(:conversation, inbox: telegram_inbox, account: account, additional_attributes: { 'chat_id' => '123' }) }
        let!(:message) do
          create(
            :message,
            conversation: conversation,
            account: account,
            message_type: :outgoing,
            sender: agent,
            content: 'original content',
            source_id: '12345'
          )
        end

        before do
          create(:inbox_member, inbox: telegram_inbox, user: agent)
          allow_any_instance_of(Channel::Telegram).to receive(:edit_message_on_telegram).and_return({ success: true })
        end

        it 'edits telegram message content' do
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { content: 'updated telegram content' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(message.reload.content).to eq('updated telegram content')
        end
      end
    end
  end
end
