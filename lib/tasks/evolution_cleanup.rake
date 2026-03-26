namespace :evolution do
  desc 'Remove o prefixo "evolution:" do identifier de contatos importados via Evolution'
  task cleanup_identifiers: :environment do
    puts 'Buscando contatos com prefixo "evolution:" no identifier...'

    contacts = Contact.where("identifier LIKE 'evolution:%'")
    total = contacts.count

    if total.zero?
      puts 'Nenhum contato encontrado com prefixo "evolution:" no identifier.'
      exit
    end

    puts "Encontrados #{total} contatos para atualizar."

    updated = 0
    errors = 0

    contacts.find_each do |contact|
      new_identifier = contact.identifier.sub(/\Aevolution:/, '')

      if contact.update(identifier: new_identifier)
        updated += 1
      else
        errors += 1
        puts "  Erro ao atualizar contato #{contact.id}: #{contact.errors.full_messages.join(', ')}"
      end
    end

    puts "\n#{'=' * 60}"
    puts 'Resumo:'
    puts "  Contatos encontrados: #{total}"
    puts "  Contatos atualizados: #{updated}"
    puts "  Erros: #{errors}"
    puts '=' * 60
  end
end
