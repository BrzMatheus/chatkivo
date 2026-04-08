<script setup>
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <span
    v-tooltip="t('CONVERSATION.TELEGRAM_EXPIRATION.TOOLTIP')"
    class="inline-flex items-center rounded-full border border-solid border-n-ruby-7 bg-n-ruby-5 px-2 py-0.5 text-xs font-medium leading-4 text-n-ruby-12"
  >
    {{ t('CONVERSATION.TELEGRAM_EXPIRATION.BADGE') }}
  </span>
</template>
