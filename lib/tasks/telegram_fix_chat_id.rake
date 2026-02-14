namespace :telegram do
  desc 'Atualiza chat_id em conversas Telegram importadas que não têm o campo preenchido'
  task fix_chat_id: :environment do
    puts "Iniciando atualização de chat_id em conversas Telegram..."
    
    # Buscar todas as inboxes do tipo Telegram
    telegram_inboxes = Inbox.where(channel_type: 'Channel::Telegram')
    
    if telegram_inboxes.empty?
      puts "Nenhuma inbox Telegram encontrada."
      exit
    end
    
    total_updated = 0
    total_checked = 0
    
    telegram_inboxes.each do |inbox|
      puts "\nProcessando inbox #{inbox.id} (#{inbox.name})..."
      
      conversations = inbox.conversations.includes(:contact_inbox)
      
      conversations.each do |conv|
        total_checked += 1
        source_id = conv.contact_inbox&.source_id
        
        # Verificar se chat_id está vazio ou diferente do source_id
        current_chat_id = conv.additional_attributes&.dig('chat_id')
        
        if source_id.present? && (current_chat_id.blank? || current_chat_id != source_id.to_s)
          conv.additional_attributes ||= {}
          conv.additional_attributes['chat_id'] = source_id.to_s
          
          if conv.save
            total_updated += 1
            puts "  ✓ Conversa #{conv.id}: atualizado chat_id=#{source_id}"
          else
            puts "  ✗ Conversa #{conv.id}: erro ao salvar - #{conv.errors.full_messages.join(', ')}"
          end
        elsif current_chat_id.present?
          puts "  - Conversa #{conv.id}: já tem chat_id=#{current_chat_id} (OK)"
        else
          puts "  ✗ Conversa #{conv.id}: source_id ausente, não foi possível atualizar"
        end
      end
    end
    
    puts "\n" + "="*60
    puts "Resumo:"
    puts "  Conversas verificadas: #{total_checked}"
    puts "  Conversas atualizadas: #{total_updated}"
    puts "="*60
  end

  desc 'Sincroniza o business_connection_id mais recente para todas as conversas Telegram'
  task sync_business_connection_id: :environment do
    puts "Iniciando sincronização de business_connection_id em conversas Telegram..."

    telegram_inboxes = Inbox.where(channel_type: 'Channel::Telegram')
    if telegram_inboxes.empty?
      puts "Nenhuma inbox Telegram encontrada."
      exit
    end

    total_updated = 0
    total_checked = 0

    telegram_inboxes.each do |inbox|
      channel_business_connection_id = inbox.channel.additional_attributes&.dig('business_connection_id')

      if channel_business_connection_id.blank?
        puts "\nInbox #{inbox.id} (#{inbox.name}): business_connection_id não encontrado no canal. Pulando."
        next
      end

      puts "\nProcessando inbox #{inbox.id} (#{inbox.name}) com business_connection_id=#{channel_business_connection_id}..."

      inbox.conversations.find_each do |conversation|
        total_checked += 1
        conversation.additional_attributes ||= {}
        current_value = conversation.additional_attributes['business_connection_id']

        next if current_value == channel_business_connection_id

        conversation.additional_attributes['business_connection_id'] = channel_business_connection_id
        if conversation.save
          total_updated += 1
          puts "  ✓ Conversa #{conversation.id}: atualizado business_connection_id"
        else
          puts "  ✗ Conversa #{conversation.id}: erro ao salvar - #{conversation.errors.full_messages.join(', ')}"
        end
      end
    end

    puts "\n" + "="*60
    puts "Resumo:"
    puts "  Conversas verificadas: #{total_checked}"
    puts "  Conversas atualizadas: #{total_updated}"
    puts "="*60
  end
end

