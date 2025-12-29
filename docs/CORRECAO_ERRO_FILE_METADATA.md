# Correção do Erro 500 em file_metadata

## Problema Identificado

### Sintoma
A API de conversas estava retornando erro 500 (Internal Server Error) ao tentar carregar conversas nas abas "Minhas", "Todas" e "Não atribuídas". O erro ocorria especificamente quando a aplicação tentava renderizar conversas que continham mensagens com anexos.

### Erro nos Logs
```
ActionView::Template::Error (undefined method '[]' for nil):
app/models/attachment.rb:109:in 'Attachment#file_metadata'
app/models/attachment.rb:90:in 'Attachment#metadata_for_file_type'
app/models/attachment.rb:48:in 'Attachment#push_event_data'
app/models/message.rb:152:in 'Message#push_event_data'
app/views/api/v1/conversations/partials/_conversation.json.jbuilder:35
```

### Stack Trace Completo
O erro acontecia na linha 109 do arquivo `app/models/attachment.rb`, no método `file_metadata`, quando tentava acessar `file.metadata[:width]` e `file.metadata[:height]`, mas `file.metadata` era `nil`.

## Causa Raiz

O problema ocorria quando um `Attachment` tinha um arquivo anexado (via ActiveStorage), mas o `file.metadata` ainda não havia sido processado ou estava vazio. Isso pode acontecer em várias situações:

1. Arquivos recém-uploadados que ainda não tiveram seus metadados processados pelo ActiveStorage
2. Arquivos de tipos que não geram metadados (como documentos PDF, arquivos de texto, etc.)
3. Arquivos onde o processamento de metadados falhou silenciosamente

O código original tentava acessar diretamente `file.metadata[:width]` e `file.metadata[:height]` sem verificar se `file.metadata` era `nil`, causando o erro `undefined method '[]' for nil`.

## Solução Implementada

### Arquivo Modificado
- `app/models/attachment.rb` - Método `file_metadata` (linhas 103-115)

### Correções Aplicadas

#### 1. Proteção para `file.metadata`
Adicionamos o operador de navegação segura (`&.`) para acessar `file.metadata` de forma segura:

```ruby
# Antes (linha 109-110)
width: file.metadata[:width],
height: file.metadata[:height]

# Depois
width: file.metadata&.[](:width),
height: file.metadata&.[](:height)
```

O operador `&.` (safe navigation) retorna `nil` se `file.metadata` for `nil`, evitando o erro.

#### 2. Proteção para `file.byte_size`
Adicionamos verificação para garantir que `file` está anexado antes de acessar `file.byte_size`:

```ruby
# Antes (linha 108)
file_size: file.byte_size,

# Depois
file_size: file.attached? ? file.byte_size : nil,
```

Isso garante que não tentamos acessar `byte_size` de um arquivo que não está anexado.

### Código Completo Corrigido

```ruby
def file_metadata
  metadata = {
    extension: extension,
    data_url: file_url,
    thumb_url: thumb_url,
    file_size: file.attached? ? file.byte_size : nil,
    width: file.metadata&.[](:width),
    height: file.metadata&.[](:height)
  }

  metadata[:data_url] = metadata[:thumb_url] = external_url if message.inbox.instagram? && message.incoming?
  metadata
end
```

## Como a Correção Funciona

1. **Safe Navigation Operator (`&.`)**: Quando `file.metadata` é `nil`, a expressão `file.metadata&.[](:width)` retorna `nil` ao invés de lançar um erro. Isso permite que o código continue executando normalmente.

2. **Verificação de Arquivo Anexado**: A verificação `file.attached?` garante que só tentamos acessar `byte_size` quando há um arquivo realmente anexado.

3. **Valores Padrão**: Quando os metadados não estão disponíveis, os campos `width`, `height` e `file_size` retornam `nil`, que é um valor válido em JSON e permite que o frontend trate esses casos adequadamente.

## Impacto da Correção

### Antes
- ❌ Erro 500 ao carregar conversas com anexos
- ❌ Loop infinito de requisições no frontend
- ❌ Interface de conversas não carregava

### Depois
- ✅ Conversas carregam normalmente
- ✅ Anexos sem metadados são tratados graciosamente
- ✅ API retorna valores `nil` para metadados ausentes
- ✅ Frontend pode processar a resposta sem erros

## Testes Realizados

Após a correção, os seguintes cenários foram validados:

1. ✅ Conversas sem anexos carregam normalmente
2. ✅ Conversas com anexos que têm metadados completos funcionam
3. ✅ Conversas com anexos sem metadados (metadata = nil) não causam erro 500
4. ✅ Conversas com anexos não anexados (file não attached) não causam erro
5. ✅ Todas as abas ("Minhas", "Todas", "Não atribuídas") carregam corretamente

## Notas Técnicas

### Por que `file.metadata` pode ser nil?

No ActiveStorage, o `metadata` de um blob é populado quando:
- O arquivo é processado pelo ImageAnalyzer (para imagens)
- O arquivo é processado pelo VideoAnalyzer (para vídeos)
- O arquivo é processado pelo AudioAnalyzer (para áudios)

Para outros tipos de arquivo (PDFs, documentos, etc.), o `metadata` pode permanecer `nil` indefinidamente, pois esses tipos não geram metadados dimensionais.

### Compatibilidade

A correção é totalmente compatível com versões anteriores:
- Arquivos com metadados completos continuam funcionando normalmente
- O frontend já lida com valores `nil` em campos opcionais
- Não há impacto em performance

## Referências

- Arquivo corrigido: `app/models/attachment.rb`
- Método: `file_metadata` (linhas 103-115)
- Data da correção: 29/12/2025
- Erro original: `undefined method '[]' for nil` na linha 109

