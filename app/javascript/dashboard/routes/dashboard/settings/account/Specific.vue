<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  DASHBOARD_APPEARANCE_SETTING_KEYS,
  DEFAULT_DASHBOARD_APPEARANCE,
  getDashboardAppearanceSettings,
} from 'dashboard/helper/dashboardAppearanceHelper';
import SectionLayout from './components/SectionLayout.vue';
import AccountFeatureToggle from './components/AccountFeatureToggle.vue';
import AccountSettingsHeader from './components/AccountSettingsHeader.vue';

const ACCOUNT_SETTING_KEYS = {
  HIDE_PRIVATE_MESSAGES: 'hide_private_messages',
  DISABLE_WHATSAPP_IMAGE_UPLOADS: 'disable_whatsapp_image_uploads',
};

const APPEARANCE_CHANGE_KEY = 'dashboard_appearance';
const AGENT_SIGNATURE_CHANGE_KEY = 'agent_message_signature';
const AGENT_NAME_TOKEN = '{{agent_name}}';
const AGENT_NAME_TOKEN_REGEX = /\{\{\s*agent_name\s*\}\}/g;
const AGENT_SIGNATURE_SETTING_KEYS = {
  ENABLED: 'agent_message_signature_enabled',
  TEMPLATE: 'agent_message_signature_template',
  MODE: 'agent_message_signature_mode',
};
const AGENT_SIGNATURE_MODES = {
  ALL_MESSAGES: 'all_messages',
  FIRST_MESSAGE_PER_AGENT: 'first_message_per_agent',
};
const DEFAULT_AGENT_SIGNATURE_SETTINGS = {
  [AGENT_SIGNATURE_SETTING_KEYS.ENABLED]: false,
  [AGENT_SIGNATURE_SETTING_KEYS.TEMPLATE]: `Atendente: ${AGENT_NAME_TOKEN}`,
  [AGENT_SIGNATURE_SETTING_KEYS.MODE]:
    AGENT_SIGNATURE_MODES.FIRST_MESSAGE_PER_AGENT,
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
  {
    key: ACCOUNT_SETTING_KEYS.DISABLE_WHATSAPP_IMAGE_UPLOADS,
    title: t(
      'GENERAL_SETTINGS.SPECIFIC.SETTINGS.DISABLE_WHATSAPP_IMAGE_UPLOADS.TITLE'
    ),
    description: t(
      'GENERAL_SETTINGS.SPECIFIC.SETTINGS.DISABLE_WHATSAPP_IMAGE_UPLOADS.DESCRIPTION'
    ),
  },
]);

const appearanceColorConfigs = computed(() => [
  {
    key: DASHBOARD_APPEARANCE_SETTING_KEYS.PRIMARY_COLOR,
    label: t('GENERAL_SETTINGS.SPECIFIC.APPEARANCE.PRIMARY_COLOR.LABEL'),
    description: t(
      'GENERAL_SETTINGS.SPECIFIC.APPEARANCE.PRIMARY_COLOR.DESCRIPTION'
    ),
  },
  {
    key: DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_LIGHT,
    label: t(
      'GENERAL_SETTINGS.SPECIFIC.APPEARANCE.BACKGROUND_COLOR_LIGHT.LABEL'
    ),
    description: t(
      'GENERAL_SETTINGS.SPECIFIC.APPEARANCE.BACKGROUND_COLOR_LIGHT.DESCRIPTION'
    ),
  },
  {
    key: DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_DARK,
    label: t(
      'GENERAL_SETTINGS.SPECIFIC.APPEARANCE.BACKGROUND_COLOR_DARK.LABEL'
    ),
    description: t(
      'GENERAL_SETTINGS.SPECIFIC.APPEARANCE.BACKGROUND_COLOR_DARK.DESCRIPTION'
    ),
  },
]);

const getAgentSignatureSettings = settings => {
  const mode = Object.values(AGENT_SIGNATURE_MODES).includes(
    settings?.[AGENT_SIGNATURE_SETTING_KEYS.MODE]
  )
    ? settings[AGENT_SIGNATURE_SETTING_KEYS.MODE]
    : DEFAULT_AGENT_SIGNATURE_SETTINGS[AGENT_SIGNATURE_SETTING_KEYS.MODE];

  return {
    [AGENT_SIGNATURE_SETTING_KEYS.ENABLED]:
      !!settings?.[AGENT_SIGNATURE_SETTING_KEYS.ENABLED],
    [AGENT_SIGNATURE_SETTING_KEYS.TEMPLATE]:
      settings?.[AGENT_SIGNATURE_SETTING_KEYS.TEMPLATE] ||
      DEFAULT_AGENT_SIGNATURE_SETTINGS[AGENT_SIGNATURE_SETTING_KEYS.TEMPLATE],
    [AGENT_SIGNATURE_SETTING_KEYS.MODE]: mode,
  };
};

