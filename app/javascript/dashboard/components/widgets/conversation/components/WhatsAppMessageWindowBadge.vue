<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { WHATSAPP_MESSAGE_WINDOW_STATUS } from 'dashboard/helper/whatsappMessageWindowHelper';

const props = defineProps({
  status: {
    type: String,
    required: true,
  },
});

const { t } = useI18n();

const isExpired = computed(
  () => props.status === WHATSAPP_MESSAGE_WINDOW_STATUS.EXPIRED
);

const label = computed(() =>
  isExpired.value
    ? t('CONVERSATION.WHATSAPP_MESSAGE_WINDOW.EXPIRED_BADGE')
    : t('CONVERSATION.WHATSAPP_MESSAGE_WINDOW.WARNING_BADGE')
);

const tooltip = computed(() =>
  isExpired.value
    ? t('CONVERSATION.WHATSAPP_MESSAGE_WINDOW.EXPIRED_TOOLTIP')
    : t('CONVERSATION.WHATSAPP_MESSAGE_WINDOW.WARNING_TOOLTIP')
);

const badgeClass = computed(() =>
  isExpired.value
    ? 'border-n-ruby-7 bg-n-ruby-5 text-n-ruby-12'
    : 'border-n-amber-7 bg-n-amber-5 text-n-amber-12'
);
</script>

<template>
  <span
    v-tooltip="tooltip"
    class="inline-flex items-center rounded-full border border-solid px-2 py-0.5 text-xs font-medium leading-4 truncate"
    :class="badgeClass"
  >
    {{ label }}
  </span>
</template>
