module SortHandler
  extend ActiveSupport::Concern

  # rubocop:disable Metrics/BlockLength
  class_methods do
    def sort_on_last_activity_at(sort_direction = :desc)
      return order(last_activity_at: sort_direction) unless sort_direction.to_s == 'desc'

      order(generate_sql_query("#{whatsapp_message_window_warning_order_query}, conversations.last_activity_at DESC"))
    end

    # rubocop:disable Metrics/MethodLength
    def sort_on_unread_first(_sort_direction = nil)
      unread_first_sql = <<~SQL.squish
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM messages
            WHERE messages.conversation_id = conversations.id
              AND messages.account_id = conversations.account_id
              AND messages.message_type = ?
              AND (
                conversations.agent_last_seen_at IS NULL OR
                messages.created_at > conversations.agent_last_seen_at
              )
          )
          AND (#{latest_non_activity_message_type_query}) = ? THEN 0
          ELSE 1
        END ASC,
        conversations.last_activity_at DESC
      SQL

      unread_first_query = sanitize_sql_array(
        [
          unread_first_sql,
          Message.message_types[:incoming],
          Message.message_types[:incoming]
        ]
      )

      order(Arel.sql(unread_first_query))
    end
    # rubocop:enable Metrics/MethodLength

    def sort_on_created_at(sort_direction = :asc)
      order(created_at: sort_direction)
    end

    def sort_on_priority(sort_direction = :desc)
      order(generate_sql_query("priority #{sort_direction.to_s.upcase} NULLS LAST, last_activity_at DESC"))
    end

    def sort_on_waiting_since(sort_direction = :asc)
      order(generate_sql_query("waiting_since #{sort_direction.to_s.upcase} NULLS LAST, created_at ASC"))
    end

    def last_messaged_conversations
      Message.except(:order).select(
        'DISTINCT ON (conversation_id) conversation_id, id, created_at, message_type'
      ).order('conversation_id, created_at DESC')
    end

    def sort_on_last_user_message_at
      order('grouped_conversations.message_type', 'grouped_conversations.created_at ASC')
    end

    private

    def latest_non_activity_message_type_query
      <<~SQL.squish
        SELECT messages.message_type
        FROM messages
        WHERE messages.conversation_id = conversations.id
          AND messages.account_id = conversations.account_id
          AND messages.message_type != #{Message.message_types[:activity]}
        ORDER BY messages.created_at DESC, messages.id DESC
        LIMIT 1
      SQL
    end

    def latest_non_activity_message_created_at_query
      <<~SQL.squish
        SELECT messages.created_at
        FROM messages
        WHERE messages.conversation_id = conversations.id
          AND messages.account_id = conversations.account_id
          AND messages.message_type != #{Message.message_types[:activity]}
        ORDER BY messages.created_at DESC, messages.id DESC
        LIMIT 1
      SQL
    end

    def whatsapp_message_window_warning_order_query
      <<~SQL.squish
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM inboxes
            WHERE inboxes.id = conversations.inbox_id
              AND inboxes.channel_type = 'Channel::Whatsapp'
          )
          AND (#{latest_non_activity_message_type_query}) = #{Message.message_types[:incoming]}
          AND (#{latest_non_activity_message_created_at_query}) BETWEEN
            (CURRENT_TIMESTAMP - INTERVAL '24 hours') AND
            (CURRENT_TIMESTAMP - INTERVAL '21 hours')
          THEN 0
          ELSE 1
        END ASC
      SQL
    end

    def generate_sql_query(query)
      Arel::Nodes::SqlLiteral.new(sanitize_sql_for_order(query))
    end
  end
  # rubocop:enable Metrics/BlockLength
end
