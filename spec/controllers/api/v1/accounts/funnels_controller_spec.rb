require 'rails_helper'

RSpec.describe 'Funnels API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }

  describe 'GET /api/v1/accounts/{account.id}/funnels' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/funnels"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'creates a default funnel when account has none' do
        expect do
          get "/api/v1/accounts/#{account.id}/funnels",
              headers: headers,
              as: :json
        end.to change { account.reload.funnels.count }.by(1)

        expect(response).to have_http_status(:success)
        first_funnel = response.parsed_body.first
        expect(first_funnel['name']).to eq('geral')
        expect(first_funnel['is_default']).to be(true)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/funnels' do
    let(:params) do
      {
        funnel: {
          name: 'Pipeline API',
          columns: [
            { id: 'new', name: 'New', position: 0 },
            { id: 'won', name: 'Won', position: 1 }
          ]
        }
      }
    end

    it 'creates a funnel' do
      expect do
        post "/api/v1/accounts/#{account.id}/funnels",
             params: params,
             headers: headers,
             as: :json
      end.to change { account.reload.funnels.count }.by(1)

      expect(response).to have_http_status(:success)
      json_response = response.parsed_body
      expect(json_response['name']).to eq('Pipeline API')
      expect(json_response['columns'].map { |column| column['id'] }).to contain_exactly('new', 'won')
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/funnels/:id' do
    let!(:funnel) do
      account.funnels.create!(
        name: 'Pipeline API',
        is_default: true,
        columns: Funnel::DEFAULT_COLUMNS
      )
    end

    it 'updates funnel attributes' do
      patch "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}",
            params: { funnel: { name: 'Pipeline Updated' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:success)
      expect(funnel.reload.name).to eq('Pipeline Updated')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/funnels/:id/move_contact' do
    let!(:funnel) do
      account.funnels.create!(
        name: 'Pipeline API',
        is_default: true,
        columns: Funnel::DEFAULT_COLUMNS
      )
    end
    let!(:contact) { create(:contact, account: account, name: 'Contract Contact', email: 'contract@example.com') }

    it 'creates or updates funnel contact position and column' do
      post "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/move_contact",
           params: { contact_id: contact.id, column_id: 'backlog', position: 3 },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:success)
      json_response = response.parsed_body

      expect(json_response['funnel_id']).to eq(funnel.id)
      expect(json_response['contact_id']).to eq(contact.id)
      expect(json_response['column_id']).to eq('backlog')
      expect(json_response['position']).to eq(3)
    end
  end
end
