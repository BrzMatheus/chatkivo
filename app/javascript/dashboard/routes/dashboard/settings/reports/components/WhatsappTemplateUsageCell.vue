<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  usage: {
    type: Object,
    default: () => ({}),
  },
});

const { t, n } = useI18n();

const categoryKeys = [
  'utility',
  'marketing',
  'authentication',
  'service',
  'other',
];

const categoryLabels = computed(() => ({
  utility: t('SUMMARY_REPORTS.WHATSAPP_TEMPLATE_CATEGORIES.UTILITY'),
  marketing: t('SUMMARY_REPORTS.WHATSAPP_TEMPLATE_CATEGORIES.MARKETING'),
  authentication: t(
    'SUMMARY_REPORTS.WHATSAPP_TEMPLATE_CATEGORIES.AUTHENTICATION'
  ),
  service: t('SUMMARY_REPORTS.WHATSAPP_TEMPLATE_CATEGORIES.SERVICE'),
  other: t('SUMMARY_REPORTS.WHATSAPP_TEMPLATE_CATEGORIES.OTHER'),
}));

const countFor = key => Number(props.usage?.[key] || 0);

const total = computed(() => countFor('total'));

const categoryItems = computed(() =>
  categoryKeys
    .map(key => ({
      key,
      count: countFor(key),
      label: categoryLabels.value[key],
    }))
    .filter(item => item.count > 0)
);
</script>

<template>
  <div class="flex flex-wrap items-center gap-1.5 min-w-60">
    <span
      class="inline-flex items-center gap-1 rounded-md bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-12"
    >
      {{ t('SUMMARY_REPORTS.WHATSAPP_TEMPLATE_TOTAL', { count: n(total) }) }}
    </span>
    <span
      v-for="item in categoryItems"
      :key="item.key"
      class="inline-flex items-center gap-1 rounded-md bg-n-solid-3 px-2 py-1 text-xs text-n-slate-11"
    >
      <span>{{ item.label }}</span>
      <span class="font-medium text-n-slate-12">{{ n(item.count) }}</span>
    </span>
  </div>
</template>
