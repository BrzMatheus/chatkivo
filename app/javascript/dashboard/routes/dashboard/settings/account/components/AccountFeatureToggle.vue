<script setup>
import { computed } from 'vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    required: true,
  },
  enabled: {
    type: Boolean,
    default: false,
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);

const model = computed({
  get: () => props.enabled,
  set: value => emit('toggle', value),
});
</script>

<template>
  <div
    class="flex items-center justify-between gap-4 p-4 rounded-xl border border-n-weak bg-n-solid-2"
    :class="{ 'opacity-60 pointer-events-none': isSaving }"
  >
    <div class="min-w-0 flex-1">
      <h4 class="text-sm font-medium text-n-slate-12">
        {{ title }}
      </h4>
      <p class="mt-1 mb-0 text-sm text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <div class="flex flex-col items-end gap-2 flex-shrink-0">
      <Switch v-model="model" />
      <span v-if="isSaving" class="text-xs text-n-slate-10">
        {{ $t('GENERAL_SETTINGS.SPECIFIC.SAVING') }}
      </span>
    </div>
  </div>
</template>
