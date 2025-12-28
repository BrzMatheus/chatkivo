# Importação de Histórico do Telegram - Super Admin

## Visão Geral

Esta funcionalidade permite que administradores do Chatwoot importem mensagens antigas do Telegram através de arquivos JSON de exportação, sincronizando o histórico completo de conversas em inboxes Telegram específicos.

## Objetivo

Resolver o problema de sincronização de mensagens antigas recebidas no Telegram, permitindo importar todo o histórico de conversas através de um arquivo JSON exportado diretamente do Telegram.

## Funcionalidades Implementadas

### 1. Interface no Super Admin

A funcionalidade foi adicionada na página de detalhes de uma conta (`/super_admin/accounts/:id`), similar aos botões existentes "Seed Data" e "Reset Cache".

**Localização:** Super Admin → Accounts → [Selecionar Conta] → Seção "Importar Histórico do Telegram"

**Características:**
- Seleção de inbox Telegram da conta
- Upload de arquivo JSON (até 50MB)
- Validação de formato JSON
- Feedback visual durante o processo

### 2. Processamento Assíncrono

A importação é processada em background usando Jobs do Sidekiq para não bloquear a interface, ideal para arquivos grandes (~20MB).

**Características:**
- Processamento assíncrono via `Telegram::ImportHistoryJob`
- Processamento em lotes de 100 registros por vez
- Status de importação rastreado no modelo `DataImport`
- Tratamento de erros robusto

### 3. Prevenção de Duplicatas

O sistema evita criar dados duplicados através de verificações:

- **Contatos:** Busca por `identifier: "telegram_#{chat_id}"` antes de criar
- **Contact Inboxes:** Verifica existência por `source_id` antes de criar
- **Conversas:** Usa `find_or_create_by` para garantir unicidade
- **Mensagens:** Verifica `exists?(source_id: message_id)` antes de criar

### 4. Preservação de Timestamps

As mensagens importadas mantêm seus timestamps originais do Telegram, garantindo que a ordem cronológica seja preservada no Chatwoot.

## Estrutura de Arquivos

### Backend

```
app/
├── services/
│   └── telegram/
│       └── import_history_service.rb       # Lógica principal de importação
├── jobs/
│   └── telegram/
│       └── import_history_job.rb           # Job assíncrono
├── controllers/
│   └── super_admin/
│       └── accounts_controller.rb          # Action telegram_import adicionada
└── models/
    └── data_import.rb                      # Atualizado para suportar telegram_history
```

### Frontend

```
app/views/
└── super_admin/
    └── accounts/
        ├── show.html.erb                   # Partial incluído
        └── _telegram_import.html.erb       # Formulário de importação
```

### Rotas

```ruby
# config/routes.rb
namespace :super_admin do
  resources :accounts do
    post :telegram_import, on: :member
  end
end
```

## Formato do JSON do Telegram

O serviço espera o formato padrão de exportação do Telegram:

```json
{
  "chats": {
    "list": [
      {
        "id": 6266715127,
        "name": "Nome do Contato",
        "type": "personal_chat",
        "messages": [
          {
            "id": 107,
            "type": "message",
            "date_unixtime": 1766093602,
            "from": "Nome do Remetente",
            "from_id": "user6266715127",
            "text": "Conteúdo da mensagem"
          }
        ]
      }
    ]
  }
}
```

### Mapeamento de Dados

| Campo Telegram | Campo Chatwoot | Observações |
|---------------|----------------|-------------|
| `chat.id` | `contact_inbox.source_id` | ID único do chat |
| `message.id` | `message.source_id` | ID único da mensagem |
| `message.date_unixtime` | `message.created_at` | Timestamp preservado |
| `message.from_id` | `contact.identifier` | Extraído como `telegram_#{user_id}` |
| `message.text` | `message.content` | Suporta string ou array |

## Fluxo de Processamento

### 1. Upload e Validação

1. Usuário seleciona inbox Telegram e faz upload do arquivo JSON
2. Sistema valida:
   - Arquivo presente
   - Tamanho máximo (50MB)
   - Formato JSON válido
   - Inbox é do tipo Telegram