const agentSignatureModeOptions = computed(() => [
  {
    value: AGENT_SIGNATURE_MODES.FIRST_MESSAGE_PER_AGENT,
    label: t(
      'GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.MODES.FIRST_MESSAGE_PER_AGENT'
    ),
  },
  {
    value: AGENT_SIGNATURE_MODES.ALL_MESSAGES,
    label: t('GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.MODES.ALL_MESSAGES'),
  },
]);

const selectedFeatureFlags = ref([]);
const accountSettings = ref({
  [ACCOUNT_SETTING_KEYS.HIDE_PRIVATE_MESSAGES]: false,
  [ACCOUNT_SETTING_KEYS.DISABLE_WHATSAPP_IMAGE_UPLOADS]: false,
});
const dashboardAppearanceSettings = ref({ ...DEFAULT_DASHBOARD_APPEARANCE });
const agentSignatureSettings = ref({ ...DEFAULT_AGENT_SIGNATURE_SETTINGS });
const changedKeys = ref([]);

const uiFlags = computed(() => getUIFlags.value);
const isSaving = computed(() => uiFlags.value.isUpdating);
const agentSignaturePreview = computed(() => {
  const template =
    agentSignatureSettings.value[AGENT_SIGNATURE_SETTING_KEYS.TEMPLATE] ||
    DEFAULT_AGENT_SIGNATURE_SETTINGS[AGENT_SIGNATURE_SETTING_KEYS.TEMPLATE];
  const agentName = t(
    'GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.PREVIEW_AGENT_NAME'
  );
  const signatureText = template.match(AGENT_NAME_TOKEN_REGEX)
    ? template.replace(AGENT_NAME_TOKEN_REGEX, agentName)
    : `${template} ${agentName}`;
  const signaturePrefix = signatureText.endsWith('\n')
    ? signatureText
    : `${signatureText}\n`;

  return `${signaturePrefix}${t(
    'GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.PREVIEW_MESSAGE'
  )}`;
});

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
      [ACCOUNT_SETTING_KEYS.DISABLE_WHATSAPP_IMAGE_UPLOADS]:
        !!account.settings?.disable_whatsapp_image_uploads,
    };
    dashboardAppearanceSettings.value = getDashboardAppearanceSettings(
      account.settings
    );
    agentSignatureSettings.value = getAgentSignatureSettings(account.settings);
    changedKeys.value = [];
  },
  { deep: true, immediate: true }
);

const markChanged = key => {
  if (!changedKeys.value.includes(key)) {
    changedKeys.value = [...changedKeys.value, key];
  }
};

const updateAgentSignatureSetting = (settingKey, value) => {
  agentSignatureSettings.value = {
    ...agentSignatureSettings.value,
    [settingKey]: value,
  };

  markChanged(AGENT_SIGNATURE_CHANGE_KEY);
};

const agentSignatureEnabledModel = computed({
  get: () =>
    !!agentSignatureSettings.value[AGENT_SIGNATURE_SETTING_KEYS.ENABLED],
  set: value =>
    updateAgentSignatureSetting(AGENT_SIGNATURE_SETTING_KEYS.ENABLED, value),
});

const toggleFeature = (featureKey, enabled) => {
  const nextFeatureFlags = new Set(selectedFeatureFlags.value);

  if (enabled) {
    nextFeatureFlags.add(featureKey);
  } else {
    nextFeatureFlags.delete(featureKey);
  }

  selectedFeatureFlags.value = [...nextFeatureFlags];

  markChanged(featureKey);
};

const toggleAccountSetting = (settingKey, enabled) => {
  accountSettings.value = {
    ...accountSettings.value,
    [settingKey]: enabled,
  };

  markChanged(settingKey);
};

const updateDashboardAppearanceSetting = (settingKey, value) => {
  dashboardAppearanceSettings.value = {
    ...dashboardAppearanceSettings.value,
    [settingKey]: value,
  };

  markChanged(APPEARANCE_CHANGE_KEY);
};

const resetDashboardAppearance = () => {
  dashboardAppearanceSettings.value = { ...DEFAULT_DASHBOARD_APPEARANCE };
  markChanged(APPEARANCE_CHANGE_KEY);
};

