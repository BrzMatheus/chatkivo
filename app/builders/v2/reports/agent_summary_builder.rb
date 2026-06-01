class V2::Reports::AgentSummaryBuilder < V2::Reports::BaseSummaryBuilder
  pattr_initialize [:account!, :params!]

  TEMPLATE_CATEGORY_KEYS = %i[authentication marketing utility service other].freeze
  TEMPLATE_MESSAGE_TYPES = [Message.message_types[:outgoing], Message.message_types[:template]].freeze

  def build
    load_data
    prepare_report
  end

  private

  attr_reader :conversations_count, :resolved_count,
              :avg_resolution_time, :avg_first_response_time, :avg_reply_time,
              :whatsapp_template_usage

  def load_data
    super
    @whatsapp_template_usage = fetch_whatsapp_template_usage
  end

  def fetch_conversations_count
    account.conversations.where(created_at: range).group('assignee_id').count
  end

  def prepare_report
    account.account_users.map do |account_user|
      build_agent_stats(account_user)
    end
  end

  def build_agent_stats(account_user)
    user_id = account_user.user_id
    {
      id: user_id,
      conversations_count: conversations_count[user_id] || 0,
      resolved_conversations_count: resolved_count[user_id] || 0,
      avg_resolution_time: avg_resolution_time[user_id],
      avg_first_response_time: avg_first_response_time[user_id],
      avg_reply_time: avg_reply_time[user_id],
      whatsapp_template_usage: whatsapp_template_usage[user_id] || default_template_usage
    }
  end

  def group_by_key
    :user_id
  end

  def fetch_whatsapp_template_usage
    usage = Hash.new { |hash, key| hash[key] = default_template_usage }

    template_messages.group(:sender_id, template_category_query).count.each do |(user_id, category), count|
      normalized_category = normalize_template_category(category)
      usage[user_id][normalized_category] += count
      usage[user_id][:total] += count
    end

    usage
  end

  def template_messages
    account.messages
           .joins(:inbox)
           .reorder(nil)
           .where(created_at: range, sender_type: 'User', private: false)
           .where(message_type: TEMPLATE_MESSAGE_TYPES)
           .where(status: [Message.statuses[:sent], Message.statuses[:delivered], Message.statuses[:read]])
           .where(inboxes: { channel_type: 'Channel::Whatsapp' })
           .where("messages.additional_attributes ? 'template_params'")
  end

  def template_category_query
    Arel.sql("LOWER(NULLIF(messages.additional_attributes #>> '{template_params,category}', ''))")
  end

  def normalize_template_category(category)
    normalized_category = category.to_s.downcase.to_sym
    return normalized_category if TEMPLATE_CATEGORY_KEYS.include?(normalized_category)

    :other
  end

  def default_template_usage
    TEMPLATE_CATEGORY_KEYS.index_with(0).merge(total: 0)
  end
end