### 2. Criação do DataImport

1. Cria registro em `DataImport` com `data_type: 'telegram_history'`
2. Anexa arquivo JSON ao registro
3. Status inicial: `pending`

### 3. Processamento Assíncrono

1. Job `Telegram::ImportHistoryJob` é enfileirado
2. Job muda status para `processing`
3. Job faz download do arquivo e processa via `ImportHistoryService`

### 4. Importação dos Dados

Para cada chat no JSON:

1. **Criar/Buscar Contato:**
   - Busca por `identifier: "telegram_#{chat_id}"`
   - Se não existir, cria novo contato com nome e atributos

2. **Criar/Buscar Contact Inbox:**
   - Busca por `source_id: chat_id`
   - Cria se não existir, vinculando contato ao inbox

3. **Criar/Buscar Conversa:**
   - Usa `find_or_create_by` com account, inbox, contact_inbox
   - Respeita `lock_to_single_conversation` do inbox

4. **Importar Mensagens:**
   - Para cada mensagem, verifica duplicata por `source_id`
   - Cria mensagem com:
     - `source_id`: ID da mensagem no Telegram
     - `created_at`: Timestamp original preservado
     - `content`: Texto da mensagem (suporta arrays)
     - `message_type`: incoming/outgoing baseado em `out`
     - `sender`: Contato (para incoming) ou nil (para outgoing)

### 5. Finalização

1. Job atualiza `DataImport`:
   - Status: `completed` ou `failed`
   - `processed_records`: Número de mensagens importadas
   - `processing_errors`: Erros encontrados (se houver)

## Características Técnicas

### Processamento em Lotes

- **Tamanho do lote:** 100 registros
- **Transações:** Uma transação por lote
- **Memória:** Processamento otimizado para arquivos grandes

### Codificação de Caracteres

- Conversão automática para UTF-8
- Tratamento de caracteres inválidos
- Suporte a emojis e caracteres especiais

### Tipos de Mensagens Suportados

- ✅ Mensagens de texto
- ✅ Mensagens com formatação (arrays de entidades)
- ⚠️ Fotos/Arquivos: Referências são logadas mas arquivos não são baixados
- ⚠️ Mensagens de serviço: Podem ser ignoradas (códigos de login, etc.)

### Limitações Conhecidas

1. **Anexos:** Arquivos e fotos referenciados no JSON não são baixados automaticamente (apenas referência é registrada)
2. **Grupos:** Apenas chats pessoais (`personal_chat`) são processados
3. **Tamanho:** Arquivos muito grandes (>50MB) são rejeitados no upload

## Como Usar

### Passo a Passo

1. **Acesse o Super Admin**
   - Faça login como Super Admin
   - Navegue para: Super Admin → Accounts

2. **Selecione uma Conta**
   - Clique na conta desejada
   - Role até a seção "Importar Histórico do Telegram"

3. **Configure a Importação**
   - Selecione o inbox Telegram da lista
   - Clique em "Escolher arquivo" e selecione o JSON exportado do Telegram

4. **Inicie a Importação**
   - Clique em "Importar Histórico"
   - Confirme a ação

5. **Aguarde o Processamento**
   - A importação é processada em background
   - O processo pode levar alguns minutos para arquivos grandes
   - Você receberá uma notificação quando concluir

### Exportando Dados do Telegram

Para exportar seus dados do Telegram:

1. Abra o Telegram Desktop ou Web
2. Vá em: Configurações → Privacidade e Segurança
3. Clique em "Exportar dados do Telegram"
4. Selecione:
   - ✅ Mensagens
   - ✅ Conversas
   - ⚠️ Arquivos (opcional - arquivos grandes aumentam o tamanho)
5. Escolha o formato: **JSON**
6. Aguarde o download e use o arquivo na importação

## Tratamento de Erros

### Erros Comuns

