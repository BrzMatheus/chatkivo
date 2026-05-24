<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import Avatar from 'next/avatar/Avatar.vue';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import ConversationContextMenu from './contextMenu/Index.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import PriorityMark from './PriorityMark.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import TelegramExpiredBadge from './components/TelegramExpiredBadge.vue';
import WhatsAppMessageWindowBadge from './components/WhatsAppMessageWindowBadge.vue';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { getWhatsAppMessageWindowStatus } from 'dashboard/helper/whatsappMessageWindowHelper';

const props = defineProps({
  activeLabel: { type: String, default: '' },
  chat: { type: Object, default: () => ({}) },
  hideInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  teamId: { type: [String, Number], default: 0 },
  foldersId: { type: [String, Number], default: 0 },
  showAssignee: { type: Boolean, default: false },
  conversationType: { type: String, default: '' },
  selected: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
  enableContextMenu: { type: Boolean, default: false },
  allowedContextMenuOptions: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'contextMenuToggle',
  'assignAgent',
  'assignLabel',
  'removeLabel',
  'assignTeam',
  'markAsUnread',
  'markAsRead',
  'assignPriority',
  'updateConversationStatus',
  'deleteConversation',
  'selectConversation',
  'deSelectConversation',
]);

const router = useRouter();
const store = useStore();

const hovered = ref(false);
const isCardHovered = ref(false);
const showContextMenu = ref(false);
const contextMenu = ref({
  x: null,
  y: null,
});

const currentChat = useMapGetter('getSelectedChat');
const inboxesList = useMapGetter('inboxes/getInboxes');
const activeInbox = useMapGetter('getSelectedInbox');
const accountId = useMapGetter('getCurrentAccountId');

const chatMetadata = computed(() => props.chat.meta || {});

const assignee = computed(() => chatMetadata.value.assignee || {});

const assignedTeam = computed(() => chatMetadata.value.team || null);

const senderId = computed(() => chatMetadata.value.sender?.id);

const currentContact = computed(() => {
  return senderId.value
    ? store.getters['contacts/getContact'](senderId.value)
    : {};
});

const isActiveChat = computed(() => {
  return currentChat.value.id === props.chat.id;
});

const unreadCount = computed(() => props.chat.unread_count);

const hasUnread = computed(() => unreadCount.value > 0);

const isInboxNameVisible = computed(() => !activeInbox.value);

const lastMessageInChat = computed(() => getLastMessage(props.chat));

const isLastMessageOutgoing = computed(() => {
  return lastMessageInChat.value?.message_type === MESSAGE_TYPE.OUTGOING;
});

const hasPendingUnread = computed(() => {
  return hasUnread.value && !isLastMessageOutgoing.value;
});

const showContextMenuTrigger = computed(() => {
  return isActiveChat.value || props.selected || isCardHovered.value;
});

const voiceCallData = computed(() => ({
  status: props.chat.additional_attributes?.call_status,
  direction: props.chat.additional_attributes?.call_direction,
}));

const inboxId = computed(() => props.chat.inbox_id);

const inbox = computed(() => {
  return inboxId.value ? store.getters['inboxes/getInbox'](inboxId.value) : {};
});

const showInboxName = computed(() => {
  return (
    !props.hideInboxName &&
    isInboxNameVisible.value &&
    inboxesList.value.length > 1
  );
});

const showMetaSection = computed(() => {
  return showInboxName.value || props.chat.priority;
});

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);

const isTelegramConversationExpired = computed(() => {
  return (
    inbox.value?.channel_type === 'Channel::Telegram' &&
    props.chat?.can_reply === false
  );
});

const whatsAppMessageWindowStatus = computed(() =>
  getWhatsAppMessageWindowStatus(props.chat, inbox.value)
);

const showLabelsSection = computed(() => {
  return props.chat.labels?.length > 0 || hasSlaPolicyId.value;
});

const messagePreviewClass = computed(() => {
  return [
    hasPendingUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
  ];
});

const conversationPath = computed(() => {
  return frontendURL(
    conversationUrl({
      accountId: accountId.value,
      activeInbox: activeInbox.value,
      id: props.chat.id,
      label: props.activeLabel,
      teamId: props.teamId,
      conversationType: props.conversationType,
      foldersId: props.foldersId,
    })
  );
});

const onCardClick = e => {
  const path = conversationPath.value;
  if (!path) return;

  // Handle Ctrl/Cmd + Click for new tab
  if (e.metaKey || e.ctrlKey) {
    e.preventDefault();
    window.open(
      `${window.chatwootConfig.hostURL}${path}`,
      '_blank',
      'noopener,noreferrer'
    );
    return;
  }

  // Skip if already active
  if (isActiveChat.value) return;

  router.push({ path });
};

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, inbox.value.id);
  } else {
    emit('deSelectConversation', props.chat.id, inbox.value.id);
  }
};

