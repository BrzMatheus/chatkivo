class Messages::AgentMessageSignatureService
  AGENT_NAME_TOKEN_REGEX = /\{\{\s*agent_name\s*\}\}/
  DEFAULT_TEMPLATE = 'Atendente: {{agent_name}}'.freeze
  FIRST_MESSAGE_PER_AGENT_MODE = 'first_message_per_agent'.freeze

  def initialize(message:)
    @message = message
    @account = message.account
    @conversation = message.conversation
  end

  def perform
    return message unless should_apply?

    signature = signature_text
    return message if signature.blank? || signature_already_present?(signature)

    message.content = "#{signature}\n#{message.content}"
    message
  end

  private

  attr_reader :message, :account, :conversation

  def should_apply?
    eligible_agent_message? && signature_enabled? && allowed_by_signature_mode?
  end

  def eligible_agent_message?
    return false unless message.outgoing?
    return false if message.private?
    return false unless message.sender.is_a?(User)
    return false if message.content.blank?
    return false if automated_message?

    true
  end

  def signature_enabled?
    ActiveModel::Type::Boolean.new.cast(account.agent_message_signature_enabled)
  end

  def allowed_by_signature_mode?
    return true unless first_message_per_agent_mode?

    !agent_has_replied_in_conversation?
  end

  def automated_message?
    content_attributes[:automation_rule_id].present? || additional_attributes[:campaign_id].present?
  end

  def content_attributes
    message.content_attributes.to_h.with_indifferent_access
  end

  def additional_attributes
    message.additional_attributes.to_h.with_indifferent_access
  end

  def signature_text
    template = account.agent_message_signature_template.presence || DEFAULT_TEMPLATE
    agent_name = message.sender.name.to_s
    return template.gsub(AGENT_NAME_TOKEN_REGEX, agent_name).strip if template.match?(AGENT_NAME_TOKEN_REGEX)

    "#{template} #{agent_name}".strip
  end

  def signature_already_present?(signature)
    message.content.to_s.start_with?("#{signature}\n")
  end

  def first_message_per_agent_mode?
    mode = account.agent_message_signature_mode.presence || FIRST_MESSAGE_PER_AGENT_MODE

    mode == FIRST_MESSAGE_PER_AGENT_MODE
  end

  def agent_has_replied_in_conversation?
    conversation.messages.outgoing.exists?(private: false, sender: message.sender)
  end
end
