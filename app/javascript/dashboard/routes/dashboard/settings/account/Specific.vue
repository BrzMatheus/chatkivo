<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SectionLayout from './components/SectionLayout.vue';
import AccountFeatureToggle from './components/AccountFeatureToggle.vue';
import AccountSettingsHeader from './components/AccountSettingsHeader.vue';

const ACCOUNT_SETTING_KEYS = {
  HIDE_PRIVATE_MESSAGES: 'hide_private_messages',
};

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const getUIFlags = useMapGetter('accounts/getUIFlags');

const featureConfigs = computed(() => [
  {
    key: FEATURE_FLAGS.AUTOMATIONS,
    title: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.AUTOMATIONS.TITLE'),
    description: t(
      'GENERAL_SETTINGS.SPECIFIC.FEATURES.AUTOMATIONS.DESCRIPTION'
    ),
  },
  {
    key: FEATURE_FLAGS.MACROS,
    title: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.MACROS.TITLE'),
    description: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.MACROS.DESCRIPTION'),
  },
  {
    key: FEATURE_FLAGS.INTEGRATIONS,
    title: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.INTEGRATIONS.TITLE'),
    description: t(
      'GENERAL_SETTINGS.SPECIFIC.FEATURES.INTEGRATIONS.DESCRIPTION'
    ),
  },
  {
    key: FEATURE_FLAGS.REPORTS,
    title: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.REPORTS.TITLE'),
    description: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.REPORTS.DESCRIPTION'),
  },
  {
    key: FEATURE_FLAGS.CAMPAIGNS,
    title: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.CAMPAIGNS.TITLE'),
    description: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.CAMPAIGNS.DESCRIPTION'),
  },
  {
    key: FEATURE_FLAGS.HELP_CENTER,
    title: t('GENERAL_SETTINGS.SPECIFIC.FEATURES.HELP_CENTER.TITLE'),
    description: t(
      'GENERAL_SETTINGS.SPECIFIC.FEATURES.HELP_CENTER.DESCRIPTION'
    ),
  },
]);

const accountSettingConfigs = computed(() => [
  {
    key: ACCOUNT_SETTING_KEYS.HIDE_PRIVATE_MESSAGES,
    title: t('GENERAL_SETTINGS.SPECIFIC.SETTINGS.HIDE_PRIVATE_MESSAGES.TITLE'),
    description: t(
      'GENERAL_SETTINGS.SPECIFIC.SETTINGS.HIDE_PRIVATE_MESSAGES.DESCRIPTION'
    ),
  },
]);

const selectedFeatureFlags = ref([]);
const accountSettings = ref({
  [ACCOUNT_SETTING_KEYS.HIDE_PRIVATE_MESSAGES]: false,
});
const changedKeys = ref([]);

const uiFlags = computed(() => getUIFlags.value);
const isSaving = computed(() => uiFlags.value.isUpdating);

const enabledFeatureMap = computed(() =>
  selectedFeatureFlags.value.reduce((result, featureKey) => {
    result[featureKey] = true;
    return result;
  }, {})
);

watch(
  currentAccount,
  account => {
    if (!account) return;

    selectedFeatureFlags.value = Object.keys(account.features || {});
    accountSettings.value = {
      [ACCOUNT_SETTING_KEYS.HIDE_PRIVATE_MESSAGES]:
        !!account.settings?.hide_private_messages,
    };
    changedKeys.value = [];
  },
  { deep: true, immediate: true }
);

const toggleFeature = (featureKey, enabled) => {
  const nextFeatureFlags = new Set(selectedFeatureFlags.value);

  if (enabled) {
    nextFeatureFlags.add(featureKey);
  } else {
    nextFeatureFlags.delete(featureKey);
  }

  selectedFeatureFlags.value = [...nextFeatureFlags];

  if (!changedKeys.value.includes(featureKey)) {
    changedKeys.value = [...changedKeys.value, featureKey];
  }
};

const toggleAccountSetting = (settingKey, enabled) => {
  accountSettings.value = {
    ...accountSettings.value,
    [settingKey]: enabled,
  };

  if (!changedKeys.value.includes(settingKey)) {
    changedKeys.value = [...changedKeys.value, settingKey];
  }
};

const saveSpecificSettings = async () => {
  try {
    await updateAccount({
      selected_feature_flags: selectedFeatureFlags.value,
      ...accountSettings.value,
    });
    changedKeys.value = [];
    useAlert(t('GENERAL_SETTINGS.SPECIFIC.UPDATE.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.SPECIFIC.UPDATE.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col max-w-2xl mx-auto w-full gap-6">
    <AccountSettingsHeader />

    <SectionLayout
      :title="$t('GENERAL_SETTINGS.SPECIFIC.TITLE')"
      :description="$t('GENERAL_SETTINGS.SPECIFIC.NOTE')"
    >
      <div v-if="!uiFlags.isFetchingItem">
        <div class="grid gap-3">
          <AccountFeatureToggle
            v-for="setting in accountSettingConfigs"
            :key="setting.key"
            :title="setting.title"
            :description="setting.description"
            :enabled="!!accountSettings[setting.key]"
            :is-saving="isSaving && changedKeys.includes(setting.key)"
            @toggle="value => toggleAccountSetting(setting.key, value)"
          />

          <AccountFeatureToggle
            v-for="feature in featureConfigs"
            :key="feature.key"
            :title="feature.title"
            :description="feature.description"
            :enabled="!!enabledFeatureMap[feature.key]"
            :is-saving="isSaving && changedKeys.includes(feature.key)"
            @toggle="value => toggleFeature(feature.key, value)"
          />
        </div>

        <div class="mt-5">
          <NextButton
            blue
            :label="$t('GENERAL_SETTINGS.SPECIFIC.SUBMIT')"
            :is-loading="isSaving"
            @click="saveSpecificSettings"
          />
        </div>
      </div>
      <woot-loading-state v-else />
    </SectionLayout>
  </div>
</template>
