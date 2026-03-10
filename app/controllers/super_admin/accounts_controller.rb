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
    dry_run = params.key?(:dry_run) ? ActiveModel::Type::Boolean.new.cast(params[:dry_run]) : true

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
    Evolution::ImportHistoryJob.perform_later(data_import.id, inbox.id, dry_run: dry_run)

    notice = dry_run ? 'DRY_RUN de importacao Evolution iniciado com sucesso.' : 'Importacao Evolution iniciada com sucesso.'
    redirect_back(fallback_location: [namespace, requested_resource], notice: notice)
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Rails/I18nLocaleTexts
end

SuperAdmin::AccountsController.prepend_mod_with('SuperAdmin::AccountsController')
