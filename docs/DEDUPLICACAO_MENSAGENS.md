# Deduplicação de Mensagens - Documentação

## Problema Original

Quando mensagens duplicadas eram recebidas através de webhooks (especialmente do WhatsApp e Telegram), o sistema estava excluindo as primeiras mensagens, fazendo com que apenas a partir da segunda resposta fosse possível visualizar as mensagens. O usuário queria que, antes de remover duplicatas, as mensagens fossem unificadas na conversa correta para garantir acesso a todas as mensagens.

## Solução Implementada

Foi implementada uma estratégia em duas camadas:

1. **Backend**: Movimenta mensagens duplicadas para a conversa correta ao invés de simplesmente ignorá-las
2. **Frontend**: Filtra mensagens duplicadas mantendo sempre a primeira mensagem criada (menor ID)

## Arquivos Modificados

### 1. Backend - WhatsApp

#### `app/services/whatsapp/incoming_message_base_service.rb`

**Mudanças:**
- Modificado o método `process_messages` para verificar se já existe uma mensagem com o mesmo `source_id`
- Quando uma mensagem duplicada é encontrada, o sistema agora:
  1. Identifica a mensagem existente
  2. Obtém o contato e a conversa corretos do webhook atual
  3. Verifica se a mensagem está em uma conversa diferente
  4. Move a mensagem para a conversa correta se necessário
  5. Registra a ação no log para auditoria

**Código relevante:**
```ruby
existing_message = find_message_by_source_id(@processed_params[:messages].first[:id])

if existing_message
  # Mensagem duplicada encontrada - garantir que está na conversa correta
  set_contact
  return unless @contact

  ActiveRecord::Base.transaction do
    set_conversation
    
    # Se a mensagem está em uma conversa diferente, movê-la para a conversa correta
    if existing_message.conversation_id != @conversation.id
      Rails.logger.info "Movendo mensagem duplicada #{existing_message.id} (source_id: #{existing_message.source_id}) da conversa #{existing_message.conversation_id} para conversa #{@conversation.id}"
      existing_message.update!(conversation_id: @conversation.id)
    end
  end
  return
end
```

### 2. Backend - Telegram

#### `app/services/telegram/incoming_message_service_helpers.rb` (NOVO)

Criado novo módulo helper para Telegram com métodos de deduplicação:

- `find_message_by_source_id(source_id)`: Busca mensagem existente pelo source_id
- `message_under_process?`: Verifica se mensagem está sendo processada (cache Redis)
- `cache_message_source_id_in_redis`: Armazena source_id no Redis durante processamento
- `clear_message_source_id_from_redis`: Remove source_id do Redis após processamento

#### `app/services/telegram/incoming_message_service.rb`

**Mudanças:**
- Incluído o módulo `Telegram::IncomingMessageServiceHelpers`
- Modificado o método `perform` para verificar duplicatas antes de criar mensagens
- Implementada mesma lógica do WhatsApp: mover mensagens duplicadas para conversa correta
- Adicionado cache Redis para evitar processamento simultâneo

**Código relevante:**
```ruby
# Verificar se já existe uma mensagem com o mesmo source_id (mensagem duplicada)
message_id = telegram_params_message_id.to_s
existing_message = find_message_by_source_id(message_id)

if existing_message
  # Mensagem duplicada encontrada - garantir que está na conversa correta
  set_contact
  return unless @contact

  ActiveRecord::Base.transaction do
    set_conversation

    # Se a mensagem está em uma conversa diferente, movê-la para a conversa correta
    if existing_message.conversation_id != @conversation.id
      Rails.logger.info "Movendo mensagem duplicada do Telegram #{existing_message.id} (source_id: #{existing_message.source_id}) da conversa #{existing_message.conversation_id} para conversa #{@conversation.id}"
      existing_message.update!(conversation_id: @conversation.id)
    end
  end
  return
end
```

### 3. Frontend

#### `app/javascript/dashboard/helper/conversationHelper.js`

**Mudanças:**
- Melhorado o método `filterDuplicateSourceMessages` para garantir que sempre mantenha a mensagem com menor ID (primeira criada)
- Implementada lógica em duas passadas:
  1. Primeira passada: Identifica qual mensagem deve ser mantida (menor ID)
  2. Segunda passada: Constrói o array final mantendo a ordem original

