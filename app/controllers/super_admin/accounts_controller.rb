class SuperAdmin::AccountsController < SuperAdmin::ApplicationController
  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #
  # def update
  #   super
  #   send_foo_updated_email(requested_resource)
  # end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  def resource_params
    permitted_params = super
    permitted_params[:limits] = permitted_params[:limits].to_h.compact
    permitted_params[:selected_feature_flags] = params[:enabled_features].keys.map(&:to_sym) if params[:enabled_features].present?
    permitted_params
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information

  def seed
    Internal::SeedAccountJob.perform_later(requested_resource)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account seeding triggered')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def reset_cache
    requested_resource.reset_cache_keys
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Cache keys cleared')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def destroy
    account = Account.find(params[:id])

    DeleteObjectJob.perform_later(account) if account.present?
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account deletion is in progress.')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def telegram_import
    account = requested_resource
    inbox_id = params[:inbox_id]
    import_file = params[:import_file]

    unless import_file.present?
      redirect_back(fallback_location: [namespace, requested_resource], alert: 'Arquivo JSON é obrigatório')
      return
    end

    # Validar tamanho máximo (50MB)
    max_size = 50.megabytes
    if import_file.size > max_size
      redirect_back(fallback_location: [namespace, requested_resource], alert: "Arquivo muito grande. Tamanho máximo: #{max_size / 1.megabyte}MB")
      return
    end

    inbox = account.inboxes.find_by(id: inbox_id)
    unless inbox&.channel_type == 'Channel::Telegram'
      redirect_back(fallback_location: [namespace, requested_resource], alert: 'Inbox Telegram inválido')
      return
    end

    # Validar se é JSON
    begin
      JSON.parse(import_file.read)
      import_file.rewind
    rescue JSON::ParserError
      redirect_back(fallback_location: [namespace, requested_resource], alert: 'Arquivo JSON inválido')
      return
    end

    # Criar DataImport record
    data_import = account.data_imports.create!(
      data_type: 'telegram_history'
    )
    data_import.import_file.attach(import_file)

    # Processar assincronamente
    Telegram::ImportHistoryJob.perform_later(data_import.id, inbox.id)

    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource],
                  notice: 'Importação de histórico do Telegram iniciada. O processo pode levar alguns minutos.')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Rails/I18nLocaleTexts
  def evolution_import
    account = requested_resource
    inbox_id = params[:inbox_id]
    import_file = params[:import_file]
    dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run])
    mode = params[:mode].to_s.presence
    mode = 'import_direct' unless Evolution::ImportHistoryService::VALID_MODES.include?(mode)

    if import_file.blank?
      redirect_back(fallback_location: [namespace, requested_resource], alert: 'Arquivo JSON e obrigatorio')
      return
    end

    max_size = 200.megabytes
    if import_file.size > max_size
      redirect_back(fallback_location: [namespace, requested_resource], alert: "Arquivo muito grande. Tamanho maximo: #{max_size / 1.megabyte}MB")
      return
    end

    inbox = account.inboxes.find_by(id: inbox_id)
    unless inbox&.api?
      redirect_back(fallback_location: [namespace, requested_resource], alert: 'Inbox API invalido')
      return
    end

    begin
      JSON.parse(import_file.read)
      import_file.rewind
    rescue JSON::ParserError
      redirect_back(fallback_location: [namespace, requested_resource], alert: 'Arquivo JSON invalido')
      return
    end

    data_import = account.data_imports.create!(data_type: 'evolution_history')
    data_import.import_file.attach(import_file)
    Evolution::ImportHistoryJob.perform_later(data_import.id, inbox.id, dry_run: dry_run, mode: mode)

    notice =
      if dry_run
        mode == 'rebuild' ? 'DRY_RUN de reconstrucao Evolution iniciado com sucesso.' : 'DRY_RUN de importacao Evolution iniciado com sucesso.'
      else
        mode == 'rebuild' ? 'Reconstrucao Evolution iniciada com sucesso.' : 'Importacao Evolution iniciada com sucesso.'
      end
    redirect_to super_admin_account_path(account, dedup_inbox_id: inbox.id), notice: notice
  end

  def evolution_dedup_preview
    account = requested_resource
    inbox = find_api_inbox!(account, params[:inbox_id])
    return if performed?

    finder = Evolution::ConversationDedup::CandidateFinder.new(account: account, inbox: inbox)
    groups = finder.perform

    if params[:group_key].present?
      preview = preview_for_group(groups, account, inbox)
      notice = "Previa: mover=#{preview[:moved_messages]} deduplicar=#{preview[:deduplicated_messages]} " \
               "substituir=#{preview[:replaced_messages]} excluir_conversas=#{preview[:deleted_conversations]}"
    else
      locked_count = finder.apply_send_locks!(groups)
      notice = "Fila de revisao carregada. Grupos=#{groups.size}, conversas atualizadas com trava=#{locked_count}."
    end

    redirect_to super_admin_account_path(account, dedup_inbox_id: inbox.id), notice: notice
  rescue StandardError => e
    redirect_to super_admin_account_path(account), alert: "Falha ao gerar previa/fila: #{e.message}"
  end

  def evolution_dedup_apply
    account = requested_resource
    inbox = find_api_inbox!(account, params[:inbox_id])
    return if performed?

    finder = Evolution::ConversationDedup::CandidateFinder.new(account: account, inbox: inbox)
    groups = finder.perform
    group = find_group!(groups, params[:group_key])

    canonical_id = canonical_conversation_id_for(group)
    target_ids = target_conversation_ids_for(group, canonical_id)
    operation = dedup_operation

    result = Evolution::ConversationDedup::MergeService.new(
      account: account,
      inbox: inbox,
      canonical_conversation_id: canonical_id,
      target_conversation_ids: target_ids,
      operation: operation
    ).perform

    notice = "Reconciliacao concluida (#{operation}): mover=#{result[:moved_messages]} " \
             "deduplicar=#{result[:deduplicated_messages]} substituir=#{result[:replaced_messages]} " \
             "excluir_conversas=#{result[:deleted_conversations]}"
    redirect_to super_admin_account_path(account, dedup_inbox_id: inbox.id), notice: notice
  rescue StandardError => e
    redirect_to super_admin_account_path(account, dedup_inbox_id: params[:inbox_id]), alert: "Falha na reconciliacao: #{e.message}"
  end

  def evolution_dedup_apply_bulk
    account = requested_resource
    inbox = find_api_inbox!(account, params[:inbox_id])
    return if performed?

    finder = Evolution::ConversationDedup::CandidateFinder.new(account: account, inbox: inbox)
    groups = finder.perform

    merged_groups = 0
    moved_messages = 0
    deduplicated_messages = 0
    replaced_messages = 0
    deleted_conversations = 0
    errors = []

    groups.each do |group|
      canonical_id = group[:suggested_canonical_conversation_id]
      target_ids = group[:conversation_ids] - [canonical_id]
      next if target_ids.blank?

      result = Evolution::ConversationDedup::MergeService.new(
        account: account,
        inbox: inbox,
        canonical_conversation_id: canonical_id,
        target_conversation_ids: target_ids,
        operation: 'merge'
      ).perform

      merged_groups += 1
      moved_messages += result[:moved_messages]
      deduplicated_messages += result[:deduplicated_messages]
      replaced_messages += result[:replaced_messages]
      deleted_conversations += result[:deleted_conversations]
    rescue StandardError => e
      errors << "[grupo #{group[:group_key]}] #{e.message}"
    end

    notice = "Lote concluido: grupos=#{merged_groups}, mover=#{moved_messages}, deduplicar=#{deduplicated_messages}, " \
             "substituir=#{replaced_messages}, excluir_conversas=#{deleted_conversations}"
    notice = "#{notice}. Erros: #{errors.join(' | ')}" if errors.any?

    redirect_to super_admin_account_path(account, dedup_inbox_id: inbox.id), notice: notice
  rescue StandardError => e
    redirect_to super_admin_account_path(account, dedup_inbox_id: params[:inbox_id]), alert: "Falha no lote: #{e.message}"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Rails/I18nLocaleTexts

  private

  def find_api_inbox!(account, inbox_id)
    inbox = account.inboxes.find_by(id: inbox_id)
    if inbox&.api?
      inbox
    else
      redirect_to super_admin_account_path(account), alert: 'Inbox API invalido para reconciliacao'
      nil
    end
  end

  def dedup_operation
    operation = params[:operation].to_s
    operation = 'merge' if operation.blank?
    operation
  end

  def find_group!(groups, group_key)
    group = groups.find { |item| item[:group_key] == group_key.to_s }
    raise 'Grupo de duplicidade nao encontrado' unless group

    group
  end

  def canonical_conversation_id_for(group)
    chosen_id = params[:canonical_conversation_id].to_i
    group_ids = group[:conversation_ids]
    canonical_id = if chosen_id.positive? && group_ids.include?(chosen_id)
                     chosen_id
                   else
                     group[:suggested_canonical_conversation_id]
                   end
    enforce_media_priority!(group, canonical_id)
    canonical_id
  end

  def target_conversation_ids_for(group, canonical_id)
    requested_ids = Array(params[:target_conversation_ids]).map(&:to_i).uniq
    requested_ids = group[:conversation_ids] if requested_ids.blank?
    requested_ids.select { |id| group[:conversation_ids].include?(id) } - [canonical_id]
  end

  def preview_for_group(groups, account, inbox)
    group = find_group!(groups, params[:group_key])
    canonical_id = canonical_conversation_id_for(group)
    target_ids = target_conversation_ids_for(group, canonical_id)

    Evolution::ConversationDedup::MergeService.new(
      account: account,
      inbox: inbox,
      canonical_conversation_id: canonical_id,
      target_conversation_ids: target_ids,
      operation: dedup_operation,
      dry_run: true
    ).preview
  end

  def enforce_media_priority!(group, canonical_id)
    media_conversation_ids = group[:conversations].select { |conversation| conversation[:has_media] }.map { |conversation| conversation[:id] }
    return if media_conversation_ids.blank?
    return if media_conversation_ids.include?(canonical_id)

    raise 'Regra de midia: escolha uma conversa canonica que tenha midia.'
  end
end

SuperAdmin::AccountsController.prepend_mod_with('SuperAdmin::AccountsController')
