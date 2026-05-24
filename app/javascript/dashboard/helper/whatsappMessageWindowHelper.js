import { INBOX_TYPES, TWILIO_CHANNEL_MEDIUM } from './inbox';
import { MESSAGE_TYPE } from 'shared/constants/messages';

export const WHATSAPP_MESSAGE_WINDOW_STATUS = {
  WARNING: 'warning',
  EXPIRED: 'expired',
};

const MESSAGE_WINDOW_SECONDS = 24 * 60 * 60;
const MESSAGE_WINDOW_WARNING_SECONDS = 3 * 60 * 60;
const MESSAGE_WINDOW_WARNING_START_SECONDS =
  MESSAGE_WINDOW_SECONDS - MESSAGE_WINDOW_WARNING_SECONDS;

const getLastNonActivityMessage = conversation => {
  if (conversation?.last_non_activity_message) {
    return conversation.last_non_activity_message;
  }

  return [...(conversation?.messages || [])]
    .reverse()
    .find(message => message.message_type !== MESSAGE_TYPE.ACTIVITY);
};

export const isWhatsAppConversation = (conversation, inbox = {}) => {
  const channelType = inbox?.channel_type || conversation?.meta?.channel;

  return (
    channelType === INBOX_TYPES.WHATSAPP ||
    (channelType === INBOX_TYPES.TWILIO &&
      inbox?.medium === TWILIO_CHANNEL_MEDIUM.WHATSAPP)
  );
};

const getMessageAgeInSeconds = message => {
  const createdAt = Number(message?.created_at);

  if (!Number.isFinite(createdAt) || createdAt <= 0) {
    return null;
  }

  return Math.max(0, Math.floor(Date.now() / 1000) - createdAt);
};

export const getWhatsAppMessageWindowStatus = (conversation, inbox = {}) => {
  if (!isWhatsAppConversation(conversation, inbox)) {
    return null;
  }

  const lastMessage = getLastNonActivityMessage(conversation);

  if (!lastMessage) {
    return null;
  }

  if (conversation?.can_reply === false) {
    return WHATSAPP_MESSAGE_WINDOW_STATUS.EXPIRED;
  }

  if (lastMessage.message_type !== MESSAGE_TYPE.INCOMING) {
    return null;
  }

  const messageAgeInSeconds = getMessageAgeInSeconds(lastMessage);

  if (messageAgeInSeconds === null) {
    return null;
  }

  if (
    messageAgeInSeconds >= MESSAGE_WINDOW_WARNING_START_SECONDS &&
    messageAgeInSeconds < MESSAGE_WINDOW_SECONDS
  ) {
    return WHATSAPP_MESSAGE_WINDOW_STATUS.WARNING;
  }

  return null;
};

export const getWhatsAppMessageWindowPriorityRank = (conversation, inbox) => {
  return getWhatsAppMessageWindowStatus(conversation, inbox) ===
    WHATSAPP_MESSAGE_WINDOW_STATUS.WARNING
    ? 0
    : 1;
};
