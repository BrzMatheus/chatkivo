require 'rails_helper'

RSpec.describe 'Super Admin accounts API', type: :request do
  include ActiveJob::TestHelper

  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  describe 'GET /super_admin/accounts' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get '/super_admin/accounts'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        sign_in(super_admin, scope: :super_admin)
        with_modified_env('NODE_OPTIONS' => '--max-old-space-size=4096') do
          get '/super_admin/accounts'
        end
        expect(response).to have_http_status(:success)
        expect(response.body).to include('New account')
        expect(response.body).to include(account.name)
      end

      it 'shows account details page' do
        sign_in(super_admin, scope: :super_admin)

        get "/super_admin/accounts/#{account.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Importar Historico Evolution')
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/reset_cache' do
    before do
      create(:label, account: account)
      create(:inbox, account: account)
      create(:team, account: account)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        expect(account.cache_keys.keys).to contain_exactly(:inbox, :label, :team)
        sign_in(super_admin, scope: :super_admin)

        now_timestamp = Time.now.utc.to_i
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('Cache keys cleared')

        range = now_timestamp..(now_timestamp + 10)
        expect(account.reload.cache_keys.values.all? { |v| range.cover?(v.to_i) }).to be(true)
      end
    end
  end

  describe 'DELETE /super_admin/accounts/{account_id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/super_admin/accounts/#{account.id}"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'Deletes the account' do
        total_accounts = Account.count
        sign_in(super_admin, scope: :super_admin)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/super_admin/accounts/#{account.id}"
        end

        expect(Account.count).to eq(total_accounts - 1)
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/evolution_import' do
    let!(:api_channel) { create(:channel_api, account: account) }
    let!(:api_inbox) { api_channel.inbox }
    let!(:non_api_inbox) { create(:inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/super_admin/accounts/#{account.id}/evolution_import"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      before do
        sign_in(super_admin, scope: :super_admin)
      end

      it 'fails when import file is missing' do
        post "/super_admin/accounts/#{account.id}/evolution_import", params: { inbox_id: api_inbox.id }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq('Arquivo JSON e obrigatorio')
      end

      it 'fails when inbox is not API' do
        import_file = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/evolution_history.json'), 'application/json')

        post "/super_admin/accounts/#{account.id}/evolution_import",
             params: { inbox_id: non_api_inbox.id, import_file: import_file }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq('Inbox API invalido')
      end

      it 'fails when JSON is invalid' do
        invalid_file = Tempfile.new(['invalid_evolution', '.json'])
        invalid_file.write('{')
        invalid_file.rewind
        import_file = Rack::Test::UploadedFile.new(invalid_file.path, 'application/json')

        post "/super_admin/accounts/#{account.id}/evolution_import",
             params: { inbox_id: api_inbox.id, import_file: import_file }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq('Arquivo JSON invalido')
      ensure
        invalid_file.close
        invalid_file.unlink
      end

      it 'fails when file exceeds max size' do
        oversized_file = Tempfile.new(['oversized_evolution', '.json'])
        oversized_file.write('{}')
        oversized_file.flush
        oversized_file.truncate(201.megabytes)
        import_file = Rack::Test::UploadedFile.new(oversized_file.path, 'application/json')

        post "/super_admin/accounts/#{account.id}/evolution_import",
             params: { inbox_id: api_inbox.id, import_file: import_file }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq('Arquivo muito grande. Tamanho maximo: 200MB')
      ensure
        oversized_file.close
        oversized_file.unlink
      end

      it 'creates data import and enqueues job' do
        import_file = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/evolution_history.json'), 'application/json')

        expect do
          post "/super_admin/accounts/#{account.id}/evolution_import",
               params: { inbox_id: api_inbox.id, import_file: import_file, dry_run: '1' }
        end.to have_enqueued_job(Evolution::ImportHistoryJob)

        data_import = account.data_imports.order(:id).last
        expect(data_import.data_type).to eq('evolution_history')
        expect(data_import.import_file).to be_attached
        expect(response).to redirect_to(super_admin_account_path(account, dedup_inbox_id: api_inbox.id))
        expect(flash[:notice]).to eq('DRY_RUN de importacao Evolution iniciado com sucesso.')
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/evolution_dedup_preview' do
    let!(:api_channel) { create(:channel_api, account: account) }
    let!(:api_inbox) { api_channel.inbox }
    let!(:contact) { create(:contact, account: account, identifier: 'evolution:5511777777777@s.whatsapp.net') }
    let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox, source_id: '5511777777777@s.whatsapp.net') }
    let!(:canonical_conversation) do
      create(
        :conversation,
        account: account,
        inbox: api_inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: { historical_import: false }
      )
    end
    let!(:secondary_conversation) do
      create(
        :conversation,
        account: account,
        inbox: api_inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: {
          historical_import: true,
          historical_import_source: 'evolution_super_admin',
          historical_import_jid: '5511777777777@s.whatsapp.net'
        }
      )
    end

    before do
      create(:message, :with_attachment, account: account, inbox: api_inbox, conversation: canonical_conversation, message_type: :incoming,
                                         content: 'Com midia')
      create(:message, account: account, inbox: api_inbox, conversation: secondary_conversation, message_type: :incoming, content: 'Texto')
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/super_admin/accounts/#{account.id}/evolution_dedup_preview", params: { inbox_id: api_inbox.id }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      before do
        sign_in(super_admin, scope: :super_admin)
      end

      it 'gera fila e aplica trava nas conversas secundarias sugeridas' do
        post "/super_admin/accounts/#{account.id}/evolution_dedup_preview", params: { inbox_id: api_inbox.id }

        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to include('Fila de revisao carregada')
        expect(secondary_conversation.reload.additional_attributes['dedupe_send_blocked']).to eq(true)
        expect(canonical_conversation.reload.additional_attributes['dedupe_send_blocked']).to be_nil
      end

      it 'retorna previa de impacto para um grupo' do
        post "/super_admin/accounts/#{account.id}/evolution_dedup_preview", params: { inbox_id: api_inbox.id }

        post "/super_admin/accounts/#{account.id}/evolution_dedup_preview",
             params: {
               inbox_id: api_inbox.id,
               group_key: "contact:#{contact.id}",
               canonical_conversation_id: canonical_conversation.id,
               target_conversation_ids: [secondary_conversation.id],
               operation: 'merge'
             }

        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to include('Previa:')
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/evolution_dedup_apply' do
    let!(:api_channel) { create(:channel_api, account: account) }
    let!(:api_inbox) { api_channel.inbox }
    let!(:contact) { create(:contact, account: account, identifier: 'evolution:5511666666666@s.whatsapp.net') }
    let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox, source_id: '5511666666666@s.whatsapp.net') }
    let!(:canonical_conversation) { create(:conversation, account: account, inbox: api_inbox, contact: contact, contact_inbox: contact_inbox) }
    let!(:secondary_conversation) do
      create(
        :conversation,
        account: account,
        inbox: api_inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: {
          historical_import: true,
          historical_import_source: 'evolution_super_admin',
          historical_import_jid: '5511666666666@s.whatsapp.net'
        }
      )
    end

    before do
      sign_in(super_admin, scope: :super_admin)
      create(:message, account: account, inbox: api_inbox, conversation: canonical_conversation, message_type: :incoming, source_id: 'WAID:BASE',
                       content: 'Base')
      create(:message, account: account, inbox: api_inbox, conversation: secondary_conversation, message_type: :incoming, source_id: 'WAID:SEC',
                       content: 'Secundaria')
    end

    it 'aplica reconciliacao no grupo informado' do
      expect do
        post "/super_admin/accounts/#{account.id}/evolution_dedup_apply",
             params: {
               inbox_id: api_inbox.id,
               group_key: "contact:#{contact.id}",
               canonical_conversation_id: canonical_conversation.id,
               target_conversation_ids: [secondary_conversation.id],
               operation: 'merge'
             }
      end.to change { Conversation.where(id: secondary_conversation.id).count }.from(1).to(0)

      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to include('Reconciliacao concluida')
      expect(canonical_conversation.reload.messages.find_by(source_id: 'WAID:SEC')).to be_present
    end

    it 'impede escolher canonica sem midia quando houver outra com midia no grupo' do
      canonical_with_media = create(
        :conversation,
        account: account,
        inbox: api_inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: { historical_import: false }
      )
      text_only_secondary = create(
        :conversation,
        account: account,
        inbox: api_inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: {
          historical_import: true,
          historical_import_source: 'evolution_super_admin',
          historical_import_jid: '5511666666666@s.whatsapp.net'
        }
      )
      create(:message, :with_attachment, account: account, inbox: api_inbox, conversation: canonical_with_media, message_type: :incoming,
                                         content: 'Com midia')
      create(:message, account: account, inbox: api_inbox, conversation: text_only_secondary, message_type: :incoming, content: 'Texto')

      post "/super_admin/accounts/#{account.id}/evolution_dedup_apply",
           params: {
             inbox_id: api_inbox.id,
             group_key: "contact:#{contact.id}",
             canonical_conversation_id: text_only_secondary.id,
             target_conversation_ids: [canonical_with_media.id],
             operation: 'merge'
           }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include('Regra de midia')
      expect(Conversation.where(id: text_only_secondary.id)).to exist
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/evolution_dedup_apply_bulk' do
    let!(:api_channel) { create(:channel_api, account: account) }
    let!(:api_inbox) { api_channel.inbox }
    let!(:contact) { create(:contact, account: account, identifier: 'evolution:5511555555555@s.whatsapp.net') }
    let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox, source_id: '5511555555555@s.whatsapp.net') }
    let!(:canonical_conversation) { create(:conversation, account: account, inbox: api_inbox, contact: contact, contact_inbox: contact_inbox) }
    let!(:secondary_conversation) do
      create(
        :conversation,
        account: account,
        inbox: api_inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: {
          historical_import: true,
          historical_import_source: 'evolution_super_admin',
          historical_import_jid: '5511555555555@s.whatsapp.net'
        }
      )
    end

    before do
      sign_in(super_admin, scope: :super_admin)
      create(:message, :with_attachment, account: account, inbox: api_inbox, conversation: canonical_conversation, message_type: :incoming,
                                         content: 'Com midia')
      create(:message, account: account, inbox: api_inbox, conversation: secondary_conversation, message_type: :incoming, content: 'Texto')
    end

    it 'aplica reconciliacao em lote com sugestao automatica' do
      expect do
        post "/super_admin/accounts/#{account.id}/evolution_dedup_apply_bulk", params: { inbox_id: api_inbox.id }
      end.to change { Conversation.where(id: secondary_conversation.id).count }.from(1).to(0)

      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to include('Lote concluido')
    end
  end
end