const onCardMouseEnter = () => {
  isCardHovered.value = true;
};

const onCardMouseLeave = () => {
  isCardHovered.value = false;
};

const openContextMenu = e => {
  if (!props.enableContextMenu) return;
  e.preventDefault();
  emit('contextMenuToggle', true);
  contextMenu.value.x = e.pageX || e.clientX;
  contextMenu.value.y = e.pageY || e.clientY;
  showContextMenu.value = true;
};

function closeContextMenu() {
  emit('contextMenuToggle', false);
  showContextMenu.value = false;
  contextMenu.value.x = null;
  contextMenu.value.y = null;
}

const openContextMenuFromButton = e => {
  if (!props.enableContextMenu) return;
  // Evita que o foco saia do menu e dispare blur,
  // o que fazia o menu fechar e abrir de novo.
  e.preventDefault();
  e.stopPropagation();

  // Se o menu já estiver aberto, o clique na seta fecha (toggle)
  if (showContextMenu.value) {
    closeContextMenu();
    return;
  }

  const rect = e.currentTarget.getBoundingClientRect();
  emit('contextMenuToggle', true);
  contextMenu.value.x = rect.right;
  contextMenu.value.y = rect.bottom;
  showContextMenu.value = true;
};

const onUpdateConversation = (status, snoozedUntil) => {
  closeContextMenu();
  emit('updateConversationStatus', props.chat.id, status, snoozedUntil);
};

const onAssignAgent = agent => {
  emit('assignAgent', agent, [props.chat.id]);
  closeContextMenu();
};

const onAssignLabel = label => {
  emit('assignLabel', [label.title], [props.chat.id]);
};

const onRemoveLabel = label => {
  emit('removeLabel', [label.title], [props.chat.id]);
};

const onAssignTeam = team => {
  emit('assignTeam', team, props.chat.id);
  closeContextMenu();
};

const markAsUnread = () => {
  emit('markAsUnread', props.chat.id);
  closeContextMenu();
};

const markAsRead = () => {
  emit('markAsRead', props.chat.id);
  closeContextMenu();
};

const assignPriority = priority => {
  emit('assignPriority', priority, props.chat.id);
  closeContextMenu();
};

const deleteConversation = () => {
  emit('deleteConversation', props.chat.id);
  closeContextMenu();
};
</script>

