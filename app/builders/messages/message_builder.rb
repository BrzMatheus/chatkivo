class Messages::MessageBuilder
  include ::FileTypeHelper
  include ::EmailHelper
  include ::DataHelper

  EXTERNAL_API_ECHO_USER_IDS = [3].freeze

  attr_reader :message

  def initialize(user, conversation, params)
    @params = params
    @private = params[:private] || false
    @conversation = conversation
    @user = user
    @account = conversation.account
    @message_type = params[:message_type] || 'outgoing'
    @attachments = params[:attachments]
    @automation_rule = content_attributes&.dig(:automation_rule_id)
    return unless params.instance_of?(ActionController::Parameters)

    @in_reply_to = content_attributes&.dig(:in_reply_to)
    @items = content_attributes&.dig(:items)
  end

  def perform
    validate_dedupe_send_block!
    @message = @conversation.messages.build(message_params)
    process_attachments
    process_emails
    Messages::AgentMessageSignatureService.new(message: @message).perform
    # When the message has no quoted content, it will just be rendered as a regular message
    # The frontend is equipped to handle this case
    process_email_content
    @message.save!
    @message
  end

  private

  def validate_dedupe_send_block!
    return unless outbound_message?
    return if @private

    attrs = @conversation.additional_attributes.to_h
    blocked = ActiveModel::Type::Boolean.new.cast(attrs['dedupe_send_blocked'])
    return unless blocked

    canonical_display_id = attrs['dedupe_canonical_conversation_display_id']
    canonical_hint = canonical_display_id.present? ? "##{canonical_display_id}" : 'canonica'
    raise StandardError, "Conversa bloqueada para envio durante reconciliacao de duplicidade. Use a conversa #{canonical_hint}."
  end

  def outbound_message?
    requested_type = @message_type.to_s
    requested_type = 'outgoing' if requested_type.blank?

    requested_type.in?(%w[outgoing template])
  end

  # Extracts content attributes from the given params.
  # - Converts ActionController::Parameters to a regular hash if needed.
  # - Attempts to parse a JSON string if content is a string.
  # - Returns an empty hash if content is not present, if there's a parsing error, or if it's an unexpected type.
  def content_attributes
    params = convert_to_hash(@params)
    content_attributes = params.fetch(:content_attributes, {})

    return safe_parse_json(content_attributes) if content_attributes.is_a?(String)
    return content_attributes if content_attributes.is_a?(Hash)

    {}
  end

  def process_attachments
    return if @attachments.blank?

    @attachments.each do |uploaded_attachment|
      attachment_file_type = file_type_for(uploaded_attachment)
      validate_whatsapp_image_upload!(attachment_file_type)

      attachment = @message.attachments.build(
        account_id: @message.account_id,
        file: uploaded_attachment
      )

      attachment.file_type = attachment_file_type
    end
  end

  def file_type_for(uploaded_attachment)
    return file_type_by_signed_id(uploaded_attachment) if uploaded_attachment.is_a?(String)

    file_type(uploaded_attachment&.content_type)
  end

  def validate_whatsapp_image_upload!(attachment_file_type)
    return unless whatsapp_image_upload_disabled?
    return unless attachment_file_type.to_s == 'image'

    raise StandardError, I18n.t('errors.messages.whatsapp_image_upload_disabled')
  end

  def whatsapp_image_upload_disabled?
    return false if @private
    return false unless @conversation.inbox&.whatsapp? || @conversation.inbox&.twilio_whatsapp?

    ActiveModel::Type::Boolean.new.cast(@account.settings&.dig('disable_whatsapp_image_uploads'))
  end

  def process_emails
    return unless @conversation.inbox&.inbox_type == 'Email'

    cc_emails = process_email_string(@params[:cc_emails])
    bcc_emails = process_email_string(@params[:bcc_emails])
    to_emails = process_email_string(@params[:to_emails])

    all_email_addresses = cc_emails + bcc_emails + to_emails
    validate_email_addresses(all_email_addresses)

    @message.content_attributes[:cc_emails] = cc_emails
    @message.content_attributes[:bcc_emails] = bcc_emails
    @message.content_attributes[:to_emails] = to_emails
  end

  def process_email_content
    return unless should_process_email_content?

    @message.content_attributes ||= {}
    email_attributes = build_email_attributes
    @message.content_attributes[:email] = email_attributes
  end

  def process_email_string(email_string)
    return [] if email_string.blank?

    email_string.gsub(/\s+/, '').split(',')
  end

  def message_type
    if @conversation.inbox.channel_type != 'Channel::Api' && @message_type == 'incoming'
      raise StandardError, 'Incoming messages are only allowed in Api inboxes'
    end

    @message_type
  end

  def sender
    return @conversation.contact unless message_type == 'outgoing'
    return if external_channel_echo_message?

    message_sender || @user
  end

  def external_created_at
    @params[:external_created_at].present? ? { external_created_at: @params[:external_created_at] } : {}
  end

  def automation_rule_id
    @automation_rule.present? ? { content_attributes: { automation_rule_id: @automation_rule } } : {}
  end

  def campaign_id
    @params[:campaign_id].present? ? { additional_attributes: { campaign_id: @params[:campaign_id] } } : {}
  end

  def template_params
    @params[:template_params].present? ? { additional_attributes: { template_params: JSON.parse(@params[:template_params].to_json) } } : {}
  end

  def message_sender
    return if @params[:sender_type] != 'AgentBot'

    AgentBot.where(account_id: [nil, @conversation.account.id]).find_by(id: @params[:sender_id])
  end

  def external_channel_echo_message?
    return false unless message_type == 'outgoing'
    return false if @private
    return false unless @user.is_a?(User)
    return false if sender_type_blocks_external_echo?

    external_echo_in_whatsapp_or_telegram? || external_echo_in_api_inbox?
  end

  def external_echo_in_whatsapp_or_telegram?
    @params[:source_id].present? &&
      (@conversation.inbox&.whatsapp? || @conversation.inbox&.telegram?)
  end

  def external_echo_in_api_inbox?
    return false unless @conversation.inbox&.api?

    external_whatsapp_source_id? || external_echo_user_for_api_inbox?
  end

  def external_echo_user_for_api_inbox?
    EXTERNAL_API_ECHO_USER_IDS.include?(@user.id)
  end

  def sender_type_blocks_external_echo?
    sender_type = @params[:sender_type].to_s

    # For API inboxes authenticated by configured external echo users,
    # we always treat outgoing messages as external channel echoes,
    # unless AgentBot was explicitly requested.
    return sender_type == 'AgentBot' if external_echo_user_for_api_inbox?

    return false if sender_type.blank?
    return false if sender_type.casecmp('User').zero? && external_whatsapp_source_id?

    true
  end

  def external_whatsapp_source_id?
    source_id = @params[:source_id].to_s

    source_id.start_with?('WAID:') || source_id.downcase.start_with?('wamid.')
  end

  def message_params
    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: message_type,
      content: @params[:content],
      private: @private,
      sender: sender,
      content_type: @params[:content_type],
      content_attributes: content_attributes.presence,
      items: @items,
      in_reply_to: @in_reply_to,
      echo_id: @params[:echo_id],
      source_id: @params[:source_id]
    }.merge(external_created_at).merge(automation_rule_id).merge(campaign_id).merge(template_params)
  end

  def email_inbox?
    @conversation.inbox&.inbox_type == 'Email'
  end

  def should_process_email_content?
    email_inbox? && !@private && @message.content.present?
  end

  def build_email_attributes
    email_attributes = ensure_indifferent_access(@message.content_attributes[:email] || {})
    normalized_content = normalize_email_body(@message.content)

    # Process liquid templates in normalized content with code block protection
    processed_content = process_liquid_in_email_body(normalized_content)

    # Use custom HTML content if provided, otherwise generate from message content
    email_attributes[:html_content] = if custom_email_content_provided?
                                        build_custom_html_content
                                      else
                                        build_html_content(processed_content)
                                      end

    email_attributes[:text_content] = build_text_content(processed_content)
    email_attributes
  end

  def build_html_content(normalized_content)
    html_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :html_content) || {})
    rendered_html = render_email_html(normalized_content)
    html_content[:full] = rendered_html
    html_content[:reply] = rendered_html
    html_content
  end

  def build_text_content(normalized_content)
    text_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :text_content) || {})
    text_content[:full] = normalized_content
    text_content[:reply] = normalized_content
    text_content
  end

  def custom_email_content_provided?
    @params[:email_html_content].present?
  end

  def build_custom_html_content
    html_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :html_content) || {})

    html_content[:full] = @params[:email_html_content]
    html_content[:reply] = @params[:email_html_content]

    html_content
  end

  # Liquid processing methods for email content
  def process_liquid_in_email_body(content)
    return content if content.blank?
    return content unless should_process_liquid?

    # Protect code blocks from liquid processing
    modified_content = modified_liquid_content(content)
    template = Liquid::Template.parse(modified_content)
    template.render(drops_with_sender)
  rescue Liquid::Error
    content
  end

  def should_process_liquid?
    @message_type == 'outgoing' || @message_type == 'template'
  end

  def drops_with_sender
    message_drops(@conversation).merge({
                                         'agent' => UserDrop.new(sender)
                                       })
  end
end

Messages::MessageBuilder.prepend_mod_with('Messages::MessageBuilder')