| Erro | Causa | Solução |
|------|-------|---------|
| "Arquivo JSON inválido" | Formato incorreto ou corrompido | Verifique se o arquivo é um JSON válido do Telegram |
| "Arquivo muito grande" | Arquivo > 50MB | Remova arquivos anexos da exportação |
| "Inbox Telegram inválido" | Inbox selecionado não é Telegram | Selecione um inbox do tipo Telegram |
| "Nenhum inbox Telegram encontrado" | Conta não tem inboxes Telegram | Crie um inbox Telegram antes de importar |

### Logs

Erros são registrados em:
- **Rails logs:** `log/production.log` ou `log/development.log`
- **DataImport record:** Campo `processing_errors`

## Exemplos de Uso

### Exemplo 1: Importação Simples

```
1. Conta tem 1 inbox Telegram configurado
2. Arquivo JSON tem 50 conversas, ~1000 mensagens
3. Tempo estimado: 2-3 minutos
4. Resultado: 50 contatos criados/encontrados, 50 conversas, 1000 mensagens importadas
```

### Exemplo 2: Importação Grande

```
1. Conta tem múltiplos inboxes Telegram
2. Arquivo JSON tem 200 conversas, ~5000 mensagens (15MB)
3. Tempo estimado: 5-10 minutos
4. Resultado: Processamento em lotes, progresso rastreado
```

## Manutenção e Monitoramento

### Verificar Status de Importação

O status das importações pode ser verificado através do modelo `DataImport`:

```ruby
# No console Rails
account = Account.find(id)
imports = account.data_imports.where(data_type: 'telegram_history')
imports.last.status # pending, processing, completed, failed
imports.last.processed_records # Número de mensagens importadas
```

### Limpar Importações Antigas

```ruby
# Remover importações antigas (>30 dias)
DataImport.where(data_type: 'telegram_history')
          .where('created_at < ?', 30.days.ago)
          .destroy_all
```

## Segurança

- ✅ Apenas Super Admins podem acessar a funcionalidade
- ✅ Validação de tipo de inbox (apenas Telegram)
- ✅ Limite de tamanho de arquivo (50MB)
- ✅ Validação de formato JSON
- ✅ Processamento assíncrono para não bloquear servidor

## Performance

### Otimizações Implementadas

1. **Processamento em Lotes:** Reduz uso de memória
2. **Transações por Lote:** Melhora performance do banco
3. **Verificação de Duplicatas:** Evita queries desnecessárias
4. **Job Assíncrono:** Não bloqueia requisições HTTP

### Benchmarks Aproximados

- **100 mensagens:** ~5-10 segundos
- **1000 mensagens:** ~30-60 segundos
- **5000 mensagens:** ~3-5 minutos
- **10000+ mensagens:** ~10-15 minutos

*Tempos variam baseado em hardware e carga do servidor*

## Troubleshooting

### Importação não inicia

- Verifique se o Sidekiq está rodando
- Verifique logs do Rails para erros
- Confirme que o arquivo foi anexado corretamente

### Mensagens duplicadas

- Sistema verifica por `source_id` antes de criar
- Se houver duplicatas, verifique se o JSON tem IDs únicos
- Reimportar o mesmo arquivo não deve criar duplicatas

### Timestamps incorretos

- Verifique se o JSON tem `date_unixtime` (preferido) ou `date`
- Timestamps são convertidos para UTC
- Ordem cronológica é preservada

## Melhorias Futuras

Possíveis melhorias para versões futuras:

- [ ] Download automático de anexos referenciados
- [ ] Suporte a grupos/canais (não apenas chats pessoais)
- [ ] Barra de progresso em tempo real
- [ ] Notificações por email quando importação completar
- [ ] Suporte a múltiplos arquivos
- [ ] Importação incremental (apenas novos dados)
- [ ] Preview de dados antes de importar

## Suporte

Para problemas ou dúvidas:

1. Verifique os logs do Rails
2. Verifique o status do DataImport
3. Consulte esta documentação
4. Entre em contato com o time de desenvolvimento

---

**Última atualização:** Dezembro 2024  
**Versão:** 1.0  
**Autor:** Equipe de Desenvolvimento Chatwoot

