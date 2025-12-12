<script setup>
import { computed } from 'vue';
import { useAttrs } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  variant: {
    type: String,
    default: 'sidebar',
    validator: value => ['sidebar', 'header'].includes(value),
  },
});

const attrs = useAttrs();
const globalConfig = useMapGetter('globalConfig/get');

const logoSource = computed(() => {
  if (props.variant === 'header') {
    return '/brand-assets/logo_thumbnailheader.svg';
  }
  return '/brand-assets/logo_thumbnailsidebar.svg';
});
</script>

<template>
  <img
    v-if="globalConfig.logoThumbnail"
    v-bind="attrs"
    :src="globalConfig.logoThumbnail"
  />
  <img v-else v-bind="attrs" :src="logoSource" alt="Logo" />
</template>
