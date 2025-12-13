<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
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

const { t } = useI18n();

const dialogRef = ref(null);
const columnName = ref('');

const canCreate = computed(() => {
  return columnName.value.trim().length > 0;
});

const resetForm = () => {
  columnName.value = '';
};

// Watch para controlar abertura/fechamento do dialog
watch(
  () => props.show,
  newValue => {
    // #region agent log
    fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'CreateColumnDialog.vue:36',
        message: 'watch show prop changed',
        data: { newValue, hasDialogRef: !!dialogRef.value },
        timestamp: Date.now(),
        sessionId: 'debug-session',
        runId: 'run1',
        hypothesisId: 'A',
      }),
    }).catch(() => {});
    // #endregion
    // Usar nextTick para garantir que o DOM foi atualizado
    if (newValue) {
      setTimeout(() => {
        // #region agent log
        fetch(
          'http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814',
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              location: 'CreateColumnDialog.vue:42',
              message: 'Opening dialog',
              data: { hasDialogRef: !!dialogRef.value },
              timestamp: Date.now(),
              sessionId: 'debug-session',
              runId: 'run1',
              hypothesisId: 'A',
            }),
          }
        ).catch(() => {});
        // #endregion
        dialogRef.value?.open();
      }, 0);
    } else {
      dialogRef.value?.close();
    }
  },
  { immediate: true }
);

const handleCreate = async () => {
  // #region agent log
  fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      location: 'CreateColumnDialog.vue:51',
      message: 'handleCreate called',
      data: { columnName: columnName.value, canCreate: canCreate.value },
      timestamp: Date.now(),
      sessionId: 'debug-session',
      runId: 'run1',
      hypothesisId: 'A',
    }),
  }).catch(() => {});
  // #endregion
  if (!canCreate.value) return;

  try {
    const columnData = { name: columnName.value.trim() };
    // #region agent log
    fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'CreateColumnDialog.vue:55',
        message: 'Emitting create event',
        data: { columnData },
        timestamp: Date.now(),
        sessionId: 'debug-session',
        runId: 'run1',
        hypothesisId: 'A',
      }),
    }).catch(() => {});
    // #endregion
    emit('create', columnData);
    resetForm();
    emit('update:show', false);
  } catch (error) {
    // #region agent log
    fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'CreateColumnDialog.vue:59',
        message: 'Error in handleCreate',
        data: { error: error?.message || error?.toString() },
        timestamp: Date.now(),
        sessionId: 'debug-session',
        runId: 'run1',
        hypothesisId: 'A',
      }),
    }).catch(() => {});
    // #endregion
    useAlert(t('KANBAN.CREATE_COLUMN_ERROR'));
  }
};

const handleClose = () => {
  resetForm();
  emit('update:show', false);
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('KANBAN.CREATE_COLUMN_TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <div class="flex flex-col gap-4">
      <div>
        <label class="block mb-2 text-sm font-medium text-n-slate-12">
          <span>{{ t('KANBAN.COLUMN_NAME_LABEL') }}</span>
        </label>
        <input
          v-model="columnName"
          type="text"
          :placeholder="t('KANBAN.COLUMN_NAME_PLACEHOLDER')"
          class="w-full px-3 py-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-weak"
          @keyup.enter="handleCreate"
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
          @click="
            () => {
              fetch(
                'http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814',
                {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    location: 'CreateColumnDialog.vue:100',
                    message: 'Button clicked',
                    data: {
                      canCreate: canCreate.value,
                      isLoading: isLoading.value,
                      columnName: columnName.value,
                    },
                    timestamp: Date.now(),
                    sessionId: 'debug-session',
                    runId: 'run1',
                    hypothesisId: 'A',
                  }),
                }
              ).catch(() => {});
              handleCreate();
            }
          "
        />
      </div>
    </template>
  </Dialog>
</template>