**Código relevante:**
```javascript
export const filterDuplicateSourceMessages = (messages = []) => {
  // Track which source_ids we've seen and which message (with smallest ID) to keep
  const seenSourceIds = new Map();
  const messagesWithoutDuplicates = [];
  
  // First pass: identify the message with smallest ID for each source_id
  messages.forEach(msg => {
    if (msg.source_id) {
      if (!seenSourceIds.has(msg.source_id)) {
        seenSourceIds.set(msg.source_id, msg);
      } else {
        // If we've seen this source_id, keep the one with smaller ID
        const existingMsg = seenSourceIds.get(msg.source_id);
        if (msg.id < existingMsg.id) {
          seenSourceIds.set(msg.source_id, msg);
        }
      }
    }
  });
  
  // Second pass: build result array maintaining original order
  const addedSourceIds = new Set();
  messages.forEach(msg => {
    if (msg.source_id) {
      // Only add the message if it's the one we decided to keep (smallest ID)
      const messageToKeep = seenSourceIds.get(msg.source_id);
      if (msg.id === messageToKeep.id && !addedSourceIds.has(msg.source_id)) {
        messagesWithoutDuplicates.push(msg);
        addedSourceIds.add(msg.source_id);
      }
    } else {
      // Messages without source_id are always included
      messagesWithoutDuplicates.push(msg);
    }
  });
  
  return messagesWithoutDuplicates;
};
```

#### `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue`

**Mudanças:**
- Modificado o computed `getMessages` para aplicar o filtro também para Telegram (anteriormente apenas WhatsApp)

**Código relevante:**
```javascript
getMessages() {
  const messages = this.currentChat.messages || [];
  if (this.isAWhatsAppChannel || this.isATelegramChannel) {
    return filterDuplicateSourceMessages(messages);
  }
  return messages;
},
```

## Como Funciona Agora

### Fluxo Backend

1. **Recebimento de Webhook:**
   - Sistema recebe webhook com mensagem
   - Extrai o `source_id` da mensagem

2. **Verificação de Duplicata:**
   - Busca no banco se já existe mensagem com o mesmo `source_id`
   - Verifica se mensagem está sendo processada no Redis

3. **Se Mensagem Duplicada Encontrada:**
   - Obtém contato e conversa corretos do webhook atual
   - Compara `conversation_id` da mensagem existente com a conversa correta
   - Se diferentes, move a mensagem para a conversa correta
   - Retorna sem criar nova mensagem

4. **Se Mensagem Nova:**
   - Armazena `source_id` no Redis (lock)
   - Processa mensagem normalmente
   - Cria mensagem no banco
   - Remove lock do Redis

### Fluxo Frontend

1. **Carregamento de Mensagens:**
   - Busca mensagens da conversa
   - Identifica se é canal WhatsApp ou Telegram

2. **Filtragem de Duplicatas:**
   - Agrupa mensagens por `source_id`
   - Para cada grupo, mantém apenas a mensagem com menor ID
   - Preserva ordem original das mensagens

3. **Exibição:**
   - Exibe mensagens filtradas na interface
   - Garante que apenas uma mensagem por `source_id` seja mostrada

## Canais Suportados

- ✅ **WhatsApp** (WhatsApp Cloud API, 360Dialog, Twilio WhatsApp)
- ✅ **Telegram**

## Benefícios

1. **Prevenção de Perda de Dados:** Mensagens não são mais ignoradas, são movidas para a conversa correta
2. **Consistência:** Todas as mensagens duplicadas acabam na mesma conversa
3. **Visibilidade:** Usuários têm acesso a todas as mensagens através da conversa correta
4. **Performance:** Cache Redis previne processamento duplicado simultâneo
5. **Auditoria:** Logs registram quando mensagens são movidas entre conversas

## Considerações Técnicas

### Redis Cache
- Utiliza chave: `MESSAGE_SOURCE_KEY::%<id>s`
- TTL padrão do Redis (geralmente configurável)
- Previne condições de corrida quando mesma mensagem chega simultaneamente

### Transações de Banco
- Operações de movimentação de mensagens são envolvidas em transações
- Garante integridade dos dados
- Rollback automático em caso de erro

### Logs
- Registra movimentações de mensagens duplicadas
- Formato: `"Movendo mensagem duplicada [ID] (source_id: [SOURCE_ID]) da conversa [ID_ORIGEM] para conversa [ID_DESTINO]"`

## Testes Recomendados

1. **Teste de Duplicata na Mesma Conversa:**
   - Enviar mesma mensagem duas vezes
   - Verificar que apenas uma é criada/exibida

2. **Teste de Duplicata em Conversa Diferente:**
   - Criar mensagem em conversa A
   - Receber webhook duplicado apontando para conversa B
   - Verificar que mensagem é movida para conversa B

3. **Teste de Processamento Simultâneo:**
   - Enviar múltiplos webhooks simultâneos com mesmo source_id
   - Verificar que apenas um processamento ocorre

4. **Teste Frontend:**
   - Carregar conversa com mensagens duplicadas
   - Verificar que apenas primeira mensagem (menor ID) é exibida

## Manutenção Futura

Se precisar adicionar suporte para outros canais:

1. Criar módulo helper similar a `Telegram::IncomingMessageServiceHelpers`
2. Adicionar métodos de verificação de duplicatas no serviço de mensagens do canal
3. Implementar lógica de movimentação de mensagens
4. Adicionar filtro no frontend se necessário

## Autores

Implementado em resposta à necessidade de unificar mensagens duplicadas antes da filtragem, garantindo acesso completo às mensagens na conversa correta.

