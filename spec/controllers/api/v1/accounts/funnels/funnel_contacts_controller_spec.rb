require 'rails_helper'

RSpec.describe 'Funnel Contacts API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let!(:funnel) do
    account.funnels.create!(
      name: 'Pipeline API',
      is_default: true,
      columns: Funnel::DEFAULT_COLUMNS
    )
  end
  let!(:contact) { create(:contact, account: account, name: 'John Doe', email: 'john.doe@example.com') }

  describe 'GET /api/v1/accounts/{account.id}/funnels/{funnel.id}/funnel_contacts' do
    before do
      funnel.funnel_contacts.create!(contact: contact, column_id: 'backlog', position: 1)
    end

    it 'returns funnel contacts from the funnel' do
      get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_contacts",
          headers: headers,
          as: :json

      expect(response).to have_http_status(:success)
      json_response = response.parsed_body
      expect(json_response.length).to eq(1)
      expect(json_response.first['contact_id']).to eq(contact.id)
      expect(json_response.first['column_id']).to eq('backlog')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/funnels/{funnel.id}/funnel_contacts' do
    it 'creates a funnel contact and defaults to first column when column_id is absent' do
      post "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_contacts",
           params: { contact_id: contact.id },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:success)
      expect(funnel.funnel_contacts.count).to eq(1)
      expect(funnel.funnel_contacts.first.column_id).to eq(Funnel::DEFAULT_COLUMNS.first['id'])
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/funnels/{funnel.id}/funnel_contacts/{contact_id}' do
    let!(:funnel_contact) do
      funnel.funnel_contacts.create!(contact: contact, column_id: 'backlog', position: 0)
    end

    it 'updates column and position' do
      patch "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_contacts/#{contact.id}",
            params: { funnel_contact: { column_id: 'em_execucao', position: 4 } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:success)
      expect(funnel_contact.reload.column_id).to eq('em_execucao')
      expect(funnel_contact.position).to eq(4)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/funnels/{funnel.id}/funnel_contacts/{contact_id}' do
    let!(:funnel_contact) do
      funnel.funnel_contacts.create!(contact: contact, column_id: 'backlog', position: 0)
    end

    it 'deletes the funnel contact' do
      expect do
        delete "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_contacts/#{contact.id}",
               headers: headers,
               as: :json
      end.to change { funnel.funnel_contacts.count }.by(-1)

      expect(response).to have_http_status(:ok)
    end
  end
end
