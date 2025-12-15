<script setup>
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
    if (newValue === oldValue) {
      return;
    }
    if (newValue) {
      await nextTick();
      if (dialogRef.value) {
        dialogRef.value.open();
      }
    } else if (dialogRef.value) {
      dialogRef.value.close();
    }
  }
);

const handleCreate = async () => {
  if (!canCreate.value) {
    return;
  }

  try {
    const funnelData = {
      name: funnelName.value.trim(),
      team_id: null,
    };
    const funnel = await store.dispatch('funnels/create', funnelData);
    emit('create', funnel);
    resetForm();
    emit('update:show', false);
  } catch (error) {
    useAlert(t('KANBAN.CREATE_ERROR'));
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
          @keydown.enter.prevent="handleCreate"
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
