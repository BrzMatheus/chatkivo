<script setup>
import ChannelIcon from 'next/icon/ChannelIcon.vue';

defineProps({
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
</script>

<template>
  <span
    class="size-5 flex-shrink-0 grid place-content-center rounded-full bg-n-alpha-2"
    :class="{ 'bg-n-solid-blue': active }"
  >
    <ChannelIcon :inbox="inbox" class="size-3" />
  </span>
  <div class="flex-1 truncate min-w-0 w-0">{{ label }}</div>
</template>
