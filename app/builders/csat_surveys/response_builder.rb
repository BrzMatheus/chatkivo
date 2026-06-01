class CsatSurveys::ResponseBuilder
  pattr_initialize [:message]

  def perform
    raise 'Invalid Message' unless message.input_csat?

    conversation = message.conversation
    rating = message.content_attributes.dig('submitted_values', 'csat_survey_response', 'rating')
    feedback_message = message.content_attributes.dig('submitted_values', 'csat_survey_response', 'feedback_message')

    return if rating.blank?

    process_csat_response(conversation, rating, feedback_message)
  end

  private

  def process_csat_response(conversation, rating, feedback_message)
    csat_survey_response = message.csat_survey_response || CsatSurveyResponse.new(
      message_id: message.id, account_id: message.account_id, conversation_id: message.conversation_id,
      contact_id: conversation.contact_id, assigned_agent: assigned_agent(conversation)
    )
    csat_survey_response.rating = rating
    csat_survey_response.feedback_message = feedback_message
    csat_survey_response.save!
    csat_survey_response
  end

  def assigned_agent(conversation)
    conversation.assignee || csat_assigned_agent(conversation)
  end

  def csat_assigned_agent(conversation)
    agent_id = csat_assigned_agent_id || conversation.additional_attributes&.dig('csat_assigned_agent_id')
    return if agent_id.blank?

    conversation.account.users.find_by(id: agent_id)
  end

  def csat_assigned_agent_id
    content_attributes = message.content_attributes || {}
    content_attributes['csat_assigned_agent_id'] || content_attributes[:csat_assigned_agent_id]
  end
end
