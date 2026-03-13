<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const tabs = computed(() => [
  {
    key: 'general_settings_index',
    label: t('GENERAL_SETTINGS.NAVIGATION.GENERAL'),
    to: accountScopedRoute('general_settings_index'),
  },
  {
    key: 'specific_settings_index',
    label: t('GENERAL_SETTINGS.NAVIGATION.SPECIFIC'),
    to: accountScopedRoute('specific_settings_index'),
  },
]);

const activeTabIndex = computed(() =>
  Math.max(
    tabs.value.findIndex(tab => tab.key === route.name),
    0
  )
);

const handleTabChange = tab => {
  router.push(tab.to);
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <BaseSettingsHeader
      :title="t('GENERAL_SETTINGS.TITLE')"
      :description="t('GENERAL_SETTINGS.DESCRIPTION')"
    />
    <TabBar
      :tabs="tabs"
      :initial-active-tab="activeTabIndex"
      class="max-w-max"
      @tab-changed="handleTabChange"
    />
  </div>
</template>
