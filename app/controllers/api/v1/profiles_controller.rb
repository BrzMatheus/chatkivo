class Api::V1::ProfilesController < Api::BaseController
  before_action :set_user

  def show; end

  def update
    if password_params[:password].present?
      render_could_not_create_error('Invalid current password') and return unless @user.valid_password?(password_params[:current_password])

      @user.update!(password_params.except(:current_password))
    end

    @user.assign_attributes(profile_params)
    @user.custom_attributes.merge!(custom_attributes_params)
    @user.save!
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  def auto_offline
    @user.account_users.find_by!(account_id: auto_offline_params[:account_id]).update!(auto_offline: auto_offline_params[:auto_offline] || false)
  end

  def availability
    @user.account_users.find_by!(account_id: availability_params[:account_id]).update!(availability: availability_params[:availability])
  end

  def set_active_account
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'app/controllers/api/v1/profiles_controller.rb:31', message: 'Iniciando set_active_account',
                 data: { account_id: profile_params[:account_id], user_id: @user.id }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run2', hypothesisId: 'H3' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    account_user = @user.account_users.find_by(account_id: profile_params[:account_id])
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'app/controllers/api/v1/profiles_controller.rb:35', message: 'AccountUser encontrado',
                 data: { account_user_id: account_user&.id }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run2', hypothesisId: 'H3' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    if account_user
      account_user.update(active_at: Time.now.utc)
      head :ok
    else
      # #region agent log
      begin
        File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
          f.puts({ location: 'app/controllers/api/v1/profiles_controller.rb:41', message: 'AccountUser NÃO encontrado para set_active_account',
                   data: { account_id: profile_params[:account_id] }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run2', hypothesisId: 'H3' }.to_json)
        end
      rescue StandardError
        nil
      end
      # #endregion
      render_unauthorized('You are not authorized to access this account')
    end
  rescue StandardError => e
    # #region agent log
    begin
      File.open('/home/mathe/chatwoot-src/.cursor/debug.log', 'a') do |f|
        f.puts({ location: 'app/controllers/api/v1/profiles_controller.rb:46', message: 'Erro em set_active_account',
                 data: { error: e.message, backtrace: e.backtrace[0..5] }, timestamp: Time.now.to_i * 1000, sessionId: 'debug-session', runId: 'run2', hypothesisId: 'H3' }.to_json)
      end
    rescue StandardError
      nil
    end
    # #endregion
    raise e
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  def reset_access_token
    @user.access_token.regenerate_token
    @user.reload
  end

  private

  def set_user
    @user = current_user
  end

  def availability_params
    params.require(:profile).permit(:account_id, :availability)
  end

  def auto_offline_params
    params.require(:profile).permit(:account_id, :auto_offline)
  end

  def profile_params
    params.require(:profile).permit(
      :email,
      :name,
      :display_name,
      :avatar,
      :message_signature,
      :account_id,
      ui_settings: {}
    )
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
