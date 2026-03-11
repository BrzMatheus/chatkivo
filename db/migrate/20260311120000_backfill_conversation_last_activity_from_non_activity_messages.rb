class BackfillConversationLastActivityFromNonActivityMessages < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE conversations AS c
      SET last_activity_at = COALESCE(last_message_data.last_message_at, c.created_at)
      FROM (
        SELECT conversations.id AS conversation_id,
               MAX(messages.created_at) AS last_message_at
        FROM conversations
        LEFT JOIN messages
          ON messages.conversation_id = conversations.id
          AND messages.message_type IN (0, 1, 3)
        GROUP BY conversations.id
      ) AS last_message_data
      WHERE c.id = last_message_data.conversation_id
        AND c.last_activity_at IS DISTINCT FROM COALESCE(last_message_data.last_message_at, c.created_at)
    SQL
  end

  def down
    # no-op
  end
end
