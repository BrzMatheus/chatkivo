<script setup>
/* eslint-disable no-console */
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'edit',
    validator: value => ['alert', 'edit'].includes(value),
  },
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  cancelButtonLabel: {
    type: String,
    default: '',
  },
  confirmButtonLabel: {
    type: String,
    default: '',
  },
  disableConfirmButton: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  showCancelButton: {
    type: Boolean,
    default: true,
  },
  showConfirmButton: {
    type: Boolean,
    default: true,
  },
  overflowYAuto: {
    type: Boolean,
    default: false,
  },
  width: {
    type: String,
    default: 'lg',
    validator: value => ['3xl', '2xl', 'xl', 'lg', 'md', 'sm'].includes(value),
  },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();

const dialogRef = ref(null);
const dialogContentRef = ref(null);
const isOpening = ref(false);
const lastOpenTime = ref(0);

const maxWidthClass = computed(() => {
  const classesMap = {
    '3xl': 'max-w-3xl',
    '2xl': 'max-w-2xl',
    xl: 'max-w-xl',
    lg: 'max-w-lg',
    md: 'max-w-md',
    sm: 'max-w-sm',
  };

  return classesMap[props.width] ?? 'max-w-md';
});

const open = () => {
  console.log('[DEBUG] Dialog.open() called, dialogRef:', !!dialogRef.value);
  if (dialogRef.value) {
    // Verificar se o dialog já está aberto
    const isOpen = dialogRef.value.open;
    console.log('[DEBUG] Dialog isOpen before showModal:', isOpen);
    if (!isOpen) {
      isOpening.value = true;
      // Usar requestAnimationFrame para garantir que o DOM está pronto
      requestAnimationFrame(() => {
        if (dialogRef.value && !dialogRef.value.open) {
          dialogRef.value.showModal();
          console.log('[DEBUG] Dialog.showModal() called');
          // Verificar se realmente abriu
          requestAnimationFrame(() => {
            console.log(
              '[DEBUG] Dialog isOpen after showModal:',
              dialogRef.value?.open
            );
            // Resetar a flag após um delay maior para permitir que o dialog abra completamente
            setTimeout(() => {
              isOpening.value = false;
              lastOpenTime.value = Date.now();
              console.log(
                '[DEBUG] Dialog isOpening flag reset, dialog isOpen:',
                dialogRef.value?.open,
                'lastOpenTime:',
                lastOpenTime.value
              );
            }, 200);
          });
        }
      });
    } else {
      console.log('[DEBUG] Dialog already open, skipping showModal');
    }
  }
};

const close = () => {
  console.log(
    '[DEBUG] Dialog.close() called, isOpening:',
    isOpening.value,
    'dialogRef:',
    !!dialogRef.value
  );
  // Prevenir fechamento imediato após abrir
  if (isOpening.value) {
    console.log('[DEBUG] Dialog.close() prevented - dialog is still opening');
    return;
  }
  if (dialogRef.value && dialogRef.value.open) {
    emit('close');
    dialogRef.value.close();
  } else {
    console.log('[DEBUG] Dialog.close() called but dialog is not open');
  }
};

const handleDialogCancel = event => {
  const timeSinceOpen = Date.now() - lastOpenTime.value;
  console.log(
    '[DEBUG] Dialog.handleDialogCancel() called from @cancel event, isOpening:',
    isOpening.value,
    'timeSinceOpen:',
    timeSinceOpen,
    'event:',
    event
  );
  // Prevenir cancelamento durante abertura ou logo após abrir
  if (isOpening.value || timeSinceOpen < 1000) {
    console.log(
      '[DEBUG] Dialog.handleDialogCancel() prevented - dialog is still opening or just opened (timeSinceOpen:',
      timeSinceOpen,
      'ms)'
    );
    event.preventDefault();
    event.stopPropagation();
    // Reabrir o dialog se ele foi fechado
    if (dialogRef.value && !dialogRef.value.open) {
      console.log('[DEBUG] Reopening dialog that was cancelled during opening');
      setTimeout(() => {
        if (dialogRef.value && !dialogRef.value.open) {
          dialogRef.value.showModal();
        }
      }, 10);
    }
  }
};

