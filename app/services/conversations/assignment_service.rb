class Conversations::AssignmentService
  SIGNATURE_ASSIGNMENT_ATTRIBUTE = 'agent_message_signature_assignment'.freeze

  def initialize(conversation:, assignee_id:, assignee_type: nil, assigned_at: Time.current)
    @conversation = conversation
    @assignee_id = assignee_id
    @assignee_type = assignee_type
    @assigned_at = assigned_at
  end

  def perform
    agent_bot_assignment? ? assign_agent_bot : assign_agent
  end

  private

  attr_reader :conversation, :assignee_id, :assignee_type, :assigned_at

  def assign_agent
    previous_assignee_id = conversation.assignee_id
    previous_agent_bot_id = conversation.assignee_agent_bot_id

    conversation.assignee = assignee
    conversation.assignee_agent_bot = nil
    record_signature_assignment_marker(previous_assignee_id, previous_agent_bot_id)
    conversation.save!
    assignee
  end

  def assign_agent_bot
    return unless agent_bot

    previous_assignee_id = conversation.assignee_id
    previous_agent_bot_id = conversation.assignee_agent_bot_id

    conversation.assignee = nil
    conversation.assignee_agent_bot = agent_bot
    record_signature_assignment_marker(previous_assignee_id, previous_agent_bot_id)
    conversation.save!
    agent_bot
  end

  def record_signature_assignment_marker(previous_assignee_id, previous_agent_bot_id)
    return unless assignment_changed?(previous_assignee_id, previous_agent_bot_id)

    attributes = conversation.additional_attributes.to_h
    attributes[SIGNATURE_ASSIGNMENT_ATTRIBUTE] = {
      assignee_id: conversation.assignee_id,
      assignee_agent_bot_id: conversation.assignee_agent_bot_id,
      assigned_at: assigned_at.iso8601(6)
    }
    conversation.additional_attributes = attributes
  end

  def assignment_changed?(previous_assignee_id, previous_agent_bot_id)
    previous_assignee_id != conversation.assignee_id ||
      previous_agent_bot_id != conversation.assignee_agent_bot_id
  end

  def assignee
    @assignee ||= conversation.account.users.find_by(id: assignee_id)
  end

  def agent_bot
    @agent_bot ||= AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end
end