const saveSpecificSettings = async () => {
  try {
    const dashboardAppearancePayload = changedKeys.value.includes(
      APPEARANCE_CHANGE_KEY
    )
      ? dashboardAppearanceSettings.value
      : {};
    const agentSignaturePayload = changedKeys.value.includes(
      AGENT_SIGNATURE_CHANGE_KEY
    )
      ? agentSignatureSettings.value
      : {};

    await updateAccount({
      selected_feature_flags: selectedFeatureFlags.value,
      ...accountSettings.value,
      ...dashboardAppearancePayload,
      ...agentSignaturePayload,
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

          <div
            class="flex flex-col gap-4 p-4 rounded-xl border border-n-weak bg-n-solid-2"
            :class="{
              'opacity-60 pointer-events-none':
                isSaving && changedKeys.includes(APPEARANCE_CHANGE_KEY),
            }"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <h4 class="text-sm font-medium text-n-slate-12">
                  {{ $t('GENERAL_SETTINGS.SPECIFIC.APPEARANCE.TITLE') }}
                </h4>
                <p class="mt-1 mb-0 text-sm text-n-slate-11">
                  {{ $t('GENERAL_SETTINGS.SPECIFIC.APPEARANCE.DESCRIPTION') }}
                </p>
              </div>
              <NextButton
                slate
                faded
                sm
                :label="$t('GENERAL_SETTINGS.SPECIFIC.APPEARANCE.RESET')"
                class="flex-shrink-0"
                @click="resetDashboardAppearance"
              />
            </div>

            <div class="grid gap-4 sm:grid-cols-3">
              <div
                v-for="colorSetting in appearanceColorConfigs"
                :key="colorSetting.key"
                class="grid min-w-0 gap-2"
              >
                <div class="min-w-0">
                  <span class="block text-sm font-medium text-n-slate-12">
                    {{ colorSetting.label }}
                  </span>
                  <span class="block text-xs leading-5 text-n-slate-11">
                    {{ colorSetting.description }}
                  </span>
                </div>
                <ColorPicker
                  :model-value="dashboardAppearanceSettings[colorSetting.key]"
                  @update:model-value="
                    value =>
                      updateDashboardAppearanceSetting(colorSetting.key, value)
                  "
                />
              </div>
            </div>

            <span
              v-if="isSaving && changedKeys.includes(APPEARANCE_CHANGE_KEY)"
              class="text-xs text-n-slate-10"
            >
              {{ $t('GENERAL_SETTINGS.SPECIFIC.SAVING') }}
            </span>
          </div>

          <div
            class="flex flex-col gap-4 p-4 rounded-xl border border-n-weak bg-n-solid-2"
            :class="{
              'opacity-60 pointer-events-none':
                isSaving && changedKeys.includes(AGENT_SIGNATURE_CHANGE_KEY),
            }"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <h4 class="text-sm font-medium text-n-slate-12">
                  {{ $t('GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.TITLE') }}
                </h4>
                <p class="mt-1 mb-0 text-sm text-n-slate-11">
                  {{
                    $t('GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.DESCRIPTION')
                  }}
                </p>
              </div>
              <Switch v-model="agentSignatureEnabledModel" />
            </div>

            <div v-if="agentSignatureEnabledModel" class="grid gap-4">
              <TextArea
                :model-value="
                  agentSignatureSettings[AGENT_SIGNATURE_SETTING_KEYS.TEMPLATE]
                "
                :label="
                  $t('GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.TEMPLATE.LABEL')
                "
                :placeholder="
                  $t(
                    'GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.TEMPLATE.PLACEHOLDER',
                    { token: AGENT_NAME_TOKEN }
                  )
                "
                :message="
                  $t(
                    'GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.TEMPLATE.HELP',
                    { token: AGENT_NAME_TOKEN }
                  )
                "
                class="w-full"
                :max-length="160"
                show-character-count
                auto-height
                resize
                min-height="5rem"
                @update:model-value="
                  value =>
                    updateAgentSignatureSetting(
                      AGENT_SIGNATURE_SETTING_KEYS.TEMPLATE,
                      value
                    )
                "
              />

              <div class="grid gap-2">
                <label class="mb-0 text-sm font-medium text-n-slate-12">
                  {{
                    $t('GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.MODE.LABEL')
                  }}
                </label>
                <select
                  :value="
                    agentSignatureSettings[AGENT_SIGNATURE_SETTING_KEYS.MODE]
                  "
                  class="!mb-0 text-sm"
                  @change="
                    event =>
                      updateAgentSignatureSetting(
                        AGENT_SIGNATURE_SETTING_KEYS.MODE,
                        event.target.value
                      )
                  "
                >
                  <option
                    v-for="option in agentSignatureModeOptions"
                    :key="option.value"
                    :value="option.value"
                  >
                    {{ option.label }}
                  </option>
                </select>
              </div>

              <div class="p-3 rounded-lg bg-n-alpha-black2">
                <span class="block text-xs font-medium text-n-slate-11">
                  {{
                    $t(
                      'GENERAL_SETTINGS.SPECIFIC.AGENT_SIGNATURE.PREVIEW_LABEL'
                    )
                  }}
                </span>
                <p
                  class="mt-1 mb-0 text-sm whitespace-pre-line text-n-slate-12"
                >
                  {{ agentSignaturePreview }}
                </p>
              </div>
            </div>

            <span
              v-if="
                isSaving && changedKeys.includes(AGENT_SIGNATURE_CHANGE_KEY)
              "
              class="text-xs text-n-slate-10"
            >
              {{ $t('GENERAL_SETTINGS.SPECIFIC.SAVING') }}
            </span>
          </div>

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
