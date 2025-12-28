/**
 * Determines the last non-activity message between store and API messages.
 * @param {Object} messageInStore - The last non-activity message from the store.
 * @param {Object} messageFromAPI - The last non-activity message from the API.
 * @returns {Object} The latest non-activity message.
 */
const getLastNonActivityMessage = (messageInStore, messageFromAPI) => {
  // If both API value and store value for last non activity message
  // are available, then return the latest one.
  if (messageInStore && messageFromAPI) {
    return messageInStore.created_at >= messageFromAPI.created_at
      ? messageInStore
      : messageFromAPI;
  }
  // Otherwise, return whichever is available
  return messageInStore || messageFromAPI;
};

/**
 * Filters out duplicate source messages from an array of messages.
 * When duplicates are found, keeps the message with the smallest ID (first one created).
 * This ensures that even if messages are processed out of order, we always keep the original message.
 * @param {Array} messages - The array of messages to filter.
 * @returns {Array} An array of messages without duplicates, maintaining the original order.
 */
export const filterDuplicateSourceMessages = (messages = []) => {
  // Track which source_ids we've seen and which message (with smallest ID) to keep
  const seenSourceIds = new Map();
  const messagesWithoutDuplicates = [];

  // First pass: identify the message with smallest ID for each source_id
  messages.forEach(msg => {
    if (msg.source_id) {
      if (!seenSourceIds.has(msg.source_id)) {
        seenSourceIds.set(msg.source_id, msg);
      } else {
        // If we've seen this source_id, keep the one with smaller ID
        const existingMsg = seenSourceIds.get(msg.source_id);
        if (msg.id < existingMsg.id) {
          seenSourceIds.set(msg.source_id, msg);
        }
      }
    }
  });

  // Second pass: build result array maintaining original order
  const addedSourceIds = new Set();
  messages.forEach(msg => {
    if (msg.source_id) {
      // Only add the message if it's the one we decided to keep (smallest ID)
      const messageToKeep = seenSourceIds.get(msg.source_id);
      if (msg.id === messageToKeep.id && !addedSourceIds.has(msg.source_id)) {
        messagesWithoutDuplicates.push(msg);
        addedSourceIds.add(msg.source_id);
      }
    } else {
      // Messages without source_id are always included
      messagesWithoutDuplicates.push(msg);
    }
  });

  return messagesWithoutDuplicates;
};

/**
 * Retrieves the last message from a conversation, prioritizing non-activity messages.
 * @param {Object} m - The conversation object containing messages.
 * @returns {Object} The last message of the conversation.
 */
export const getLastMessage = m => {
  const lastMessageIncludingActivity = m.messages[m.messages.length - 1];

  const nonActivityMessages = m.messages.filter(
    message => message.message_type !== 2
  );
  const lastNonActivityMessageInStore =
    nonActivityMessages[nonActivityMessages.length - 1];

  const lastNonActivityMessageFromAPI = m.last_non_activity_message;

  // If API value and store value for last non activity message
  // is empty, then return the last activity message
  if (!lastNonActivityMessageInStore && !lastNonActivityMessageFromAPI) {
    return lastMessageIncludingActivity;
  }

  return getLastNonActivityMessage(
    lastNonActivityMessageInStore,
    lastNonActivityMessageFromAPI
  );
};

/**
 * Filters messages that have been read by the agent.
 * @param {Array} messages - The array of messages to filter.
 * @param {number} agentLastSeenAt - The timestamp of when the agent last saw the messages.
 * @returns {Array} An array of read messages.
 */
export const getReadMessages = (messages, agentLastSeenAt) => {
  return messages.filter(
    message => message.created_at * 1000 <= agentLastSeenAt * 1000
  );
};

/**
 * Filters messages that have not been read by the agent.
 * @param {Array} messages - The array of messages to filter.
 * @param {number} agentLastSeenAt - The timestamp of when the agent last saw the messages.
 * @returns {Array} An array of unread messages.
 */
export const getUnreadMessages = (messages, agentLastSeenAt) => {
  return messages.filter(
    message => message.created_at * 1000 > agentLastSeenAt * 1000
  );
};
