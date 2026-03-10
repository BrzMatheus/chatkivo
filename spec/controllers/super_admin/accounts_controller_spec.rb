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
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('DRY_RUN de importacao Evolution iniciado com sucesso.')
      end
    end
  end
end