const handleDialogClose = event => {
  const timeSinceOpen = Date.now() - lastOpenTime.value;
  console.log(
    '[DEBUG] Dialog.handleDialogClose() called from @close event, isOpening:',
    isOpening.value,
    'dialogRef:',
    !!dialogRef.value,
    'event:',
    event,
    'dialogOpen:',
    dialogRef.value?.open,
    'timeSinceOpen:',
    timeSinceOpen,
    'event.type:',
    event?.type,
    'event.target:',
    event?.target?.tagName
  );
  // Prevenir fechamento imediato após abrir (dentro de 1000ms para dar mais tempo)
  if (isOpening.value || timeSinceOpen < 1000) {
    console.log(
      '[DEBUG] Dialog.handleDialogClose() prevented - dialog is still opening or just opened (timeSinceOpen:',
      timeSinceOpen,
      'ms)'
    );
    // Prevenir o fechamento padrão do dialog
    if (event && event.preventDefault) {
      event.preventDefault();
    }
    // Reabrir o dialog se ele foi fechado durante a abertura
    if (dialogRef.value && !dialogRef.value.open) {
      console.log('[DEBUG] Reopening dialog that was closed during opening');
      setTimeout(() => {
        if (dialogRef.value && !dialogRef.value.open) {
          dialogRef.value.showModal();
        }
      }, 10);
    }
    return;
  }
  // Verificar se o dialog está realmente aberto antes de fechar
  // Isso previne fechamentos acidentais quando o dialog já está fechado
  if (dialogRef.value && !dialogRef.value.open) {
    console.log(
      '[DEBUG] Dialog.handleDialogClose() prevented - dialog is already closed'
    );
    return;
  }
  close();
};

const confirm = () => {
  emit('confirm');
};

defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogRef"
      class="w-full transition-all duration-300 ease-in-out shadow-xl rounded-xl"
      :class="[
        maxWidthClass,
        overflowYAuto ? 'overflow-y-auto' : 'overflow-visible',
      ]"
      @close="handleDialogClose"
      @cancel="handleDialogCancel"
      @click="
        e => {
          console.log(
            '[DEBUG] Dialog @click event, target:',
            e.target.tagName,
            'currentTarget:',
            e.currentTarget.tagName,
            'dialogOpen:',
            dialogRef.value?.open
          );
        }
      "
    >
      <form
        ref="dialogContentRef"
        class="flex flex-col w-full h-auto gap-6 p-6 overflow-visible text-left align-middle transition-all duration-300 ease-in-out transform bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl"
        @submit.prevent="confirm"
        @click.stop
        @keydown="
          e => {
            console.log(
              '[DEBUG] Dialog form keydown, key:',
              e.key,
              'code:',
              e.code,
              'target:',
              e.target.tagName,
              'target.type:',
              e.target.type
            );
          }
        "
        @keyup="
          e => {
            console.log(
              '[DEBUG] Dialog form keyup, key:',
              e.key,
              'code:',
              e.code,
              'target:',
              e.target.tagName
            );
          }
        "
      >
        <div v-if="title || description" class="flex flex-col gap-2">
          <h3 class="text-base font-medium leading-6 text-n-slate-12">
            {{ title }}
          </h3>
          <slot name="description">
            <p v-if="description" class="mb-0 text-sm text-n-slate-11">
              {{ description }}
            </p>
          </slot>
        </div>
        <slot />
        <!-- Dialog content will be injected here -->
        <slot name="footer">
          <div
            v-if="showCancelButton || showConfirmButton"
            class="flex items-center justify-between w-full gap-3"
          >
            <Button
              v-if="showCancelButton"
              variant="faded"
              color="slate"
              :label="cancelButtonLabel || t('DIALOG.BUTTONS.CANCEL')"
              class="w-full"
              type="button"
              @click="close"
            />
            <Button
              v-if="showConfirmButton"
              :color="type === 'edit' ? 'blue' : 'ruby'"
              :label="confirmButtonLabel || t('DIALOG.BUTTONS.CONFIRM')"
              class="w-full"
              :is-loading="isLoading"
              :disabled="disableConfirmButton || isLoading"
              type="submit"
            />
          </div>
        </slot>
      </form>
    </dialog>
  </TeleportWithDirection>
</template>

<style scoped>
dialog::backdrop {
  @apply bg-n-alpha-black1 backdrop-blur-[4px];
}
</style>
