<script setup>
/* eslint-disable no-console */
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:show', 'create']);

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const funnelName = ref('');

const canCreate = computed(() => {
  return funnelName.value.trim().length > 0;
});

const resetForm = () => {
  funnelName.value = '';
};

// Watch para controlar abertura/fechamento do dialog
watch(
  () => props.show,
  async (newValue, oldValue) => {
    console.log(
      '[DEBUG] CreateFunnelDialog show prop changed to:',
      newValue,
      'from:',
      oldValue,
      'dialogRef:',
      !!dialogRef.value
    );
    // Só processar se o valor realmente mudou
    if (newValue === oldValue) {
      console.log('[DEBUG] CreateFunnelDialog show value unchanged, skipping');
      return;
    }
    if (newValue) {
      await nextTick();
      console.log('[DEBUG] After nextTick, dialogRef:', !!dialogRef.value);
      if (dialogRef.value) {
        console.log('[DEBUG] Opening CreateFunnelDialog');
        dialogRef.value.open();
      } else {
        console.error('[DEBUG] dialogRef is null!');
      }
    } else if (dialogRef.value) {
      dialogRef.value.close();
    }
  }
);

const handleCreate = async () => {
  // #region agent log
  fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      location: 'CreateFunnelDialog.vue:handleCreate',
      message: 'handleCreate called',
      data: {
        funnelNameValue: funnelName.value,
        funnelNameTrimmed: funnelName.value?.trim(),
        canCreateValue: canCreate.value,
        funnelNameLength: funnelName.value?.length,
      },
      timestamp: Date.now(),
      sessionId: 'debug-session',
      hypothesisId: 'C',
    }),
  }).catch(() => {});
  // #endregion
  console.log(
    '[DEBUG] CreateFunnelDialog handleCreate called, canCreate:',
    canCreate.value,
    'funnelName:',
    funnelName.value
  );
  if (!canCreate.value) {
    // #region agent log
    fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'CreateFunnelDialog.vue:handleCreate:validationFailed',
        message: 'Cannot create - validation failed',
        data: {
          funnelNameValue: funnelName.value,
          canCreateValue: canCreate.value,
        },
        timestamp: Date.now(),
        sessionId: 'debug-session',
        hypothesisId: 'C',
      }),
    }).catch(() => {});
    // #endregion
    console.log('[DEBUG] Cannot create - validation failed');
    return;
  }

  try {
    const funnelData = {
      name: funnelName.value.trim(),
      team_id: null,
    };
    console.log('[DEBUG] Dispatching funnels/create with:', funnelData);
    const funnel = await store.dispatch('funnels/create', funnelData);
    console.log('[DEBUG] Funnel created:', funnel);
    emit('create', funnel);
    resetForm();
    emit('update:show', false);
  } catch (error) {
    console.error('[DEBUG] Error creating funnel:', error);
    useAlert(t('KANBAN.CREATE_ERROR'));
  }
};

// #region agent log
const handleKeydownEnter = () => {
  fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      location: 'CreateFunnelDialog.vue:keydownEnter',
      message: 'keydown.enter triggered',
      data: {
        funnelNameValue: funnelName.value,
        funnelNameLength: funnelName.value?.length,
        canCreateValue: canCreate.value,
        hasLetters: /[a-zA-Z]/.test(funnelName.value),
        hasNumbers: /[0-9]/.test(funnelName.value),
      },
      timestamp: Date.now(),
      sessionId: 'debug-session',
      hypothesisId: 'A-D',
    }),
  }).catch(() => {});
  console.log(
    '[DEBUG] CreateFunnelDialog keydown.enter - calling handleCreate, funnelName:',
    funnelName.value,
    'canCreate:',
    canCreate.value
  );
  handleCreate();
};

const handleKeyupEnter = () => {
  fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      location: 'CreateFunnelDialog.vue:keyupEnter',
      message: 'keyup.enter triggered',
      data: {
        funnelNameValue: funnelName.value,
        canCreateValue: canCreate.value,
      },
      timestamp: Date.now(),
      sessionId: 'debug-session',
      hypothesisId: 'D',
    }),
  }).catch(() => {});
  console.log(
    '[DEBUG] CreateFunnelDialog keyup.enter, funnelName:',
    funnelName.value
  );
};
// #endregion

const handleClose = () => {
  // #region agent log
  fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      location: 'CreateFunnelDialog.vue:handleClose',
      message: 'handleClose called',
      data: {
        funnelNameValue: funnelName.value,
        canCreateValue: canCreate.value,
        stackTrace: new Error().stack?.split('\n').slice(0, 5),
      },
      timestamp: Date.now(),
      sessionId: 'debug-session',
      hypothesisId: 'A-E',
    }),
  }).catch(() => {});
  // #endregion
  console.log('[DEBUG] CreateFunnelDialog handleClose called');
  resetForm();
  emit('update:show', false);
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('KANBAN.CREATE_FUNNEL_TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <div class="flex flex-col gap-4">
      <div>
        <label class="block mb-2 text-sm font-medium text-n-slate-12">
          <span>{{ t('KANBAN.FUNNEL_NAME_LABEL') }}</span>
        </label>
        <input
          v-model="funnelName"
          type="text"
          :placeholder="t('KANBAN.FUNNEL_NAME_PLACEHOLDER')"
          class="w-full px-3 py-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-weak"
          @keydown.enter.prevent="handleKeydownEnter"
          @keyup.enter="handleKeyupEnter"
          @focus="
            () =>
              console.log(
                '[DEBUG] CreateFunnelDialog input focused, funnelName:',
                funnelName.value
              )
          "
          @blur="
            () =>
              console.log(
                '[DEBUG] CreateFunnelDialog input blurred, funnelName:',
                funnelName.value
              )
          "
          @input="
            () =>
              console.log(
                '[DEBUG] CreateFunnelDialog input changed, funnelName:',
                funnelName.value
              )
          "
        />
      </div>
    </div>
    <template #footer>
      <div class="flex justify-end gap-2">
        <Button
          :label="t('KANBAN.CANCEL')"
          variant="ghost"
          color="slate"
          @click="handleClose"
        />
        <Button
          :label="t('KANBAN.ADD')"
          variant="solid"
          color="teal"
          :is-loading="isLoading"
          :disabled="!canCreate || isLoading"
          @click="handleCreate"
        />
      </div>
    </template>
  </Dialog>
</template>
