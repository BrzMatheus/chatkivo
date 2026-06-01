require 'rails_helper'

describe CsatSurveys::ResponseBuilder do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, assignee: nil) }
  let(:message) do
    create(
      :message, account: account, conversation: conversation, inbox: conversation.inbox, content_type: :input_csat,
                content_attributes: { 'submitted_values': { 'csat_survey_response': { 'rating': 5, 'feedback_message': 'hello' } } }
    )
  end

  describe '#perform' do
    it 'creates a new csat survey response' do
      csat_survey_response = described_class.new(
        message: message
      ).perform

      expect(csat_survey_response.valid?).to be(true)
    end

    it 'updates the value of csat survey response if response already exists' do
      existing_survey_response = create(:csat_survey_response, message: message)
      csat_survey_response = described_class.new(
        message: message
      ).perform

      expect(csat_survey_response.id).to eq(existing_survey_response.id)
      expect(csat_survey_response.rating).to eq(5)
    end

    it 'uses the CSAT assigned agent stored on the survey message' do
      agent = create(:user, account: account, role: :agent)
      message.update!(
        content_attributes: message.content_attributes.merge('csat_assigned_agent_id' => agent.id)
      )

      csat_survey_response = described_class.new(message: message).perform

      expect(csat_survey_response.assigned_agent).to eq(agent)
    end
  end
end
