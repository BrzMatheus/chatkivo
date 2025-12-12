class Api::V1::Widget::BaseController < ApplicationController
  include SwitchLocale
  include WebsiteTokenHelper

  before_action :set_web_widget
  before_action :set_contact

  private

  def conversations
    if @contact_inbox.hmac_verified?
      verified_contact_inbox_ids = @contact.contact_inboxes.where(inbox_id: auth_token_params[:inbox_id], hmac_verified: true).map(&:id)
      @conversations = @contact.conversations.where(contact_inbox_id: verified_contact_inbox_ids)
    else
      @conversations = @contact_inbox.conversations.where(inbox_id: auth_token_params[:inbox_id])
    end
  end

  def conversation
    @conversation ||= conversations.last
  end

  def create_conversation
    # Verificar se já existe uma conversa para evitar duplicatas
    # especialmente em casos de requisições simultâneas (mensagens automáticas, stickers, etc)
    existing_conversation = find_or_create_conversation
    existing_conversation || create_new_conversation_with_lock
  end

  def find_or_create_conversation
    # Se lock_to_single_conversation está habilitado, usar a última conversa
    if inbox.lock_to_single_conversation?
      @contact_inbox.conversations.last
    else
      # Caso contrário, usar a última conversa não resolvida
      @contact_inbox.conversations.where.not(status: :resolved).last
    end
  end

  def create_new_conversation_with_lock
    # Usar lock no contact_inbox para prevenir condições de corrida
    @contact_inbox.with_lock do
      # Verificar novamente após adquirir o lock
      existing = find_or_create_conversation
      return existing if existing

      ::Conversation.create!(conversation_params)
    end
  rescue ActiveRecord::RecordNotUnique => e
    # Se ainda assim houver duplicação (por constraints de DB), buscar a existente
    Rails.logger.warn "Conversa duplicada detectada para contact_inbox #{@contact_inbox.id}: #{e.message}"
    find_or_create_conversation || raise
  end

  def inbox
    @inbox ||= ::Inbox.find_by(id: auth_token_params[:inbox_id])
  end

  def conversation_params
    # FIXME: typo referrer in additional attributes, will probably require a migration.
    {
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: {
        browser_language: browser.accept_language&.first&.code,
        browser: browser_params,
        initiated_at: timestamp_params,
        referer: permitted_params[:message][:referer_url]
      },
      custom_attributes: permitted_params[:custom_attributes].presence || {}
    }
  end

  def contact_email
    permitted_params.dig(:contact, :email)&.downcase
  end

  def contact_name
    return if @contact.email.present? || @contact.phone_number.present? || @contact.identifier.present?

    permitted_params.dig(:contact, :name) || (contact_email.split('@')[0] if contact_email.present?)
  end

  def contact_phone_number
    permitted_params.dig(:contact, :phone_number)
  end

  def browser_params
    {
      browser_name: browser.name,
      browser_version: browser.full_version,
      device_name: browser.device.name,
      platform_name: browser.platform.name,
      platform_version: browser.platform.version
    }
  end

  def timestamp_params
    { timestamp: permitted_params[:message][:timestamp] }
  end

  def message_params
    {
      account_id: conversation.account_id,
      sender: @contact,
      content: permitted_params[:message][:content],
      inbox_id: conversation.inbox_id,
      content_attributes: {
        in_reply_to: permitted_params[:message][:reply_to]
      },
      echo_id: permitted_params[:message][:echo_id],
      message_type: :incoming
    }
  end
end