<template>
  <div
    class="relative flex items-start flex-grow-0 flex-shrink-0 w-auto max-w-full py-0 border-t-0 border-b-0 border-l-0 border-r-0 border-transparent border-solid cursor-pointer conversation hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 group"
    :class="{
      'active animate-card-select bg-n-background border-n-weak': isActiveChat,
      'bg-n-slate-2': selected,
      'px-0': compact,
      'px-3': !compact,
    }"
    @click="onCardClick"
    @contextmenu="openContextMenu($event)"
    @mouseenter="onCardMouseEnter"
    @mouseleave="onCardMouseLeave"
  >
    <div
      class="relative"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <Avatar
        v-if="!hideThumbnail"
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="32"
        :status="currentContact.availability_status"
        :class="!showInboxName ? 'mt-4' : 'mt-8'"
        hide-offline-status
        rounded-full
      >
        <template #overlay="{ size }">
          <label
            v-if="hovered || selected"
            class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <input
              :value="selected"
              :checked="selected"
              class="!m-0 cursor-pointer"
              type="checkbox"
              @change="onSelectConversation($event.target.checked)"
            />
          </label>
        </template>
      </Avatar>
    </div>
    <div
      class="px-0 py-3 border-b group-hover:border-transparent flex-1 border-n-slate-3 min-w-0"
    >
      <div
        v-if="showMetaSection"
        class="flex items-center min-w-0 gap-1"
        :class="{
          'ltr:ml-2 rtl:mr-2': !compact,
          'mx-2': compact,
        }"
      >
        <InboxName v-if="showInboxName" :inbox="inbox" class="flex-1 min-w-0" />
        <div
          class="flex items-center gap-2 flex-shrink-0"
          :class="{
            'flex-1 justify-end': !showInboxName,
          }"
        >
          <PriorityMark :priority="chat.priority" class="flex-shrink-0" />
        </div>
      </div>
      <div class="mx-2 flex items-start gap-2 min-w-0">
        <div class="flex-1 min-w-0">
          <h4
            class="conversation--user text-sm my-0 capitalize pt-0.5 text-ellipsis overflow-hidden whitespace-nowrap text-n-slate-12"
            :class="hasPendingUnread ? 'font-semibold' : 'font-medium'"
          >
            {{ currentContact.name }}
          </h4>
          <VoiceCallStatus
            v-if="voiceCallData.status"
            key="voice-status-row"
            :status="voiceCallData.status"
            :direction="voiceCallData.direction"
            :message-preview-class="messagePreviewClass"
            class="!mx-0"
          />
          <MessagePreview
            v-else-if="lastMessageInChat"
            key="message-preview"
            :message="lastMessageInChat"
            class="my-0 mx-0 leading-6 h-6 flex-1 min-w-0 text-sm"
            :class="messagePreviewClass"
          />
          <p
            v-else
            key="no-messages"
            class="text-n-slate-11 text-sm my-0 mx-0 leading-6 h-6 flex-1 min-w-0 overflow-hidden text-ellipsis whitespace-nowrap"
            :class="messagePreviewClass"
          >
            <fluent-icon
              size="16"
              class="-mt-0.5 align-middle inline-block text-n-slate-10"
              icon="info"
            />
            <span class="mx-0.5">
              {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
            </span>
          </p>
        </div>
        <div class="flex flex-col items-end flex-shrink-0 gap-1 pt-0.5">
          <div
            class="flex items-center justify-end gap-1 min-h-4 max-w-[180px]"
          >
            <span
              v-if="showAssignee && assignee.name"
              class="text-n-slate-11 text-xs font-medium leading-4 py-0 px-0 inline-flex items-center truncate max-w-[110px]"
              :title="assignee.name"
            >
              <fluent-icon icon="person" size="12" class="text-n-slate-11" />
              {{ assignee.name }}
            </span>
            <span class="font-normal leading-4 text-xxs whitespace-nowrap">
              <TimeAgo
                :last-activity-timestamp="chat.timestamp"
                :created-at-timestamp="chat.created_at"
              />
            </span>
          </div>

          <div class="relative flex items-center justify-end min-h-5">
            <div
              class="flex items-center justify-end gap-1 transition-all duration-150"
              :class="
                showContextMenuTrigger
                  ? 'ltr:pr-7 rtl:pl-7'
                  : 'ltr:pr-0 rtl:pl-0'
              "
            >
              <span
                v-if="assignedTeam"
                class="px-2 py-0.5 rounded-full bg-n-slate-3 text-xs font-medium text-n-slate-12 truncate max-w-[120px]"
                :title="`${$t('CHAT_LIST.ASSIGNED_TEAM')}: ${assignedTeam.name}`"
              >
                {{ assignedTeam.name }}
              </span>
              <TelegramExpiredBadge
                v-if="isTelegramConversationExpired"
                class="max-w-[140px] truncate"
              />
              <WhatsAppMessageWindowBadge
                v-if="whatsAppMessageWindowStatus"
                :status="whatsAppMessageWindowStatus"
                class="max-w-[150px]"
              />
              <span
                v-if="hasPendingUnread"
                class="shadow-lg rounded-full text-xxs font-semibold h-4 leading-4 min-w-[1rem] px-1 py-0 text-center text-white bg-n-teal-9"
              >
                {{
                  unreadCount > 9
                    ? $t('CONVERSATION.UNREAD_OVER_NINE')
                    : unreadCount
                }}
              </span>
            </div>
            <button
              v-if="props.enableContextMenu"
              type="button"
              class="absolute ltr:right-0 rtl:left-0 top-1/2 -translate-y-1/2 w-5 h-5 z-10 flex items-center justify-center text-n-slate-10 hover:text-n-slate-12 focus:outline-none transition-opacity duration-150 before:content-[''] before:block before:w-0 before:h-0 before:border-l-[4px] before:border-r-[4px] before:border-t-[5px] before:border-l-transparent before:border-r-transparent before:border-t-current before:-translate-y-px"
              :class="
                showContextMenuTrigger
                  ? 'opacity-100 pointer-events-auto'
                  : 'opacity-0 pointer-events-none'
              "
              @mousedown.prevent="openContextMenuFromButton"
            />
          </div>
        </div>
      </div>
      <CardLabels
        v-if="showLabelsSection"
        :conversation-labels="chat.labels"
        :conversation-id="chat.id"
        class="mt-0.5 mx-2 mb-0"
      >
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
    <ContextMenu
      v-if="showContextMenu"
      :x="contextMenu.x"
      :y="contextMenu.y"
      @close="closeContextMenu"
    >
      <ConversationContextMenu
        :status="chat.status"
        :inbox-id="inbox.id"
        :priority="chat.priority"
        :chat-id="chat.id"
        :has-unread-messages="hasUnread"
        :conversation-labels="chat.labels"
        :conversation-url="conversationPath"
        :allowed-options="allowedContextMenuOptions"
        @update-conversation="onUpdateConversation"
        @assign-agent="onAssignAgent"
        @assign-label="onAssignLabel"
        @remove-label="onRemoveLabel"
        @assign-team="onAssignTeam"
        @mark-as-unread="markAsUnread"
        @mark-as-read="markAsRead"
        @assign-priority="assignPriority"
        @delete-conversation="deleteConversation"
        @close="closeContextMenu"
      />
    </ContextMenu>
  </div>
</template>
