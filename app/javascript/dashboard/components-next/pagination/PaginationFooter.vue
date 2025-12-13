<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  currentPage: {
    type: Number,
    required: true,
  },
  totalItems: {
    type: Number,
    required: true,
  },
  itemsPerPage: {
    type: Number,
    default: 16,
  },
});
const emit = defineEmits(['update:currentPage']);
const { t } = useI18n();

const totalPages = computed(() =>
  Math.ceil(props.totalItems / props.itemsPerPage)
);
const isFirstPage = computed(() => props.currentPage === 1);
const isLastPage = computed(() => props.currentPage === totalPages.value);
const changePage = newPage => {
  // Garantir que newPage seja um número
  const pageNumber = Number(newPage);
  if (
    !Number.isNaN(pageNumber) &&
    pageNumber >= 1 &&
    pageNumber <= totalPages.value
  ) {
    emit('update:currentPage', pageNumber);
  }
};

const pageInfo = computed(() => {
  return t('PAGINATION_FOOTER.CURRENT_PAGE_INFO', {
    currentPage: '',
    totalPages: totalPages.value,
  });
});
</script>

<template>
  <div
    class="flex justify-center h-12 w-full max-w-[calc(60rem-3px)] outline outline-n-container outline-1 -outline-offset-1 mx-auto bg-n-solid-2 rounded-xl py-2 ltr:pl-3 rtl:pr-3 ltr:pr-3 rtl:pl-3 items-center before:absolute before:inset-x-0 before:-top-4 before:bg-gradient-to-t before:from-n-background before:from-10% before:dark:from-0% before:to-transparent before:h-4 before:pointer-events-none"
  >
    <div class="flex items-center gap-1">
      <Button
        icon="i-lucide-chevrons-left"
        variant="ghost"
        size="sm"
        color="slate"
        class="!w-6 !h-6"
        :disabled="isFirstPage"
        @click="changePage(1)"
      />
      <Button
        icon="i-lucide-chevron-left"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-6 !h-6"
        :disabled="isFirstPage"
        @click="changePage(Number(currentPage) - 1)"
      />
      <div class="inline-flex items-center gap-1.5 text-xs text-n-slate-11">
        <span class="px-2 tabular-nums py-0.5 bg-n-alpha-black2 rounded-md">
          {{ currentPage }}
        </span>
        <span class="truncate whitespace-nowrap">{{ pageInfo }}</span>
      </div>
      <Button
        icon="i-lucide-chevron-right"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-6 !h-6"
        :disabled="isLastPage"
        @click="changePage(Number(currentPage) + 1)"
      />
      <Button
        icon="i-lucide-chevrons-right"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-6 !h-6"
        :disabled="isLastPage"
        @click="changePage(totalPages)"
      />
    </div>
  </div>
</template>
