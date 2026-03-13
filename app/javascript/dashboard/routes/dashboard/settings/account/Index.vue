<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AccountId from './components/AccountId.vue';
import BuildInfo from './components/BuildInfo.vue';
import AccountDelete from './components/AccountDelete.vue';
import AudioTranscription from './components/AudioTranscription.vue';
import SectionLayout from './components/SectionLayout.vue';
import AccountSettingsHeader from './components/AccountSettingsHeader.vue';

const { locale: i18nLocale, t } = useI18n();
const { uiSettings } = useUISettings();
const { enabledLanguages } = useConfig();
const { accountId, currentAccount, updateAccount } = useAccount();

const getUIFlags = useMapGetter('accounts/getUIFlags');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const isOnChatwootCloud = useMapGetter('globalConfig/isOnChatwootCloud');

const id = ref('');
const name = ref('');
const locale = ref('en');
const domain = ref('');
const supportEmail = ref('');
const features = ref({});

const rules = computed(() => ({
  name: { required },
  locale: { required },
}));

const v$ = useVuelidate(rules, {
  name,
  locale,
});

const uiFlags = computed(() => getUIFlags.value);

const languagesSortedByCode = computed(() =>
  [...enabledLanguages].sort((l1, l2) =>
    l1.iso_639_1_code.localeCompare(l2.iso_639_1_code)
  )
);

const isUpdating = computed(() => uiFlags.value.isUpdating);

const featureInboundEmailEnabled = computed(
  () => !!features.value?.inbound_emails
);

const featureCustomReplyDomainEnabled = computed(
  () =>
    featureInboundEmailEnabled.value && !!features.value?.custom_reply_domain
);

const featureCustomReplyEmailEnabled = computed(() => {
  return (
    featureInboundEmailEnabled.value && !!features.value?.custom_reply_email
  );
});

const showAudioTranscriptionConfig = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.CAPTAIN)
);

const syncAccount = account => {
  if (!account?.id) return;

  i18nLocale.value = uiSettings.value?.locale || account.locale;
  name.value = account.name;
  locale.value = account.locale;
  id.value = account.id;
  domain.value = account.domain;
  supportEmail.value = account.support_email;
  features.value = account.features || {};
};

watch(currentAccount, account => syncAccount(account), {
  deep: true,
  immediate: true,
});

const updateAccountSettings = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) {
    useAlert(t('GENERAL_SETTINGS.FORM.ERROR'));
    return;
  }

  try {
    await updateAccount({
      locale: locale.value,
      name: name.value,
      domain: domain.value,
      support_email: supportEmail.value,
    });

    i18nLocale.value = uiSettings.value?.locale || locale.value;
    useAlert(t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.UPDATE.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col max-w-2xl mx-auto w-full gap-6">
    <AccountSettingsHeader />

    <div class="flex-grow flex-shrink min-w-0">
      <SectionLayout
        :title="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.TITLE')"
        :description="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.NOTE')"
      >
        <form
          v-if="!uiFlags.isFetchingItem"
          class="grid gap-4"
          @submit.prevent="updateAccountSettings"
        >
          <WithLabel
            :has-error="v$.name.$error"
            :label="$t('GENERAL_SETTINGS.FORM.NAME.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.NAME.ERROR')"
          >
            <NextInput
              v-model="name"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER')"
              @blur="v$.name.$touch"
            />
          </WithLabel>
          <WithLabel
            :has-error="v$.locale.$error"
            :label="$t('GENERAL_SETTINGS.FORM.LANGUAGE.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.LANGUAGE.ERROR')"
          >
            <select v-model="locale" class="!mb-0 text-sm">
              <option
                v-for="lang in languagesSortedByCode"
                :key="lang.iso_639_1_code"
                :value="lang.iso_639_1_code"
              >
                {{ lang.name }}
              </option>
            </select>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyDomainEnabled"
            :label="$t('GENERAL_SETTINGS.FORM.DOMAIN.LABEL')"
          >
            <NextInput
              v-model="domain"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.DOMAIN.PLACEHOLDER')"
            />
            <template #help>
              {{
                featureInboundEmailEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED')
              }}

              {{
                featureCustomReplyDomainEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.CUSTOM_EMAIL_DOMAIN_ENABLED')
              }}
            </template>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyEmailEnabled"
            :label="$t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.LABEL')"
          >
            <NextInput
              v-model="supportEmail"
              type="text"
              class="w-full"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER')
              "
            />
          </WithLabel>
          <div>
            <NextButton blue :is-loading="isUpdating" type="submit">
              {{ $t('GENERAL_SETTINGS.SUBMIT') }}
            </NextButton>
          </div>
        </form>
      </SectionLayout>

      <woot-loading-state v-if="uiFlags.isFetchingItem" />
    </div>

    <AudioTranscription v-if="showAudioTranscriptionConfig" />
    <AccountId />
    <div v-if="!uiFlags.isFetchingItem && isOnChatwootCloud">
      <AccountDelete />
    </div>
    <BuildInfo />
  </div>
</template>
