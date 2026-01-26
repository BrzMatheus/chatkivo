<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  active: {
    type: Boolean,
    default: false,
  },
  inbox: {
    type: Object,
    required: true,
  },
});

const isApiChannel = computed(
  () => props.inbox?.channel_type === 'Channel::Api'
);
</script>

<template>
  <span
    class="size-5 flex-shrink-0 grid place-content-center rounded-full bg-n-alpha-2"
    :class="{ 'bg-n-solid-blue': active }"
  >
    <Icon v-if="isApiChannel" icon="i-woot-whatsapp" class="size-3" />
    <ChannelIcon v-else :inbox="inbox" class="size-3" />
  </span>
  <div class="flex-1 truncate min-w-0 w-0">{{ label }}</div>
</template>
