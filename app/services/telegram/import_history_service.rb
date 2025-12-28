class Telegram::ImportHistoryService
  pattr_initialize [:account!, :inbox!, :import_file_data!]

  BATCH_SIZE = 100 # Processar em lotes para arquivos grandes

  def perform
    raise 'Inbox must be a Telegram inbox' unless inbox.channel_type == 'Channel::Telegram'

    json_data = parse_json_file
    process_chats(json_data)

    {
      contacts_count: @contacts_count || 0,
      conversations_count: @conversations_count || 0,
      messages_count: @messages_count || 0
    }
  end

  private

  def parse_json_file
    # Ensure UTF-8 encoding
    data = import_file_data.force_encoding('UTF-8')
    clean_data = data.valid_encoding? ? data : data.encode('UTF-16le', invalid: :replace, replace: '').encode('UTF-8')

    JSON.parse(clean_data)
  rescue JSON::ParserError => e
    raise "Arquivo JSON inválido: #{e.message}"
  end

  def process_chats(json_data)
    @contacts_count = 0
    @conversations_count = 0
    @messages_count = 0

    chats = json_data.dig('chats', 'list') || []

    # Processar em lotes para não sobrecarregar memória
    chats.each_slice(BATCH_SIZE) do |chat_batch|
      ActiveRecord::Base.transaction do
        chat_batch.each do |chat_data|
          process_single_chat(chat_data)
        end
      end
    end
  end

  def process_single_chat(chat_data)
    return unless chat_data['type'] == 'personal_chat'

    chat_id = extract_chat_id(chat_data)
    return if chat_id.blank?

    messages = chat_data['messages'] || []
    return if messages.empty?

    # Criar ou encontrar contato e contact_inbox
    contact_inbox = find_or_create_contact_inbox(chat_id, chat_data, messages.first)
    return unless contact_inbox

    # Criar ou encontrar conversa
    conversation = find_or_create_conversation(contact_inbox, chat_id)
    return unless conversation

    @conversations_count += 1

    # Importar mensagens em lotes
    messages.each_slice(BATCH_SIZE) do |message_batch|
      process_messages_batch(conversation, message_batch, contact_inbox.contact)
    end
  end

  def extract_chat_id(chat_data)
    chat_data['id']&.to_s
  end

  def find_or_create_contact_inbox(chat_id, chat_data, first_message)
    # Buscar contact_inbox existente
    contact_inbox = inbox.contact_inboxes.find_by(source_id: chat_id)
    return contact_inbox if contact_inbox

    # Extrair dados do contato
    from_data = extract_from_data(first_message, chat_data)

    # Buscar contato por identifier ou criar novo
    contact = account.contacts.find_or_initialize_by(
      identifier: "telegram_#{chat_id}"
    )

    if contact.new_record?
      contact.name = extract_contact_name(from_data, chat_data)
      contact.additional_attributes = {
        username: from_data[:username],
        social_telegram_user_id: chat_id,
        social_telegram_user_name: from_data[:username]
      }
      contact.save!
      @contacts_count += 1
    end

    # Criar contact_inbox
    inbox.contact_inboxes.create!(
      contact: contact,
      source_id: chat_id
    )
  end

  def extract_from_data(message_data, chat_data)
    # Tentar extrair do from_id da mensagem
    from_id = message_data['from_id']
    user_id = from_id.to_s.gsub('user', '') if from_id.present?

    # Usar nome do chat como fallback
    name = message_data['from'] || chat_data['name'] || ''
    name_parts = name.split(' ', 2)

    {
      first_name: name_parts[0] || '',
      last_name: name_parts[1] || '',
      username: user_id,
      user_id: user_id
    }
  end

  def extract_contact_name(from_data, chat_data)
    name = chat_data['name'] || ''
    return name if name.present?

    full_name = "#{from_data[:first_name]} #{from_data[:last_name]}".strip
    return full_name if full_name.present?

    "Telegram User #{from_data[:user_id] || 'Unknown'}"
  end

  def find_or_create_conversation(contact_inbox, chat_id)
    # Se inbox tem lock_to_single_conversation, usar última conversa
    if inbox.lock_to_single_conversation
      conversation = contact_inbox.conversations.last
      return conversation if conversation
    end

    # Buscar conversa existente ou criar nova
    Conversation.find_or_create_by!(
      account: account,
      inbox: inbox,
      contact: contact_inbox.contact,
      contact_inbox: contact_inbox
    ) do |conv|
      conv.additional_attributes = {
        chat_id: chat_id
      }
    end
  end

  def process_messages_batch(conversation, messages_batch, contact)
    messages_batch.each do |msg_data|
      next unless msg_data['type'] == 'message'

      create_message_if_not_exists(conversation, msg_data, contact)
    end
  end

  def create_message_if_not_exists(conversation, msg_data, contact)
    message_id = extract_message_id(msg_data)
    return if message_id.blank?

    # Verificar se mensagem já existe
    return if conversation.messages.exists?(source_id: message_id.to_s)

    content = extract_content(msg_data)
    is_outgoing = extract_is_outgoing(msg_data, contact)
    timestamp = extract_timestamp(msg_data)

    message = conversation.messages.build(
      account_id: account.id,
      inbox_id: inbox.id,
      content: content,
      message_type: is_outgoing ? :outgoing : :incoming,
      source_id: message_id.to_s,
      sender: is_outgoing ? nil : contact,
      content_attributes: {
        external_created_at: timestamp.iso8601
      }
    )

    # Salvar sem validação para evitar problemas com timestamps
    message.save!(validate: false)

    # Preservar timestamp original usando update_columns para evitar callbacks
    message.update_columns(created_at: timestamp, updated_at: timestamp)

    @messages_count += 1

    # Processar anexos se houver (fotos/arquivos)
    process_attachments(message, msg_data) if has_attachments?(msg_data)
  end

  def extract_message_id(message_data)
    message_data['id']
  end

  def extract_content(message_data)
    text = message_data['text']

    # text pode ser string ou array de objetos
    if text.is_a?(Array)
      # Processar array de entidades de texto
      text.map do |item|
        if item.is_a?(Hash)
          item['text'] || ''
        else
          item.to_s
        end
      end.join('')
    elsif text.is_a?(String)
      text
    else
      ''
    end
  end

  def extract_is_outgoing(message_data, _contact)
    # No formato do Telegram export, mensagens recebidas têm 'from' e 'from_id'
    # Mensagens enviadas não teriam 'from' ou teriam 'out': true
    message_data['out'] == true
  end

  def extract_timestamp(message_data)
    # Preferir date_unixtime, depois date
    timestamp = message_data['date_unixtime'] || message_data['date']

    if timestamp.is_a?(Numeric)
      Time.at(timestamp).utc
    elsif timestamp.is_a?(String)
      begin
        Time.parse(timestamp).utc
      rescue StandardError
        Time.current.utc
      end
    else
      Time.current.utc
    end
  end

  def has_attachments?(message_data)
    message_data['photo'].present? ||
      message_data['file'].present? ||
      message_data['file_name'].present?
  end

  def process_attachments(_message, msg_data)
    # Processar foto
    if msg_data['photo'].present?
      # Foto está referenciada mas o arquivo pode não estar incluído no JSON
      Rails.logger.info "Foto encontrada mas não processada: #{msg_data['photo']}"
    end

    # Processar arquivo
    return unless msg_data['file'].present? || msg_data['file_name'].present?

    # Arquivo está referenciado mas pode não estar incluído
    Rails.logger.info "Arquivo encontrado mas não processado: #{msg_data['file_name']}"
  end
end
