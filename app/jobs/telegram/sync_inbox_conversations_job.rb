class Telegram::SyncInboxConversationsJob < ApplicationJob
  queue_as :default

  def perform(inbox_id, business_connection_id)
    inbox = Inbox.find_by(id: inbox_id)
    return unless inbox
    return unless inbox.channel_type == 'Channel::Telegram'
    return unless business_connection_id.present?

    Rails.logger.info "Telegram: Iniciando sincronização de conversas do inbox #{inbox_id} com business_connection_id #{business_connection_id}"

    # Buscar todas as conversas do inbox que não têm business_connection_id
    conversations_to_sync = inbox.conversations
                                 .where("additional_attributes->>'business_connection_id' IS NULL OR additional_attributes->>'business_connection_id' = ''")

    return if conversations_to_sync.empty?

    Rails.logger.info "Telegram: Encontradas #{conversations_to_sync.count} conversas para sincronizar no inbox #{inbox_id}"

    updated_count = 0
    failed_count = 0

    conversations_to_sync.find_each do |conversation|
      conversation.additional_attributes ||= {}

      # Atualizar apenas se ainda não tiver business_connection_id
      if conversation.additional_attributes['business_connection_id'].blank?
        conversation.additional_attributes['business_connection_id'] = business_connection_id
        conversation.save!
        updated_count += 1

        Rails.logger.debug { "Telegram: Conversa #{conversation.id} sincronizada com business_connection_id" }
      end
    rescue StandardError => e
      failed_count += 1
      Rails.logger.error "Telegram: Erro ao sincronizar conversa #{conversation.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      # Continua com as outras conversas mesmo se uma falhar
    end

    Rails.logger.info "Telegram: Sincronização concluída para inbox #{inbox_id}. #{updated_count} conversas atualizadas, #{failed_count} falhas"
  end
end
