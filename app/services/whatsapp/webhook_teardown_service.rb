class Whatsapp::WebhookTeardownService
  def initialize(channel)
    @channel = channel
  end

  def perform
    return unless should_teardown_webhook?

    api_client = Whatsapp::FacebookApiClient.new(provider_config['api_key'])

    clear_phone_number_override(api_client)
    clear_legacy_waba_override(api_client)
  rescue StandardError => e
    # before_destroy must never block a channel delete — log and move on.
    Rails.logger.error "[WHATSAPP] Webhook teardown failed for channel #{@channel&.id}: #{e.message}"
  end

  private

  def provider_config
    @channel.provider_config || {}
  end

  def should_teardown_webhook?
    @channel.provider == 'whatsapp_cloud' &&
      provider_config['source'] == 'embedded_signup' &&
      provider_config['api_key'].present? &&
      (provider_config['phone_number_id'].present? || provider_config['business_account_id'].present?)
  end

  def clear_phone_number_override(api_client)
    phone_number_id = provider_config['phone_number_id']
    return if phone_number_id.blank?

    api_client.clear_phone_number_callback_override(phone_number_id)
    Rails.logger.info "[WHATSAPP] Phone-level webhook override cleared for channel #{@channel.id}"
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Phone-level webhook clear failed for channel #{@channel.id}: #{e.message}"
  end

  # The WABA-level override_callback_uri is shared across every phone number on
  # the WABA, so we must not clear it while a sibling channel still depends on
  # it. We use our own DB as the source of truth: if any other channel still
  # references this WABA, leave the override alone (siblings on the new code
  # path use phone-level overrides which take precedence anyway). Otherwise
  # this channel is the last consumer in this install and the clear is safe.
  def clear_legacy_waba_override(api_client)
    waba_id = provider_config['business_account_id']
    return if waba_id.blank?
    return if sibling_channel_on_waba?(waba_id)

    api_client.clear_waba_callback_override(waba_id)
    Rails.logger.info "[WHATSAPP] Legacy WABA webhook override cleared for channel #{@channel.id}"
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Legacy WABA webhook clear failed for channel #{@channel.id}: #{e.message}"
  end

  def sibling_channel_on_waba?(waba_id)
    Channel::Whatsapp.where.not(id: @channel.id)
                     .exists?(["provider_config ->> 'business_account_id' = ?", waba_id])
  end
end
