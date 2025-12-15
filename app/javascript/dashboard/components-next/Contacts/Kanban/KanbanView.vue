<script setup>
/* eslint-disable no-alert, no-restricted-globals */
import { onMounted, onUnmounted, computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';

import KanbanColumn from './KanbanColumn.vue';
import CreateFunnelDialog from './CreateFunnelDialog.vue';
import CreateColumnDialog from './CreateColumnDialog.vue';
import ContactsSidebar from './ContactsSidebar.vue';
import KanbanFilter from './KanbanFilter.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const store = useStore();
const { t } = useI18n();

const funnels = useMapGetter('funnels/getFunnels');
const uiFlags = useMapGetter('funnels/getUIFlags');
const defaultFunnel = useMapGetter('funnels/getDefaultFunnel');
const teams = useMapGetter('teams/getTeams');
const meta = useMapGetter('contacts/getMeta');

const selectedFunnelId = ref(null);
const showCreateDialog = ref(false);
const showCreateColumnDialog = ref(false);
const showCreateDropdown = ref(false);
const showFilterDialog = ref(false);
const searchQuery = ref('');
const error = ref(null);
const sidebarWidth = ref(290);
const draggedColumnIndex = ref(null);
const draggedOverColumnIndex = ref(null);
const dragLeaveTimeout = ref(null);
const columnsOrder = ref([]);
const appliedFilters = ref([]);
const currentPage = ref(1);
const isPageLoading = ref(false);

// Sidebar resize functionality
const MIN_SIDEBAR_WIDTH = 200;
const MAX_SIDEBAR_WIDTH = 500;
const isResizingSidebar = ref(false);
const resizeStartX = ref(0);
const resizeStartWidth = ref(290);

const handleSidebarResize = event => {
  if (!isResizingSidebar.value) return;

  const deltaX = event.clientX - resizeStartX.value;
  const newWidth = resizeStartWidth.value + deltaX;

  const clampedWidth = Math.max(
    MIN_SIDEBAR_WIDTH,
    Math.min(MAX_SIDEBAR_WIDTH, newWidth)
  );
  sidebarWidth.value = clampedWidth;
};

const stopSidebarResize = () => {
  isResizingSidebar.value = false;
  document.removeEventListener('mousemove', handleSidebarResize);
  document.removeEventListener('mouseup', stopSidebarResize);
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
};

const startSidebarResize = event => {
  isResizingSidebar.value = true;
  resizeStartX.value = event.clientX;
  resizeStartWidth.value = sidebarWidth.value;

  document.addEventListener('mousemove', handleSidebarResize);
  document.addEventListener('mouseup', stopSidebarResize);
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';

  event.preventDefault();
};

const currentFunnel = computed(() => {
  if (!funnels.value || funnels.value.length === 0) return null;
  if (selectedFunnelId.value) {
    return funnels.value.find(f => f.id === selectedFunnelId.value);
  }
  return defaultFunnel.value || funnels.value[0] || null;
});

const sortedColumns = computed(() => {
  const funnel = currentFunnel.value;
  if (!funnel || !Array.isArray(funnel.columns)) return [];

  if (!columnsOrder.value.length) {
    return funnel.columns;
  }

  const byId = funnel.columns.reduce((acc, col) => {
    acc[col.id] = col;
    return acc;
  }, {});

  return columnsOrder.value.map(id => byId[id]).filter(Boolean);
});

const isFetching = computed(() => uiFlags.value.isFetching);
const isCreating = computed(() => uiFlags.value.isCreating);
const isUpdating = computed(() => uiFlags.value.isUpdating);

async function reloadFunnels(preserveSelection = false) {
  try {
    error.value = null;
    const previousFunnelId = preserveSelection ? selectedFunnelId.value : null;

    await store.dispatch('funnels/get');
    await store.dispatch('teams/get');

    await new Promise(resolve => {
      setTimeout(resolve, 100);
    });

    if (preserveSelection && previousFunnelId) {
      const preservedFunnel = funnels.value?.find(
        f => f.id === previousFunnelId
      );
      if (preservedFunnel) {
        selectedFunnelId.value = previousFunnelId;
        columnsOrder.value = (preservedFunnel.columns || []).map(col => col.id);
        await store.dispatch('funnels/getContacts', {
          funnelId: previousFunnelId,
        });
        return;
      }
    }

    const funnel =
      defaultFunnel.value || (funnels.value && funnels.value[0]) || null;
    if (funnel) {
      selectedFunnelId.value = funnel.id;
      columnsOrder.value = (funnel.columns || []).map(col => col.id);
      await store.dispatch('funnels/getContacts', {
        funnelId: funnel.id,
      });
    }
  } catch (err) {
    error.value =
      err?.message || err?.toString() || t('KANBAN.ERROR.LOAD_FUNNELS');
  }
}

const handleCreateFunnel = () => {
  showCreateDialog.value = true;
  showCreateDropdown.value = false;
};

const handleCreateColumn = () => {
  if (!currentFunnel.value) {
    useAlert(t('KANBAN.CREATE_COLUMN.NO_FUNNEL_SELECTED'));
    showCreateDropdown.value = false;
    return;
  }
  showCreateColumnDialog.value = true;
  showCreateDropdown.value = false;
};

const handleColumnCreated = async columnData => {
  if (!currentFunnel.value || !columnData?.name) {
    useAlert(t('KANBAN.CREATE_COLUMN_ERROR'));
    return;
  }

  try {
    const funnel = currentFunnel.value;
    const existingColumns = funnel.columns || [];

    const newColumnId = `col_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const maxPosition =
      existingColumns.length > 0
        ? Math.max(...existingColumns.map(col => col.position || 0))
        : -1;

    const newColumn = {
      id: newColumnId,
      name: columnData.name.trim(),
      position: maxPosition + 1,
    };

    const updatedColumns = [...existingColumns, newColumn];

    await store.dispatch('funnels/update', {
      id: funnel.id,
      columns: updatedColumns,
    });

    await reloadFunnels(true);

    const updatedFunnel = currentFunnel.value;
    if (updatedFunnel && updatedFunnel.columns) {
      columnsOrder.value = updatedFunnel.columns.map(col => col.id);
    }
  } catch (err) {
    const errorMessage =
      err?.response?.data?.error ||
      err?.message ||
      t('KANBAN.CREATE_COLUMN_ERROR');
    useAlert(errorMessage);
  }
};

const createMenuItems = computed(() => [
  {
    action: 'create_funnel',
    value: 'create_funnel',
    label: t('KANBAN.CREATE_NEW_FUNNEL'),
    icon: 'i-lucide-plus',
  },
  {
    action: 'create_column',
    value: 'create_column',
    label: t('KANBAN.CREATE_NEW_COLUMN'),
    icon: 'i-lucide-layout-grid',
  },
]);

const handleCreateAction = ({ action }) => {
  if (action === 'create_funnel') {
    handleCreateFunnel();
  } else if (action === 'create_column') {
    handleCreateColumn();
  }
};

const loadContacts = async (page = 1) => {
  try {
    currentPage.value = page;
    await store.dispatch('contacts/get', { page });
  } catch {
    // Error is handled by the store
  }
};

const handleFunnelSelect = async () => {
  const funnel = currentFunnel.value;
  if (!funnel) return;
  try {
    selectedFunnelId.value = funnel.id;
    columnsOrder.value = (funnel.columns || []).map(col => col.id);
    await store.dispatch('funnels/getContacts', { funnelId: funnel.id });
  } catch {
    // Erro silencioso - a UI já mostra feedback através do store
  }
};

const handleDeleteFunnel = async () => {
  const funnel = currentFunnel.value;
  if (!funnel) return;

  if (!window.confirm(t('KANBAN.DELETE_FUNNEL_CONFIRM'))) {
    return;
  }

  try {
    await store.dispatch('funnels/delete', funnel.id);
    useAlert(t('KANBAN.DELETE_FUNNEL_RESULT.SUCCESS'));
    await reloadFunnels(false);
  } catch (deleteError) {
    useAlert(t('KANBAN.DELETE_FUNNEL_RESULT.ERROR'));
  }
};

const handleColumnDeleted = async () => {
  await reloadFunnels(true);
};

const handleAddContact = async ({ contactId, funnelId }) => {
  try {
    const funnel = currentFunnel.value;
    if (!funnel || !funnel.columns || funnel.columns.length === 0) {
      useAlert(t('KANBAN.ADD_CONTACT.NO_COLUMNS'));
      return;
    }

    const firstColumnId = funnel.columns[0].id;
    await store.dispatch('funnels/addContact', {
      funnelId,
      contactId,
      columnId: firstColumnId,
    });
    useAlert(t('KANBAN.ADD_CONTACT.SUCCESS'));
  } catch {
    useAlert(t('KANBAN.ADD_CONTACT.ERROR'));
  }
};

const handleFilter = () => {
  showFilterDialog.value = !showFilterDialog.value;
};

const handleApplyFilter = async filters => {
  const validFilters = filters.filter(f => {
    const hasValue =
      f.values !== null &&
      f.values !== undefined &&
      f.values !== '' &&
      (!Array.isArray(f.values) || f.values.length > 0);
    return (
      hasValue || ['is_present', 'is_not_present'].includes(f.filterOperator)
    );
  });

  currentPage.value = 1;

  if (validFilters.length > 0) {
    try {
      const filtersForQuery = validFilters.map(f => {
        let processedValues = f.values;

        if (f.attributeKey === 'team_id') {
          if (
            typeof f.values === 'object' &&
            f.values !== null &&
            !Array.isArray(f.values)
          ) {
            processedValues = [f.values.id || f.values];
          } else if (Array.isArray(f.values)) {
            processedValues = f.values.map(v =>
              typeof v === 'object' && v !== null ? v.id || v : v
            );
          } else {
            processedValues = [f.values];
          }
        }

        return {
          attribute_key: f.attributeKey,
          filter_operator: f.filterOperator,
          values: processedValues,
          query_operator: f.queryOperator || 'and',
        };
      });

      const queryPayload = filterQueryGenerator(filtersForQuery);

      await store.dispatch('contacts/filter', {
        page: 1,
        queryPayload,
      });
    } catch {
      useAlert(t('KANBAN.FILTER.ERROR'));
    }
  } else {
    await loadContacts(1);
  }

  appliedFilters.value = filters;
  showFilterDialog.value = false;
};

const handleClearFilters = async () => {
  store.dispatch('contacts/clearContactFilters');
  appliedFilters.value = [];
  showFilterDialog.value = false;
  currentPage.value = 1;
  await loadContacts(1);
};

watch(
  () => showFilterDialog.value,
  newValue => {
    if (!newValue && appliedFilters.value.length > 0) {
      const hasValidFilters = appliedFilters.value.some(f => {
        const hasValue =
          f.values !== null &&
          f.values !== undefined &&
          f.values !== '' &&
          (!Array.isArray(f.values) || f.values.length > 0);
        return (
          hasValue ||
          ['is_present', 'is_not_present'].includes(f.filterOperator)
        );
      });

      if (!hasValidFilters) {
        appliedFilters.value = [];
        store.dispatch('contacts/clearContactFilters');
      }
    }
  }
);

const handleFunnelCreated = async funnel => {
  try {
    selectedFunnelId.value = funnel.id;
    await store.dispatch('funnels/getContacts', { funnelId: funnel.id });
    showCreateDialog.value = false;
  } catch (err) {
    error.value = err.message || t('KANBAN.ERROR.LOAD_CONTACTS');
    showCreateDialog.value = false;
  }
};

const handleContactMoved = async () => {
  if (currentFunnel.value) {
    await store.dispatch('funnels/getContacts', {
      funnelId: currentFunnel.value.id,
    });
  }
};

const handleAddContactFromSidebar = async ({ contactId, columnId }) => {
  try {
    const funnel = currentFunnel.value;
    if (!funnel) return;

    await store.dispatch('funnels/addContact', {
      funnelId: funnel.id,
      contactId,
      columnId,
    });
    useAlert(t('KANBAN.ADD_CONTACT.SUCCESS'));
  } catch {
    useAlert(t('KANBAN.ADD_CONTACT.ERROR'));
  }
};

const handleColumnDragStart = (e, index) => {
  draggedColumnIndex.value = index;
  e.dataTransfer.effectAllowed = 'move';
};

const handleColumnDragOver = (e, columnIndex) => {
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';

  if (dragLeaveTimeout.value) {
    clearTimeout(dragLeaveTimeout.value);
    dragLeaveTimeout.value = null;
  }

  if (
    draggedColumnIndex.value !== null &&
    draggedColumnIndex.value !== columnIndex
  ) {
    draggedOverColumnIndex.value = columnIndex;
  }
};

const handleColumnDragLeave = e => {
  const relatedTarget = e.relatedTarget;
  if (relatedTarget && e.currentTarget.contains(relatedTarget)) {
    return;
  }

  dragLeaveTimeout.value = setTimeout(() => {
    draggedOverColumnIndex.value = null;
    dragLeaveTimeout.value = null;
  }, 50);
};

const handleColumnDrop = (e, dropIndex) => {
  e.preventDefault();

  if (dragLeaveTimeout.value) {
    clearTimeout(dragLeaveTimeout.value);
    dragLeaveTimeout.value = null;
  }

  const fromIndex = draggedColumnIndex.value;
  draggedColumnIndex.value = null;
  draggedOverColumnIndex.value = null;

  if (fromIndex === null || fromIndex === dropIndex || !currentFunnel.value) {
    return;
  }

  const currentOrder =
    columnsOrder.value && columnsOrder.value.length
      ? [...columnsOrder.value]
      : (currentFunnel.value.columns || []).map(col => col.id);

  if (!currentOrder.length) return;

  const [movedId] = currentOrder.splice(fromIndex, 1);
  currentOrder.splice(dropIndex, 0, movedId);

  columnsOrder.value = currentOrder;
};

const handleClickOutside = event => {
  if (showCreateDropdown.value) {
    const target = event.target;
    const button = target.closest(
      '.create-dropdown-button, .create-dropdown-button *'
    );
    const dropdown = target.closest(
      '[class*="dropdown-menu"], [class*="DropdownMenu"]'
    );

    if (!button && !dropdown) {
      showCreateDropdown.value = false;
    }
  }
};

const loadContactsWithSearchOrFilter = async (page = 1) => {
  currentPage.value = page;

  const validFilters = appliedFilters.value.filter(f => {
    const hasValue =
      f.values !== null &&
      f.values !== undefined &&
      f.values !== '' &&
      (!Array.isArray(f.values) || f.values.length > 0);
    return (
      hasValue || ['is_present', 'is_not_present'].includes(f.filterOperator)
    );
  });

  if (validFilters.length > 0) {
    const filtersForQuery = validFilters.map(f => {
      let processedValues = f.values;

      if (f.attributeKey === 'team_id') {
        if (
          typeof f.values === 'object' &&
          f.values !== null &&
          !Array.isArray(f.values)
        ) {
          processedValues = [f.values.id || f.values];
        } else if (Array.isArray(f.values)) {
          processedValues = f.values.map(v =>
            typeof v === 'object' && v !== null ? v.id || v : v
          );
        } else {
          processedValues = [f.values];
        }
      }

      return {
        attribute_key: f.attributeKey,
        filter_operator: f.filterOperator,
        values: processedValues,
        query_operator: f.queryOperator || 'and',
      };
    });

    const queryPayload = filterQueryGenerator(filtersForQuery);
    await store.dispatch('contacts/filter', {
      page,
      queryPayload,
    });
  } else if (searchQuery.value) {
    await store.dispatch('contacts/search', {
      search: encodeURIComponent(searchQuery.value),
      page,
      sortAttr: 'name',
    });
  } else {
    await loadContacts(page);
  }
};

const searchContactsDebounced = debounce(async (query, page = 1) => {
  currentPage.value = page;

  if (!query || query.trim() === '') {
    await loadContactsWithSearchOrFilter(1);
    return;
  }

  await store.dispatch('contacts/search', {
    search: encodeURIComponent(query.trim()),
    page,
    sortAttr: 'name',
  });
}, 300);

watch(searchQuery, async (newQuery, oldQuery) => {
  if (oldQuery !== undefined && newQuery !== oldQuery) {
    currentPage.value = 1;
    await searchContactsDebounced(newQuery, 1);
  }
});

const handleLoadPage = async page => {
  if (isPageLoading.value || uiFlags.value.isFetching) {
    return;
  }

  const currentMetaPage = meta.value?.currentPage || 1;

  if (page === currentMetaPage && !isPageLoading.value) {
    return;
  }

  isPageLoading.value = true;
  try {
    currentPage.value = page;
    await loadContactsWithSearchOrFilter(page);
  } catch {
    // Error is handled by the store
  } finally {
    setTimeout(() => {
      isPageLoading.value = false;
    }, 300);
  }
};

onMounted(() => {
  try {
    loadContacts(1);
    reloadFunnels();
    document.addEventListener('click', handleClickOutside);
  } catch (err) {
    error.value = t('KANBAN.ERROR.FATAL');
  }
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
  if (dragLeaveTimeout.value) {
    clearTimeout(dragLeaveTimeout.value);
  }
});
</script>

<template>
  <div class="flex h-full bg-n-background">
    <!-- Sidebar de Contatos -->
    <div
      class="relative flex-shrink-0 border-r border-n-strong"
      :style="{ width: `${sidebarWidth}px` }"
    >
      <ContactsSidebar
        :search-query="searchQuery"
        :funnel-id="currentFunnel?.id"
        :applied-filters="appliedFilters"
        @add-contact="handleAddContact"
        @load-page="handleLoadPage"
      />
      <!-- Resize handle -->
      <div
        class="absolute top-0 bottom-0 right-0 w-1 cursor-col-resize hover:bg-n-strong/50 transition-colors z-50 group"
        @mousedown="startSidebarResize"
      >
        <div class="absolute inset-y-0 -right-1 w-3" />
      </div>
    </div>

    <!-- Área Principal do Kanban -->
    <div class="flex flex-col flex-1 min-w-0">
      <div
        v-if="error"
        class="p-4 m-4 bg-red-100 border border-red-400 rounded text-red-700"
      >
        <p class="font-semibold">{{ t('KANBAN.ERROR.TITLE') }}</p>
        <p class="text-sm mt-1">{{ error }}</p>
        <button
          class="mt-2 px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
          @click="reloadFunnels"
        >
          {{ t('KANBAN.ERROR.RETRY') }}
        </button>
      </div>
      <template v-else>
        <div
          class="flex items-center justify-between px-6 h-[5rem] border-b border-n-strong gap-4"
        >
          <div class="flex items-center gap-4 flex-shrink-0">
            <div
              v-if="funnels && funnels.length > 0"
              class="flex items-center gap-2"
            >
              <div class="relative w-[140px] flex-shrink-0 h-10">
                <select
                  v-model="selectedFunnelId"
                  class="funnel-select w-full h-full px-3 pr-8 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-weak"
                  @change="handleFunnelSelect"
                >
                  <option
                    v-for="funnel in funnels"
                    :key="funnel.id"
                    :value="funnel.id"
                  >
                    {{ funnel.name }}
                  </option>
                </select>
                <Icon
                  icon="i-lucide-chevron-down"
                  class="absolute right-2 top-1/2 -translate-y-1/2 size-4 text-n-slate-10 pointer-events-none"
                />
              </div>
              <Button
                v-if="currentFunnel && funnels.length > 1"
                icon="i-lucide-trash"
                variant="ghost"
                color="ruby"
                size="sm"
                :title="t('KANBAN.DELETE_FUNNEL')"
                class="flex-shrink-0"
                @click="handleDeleteFunnel"
              />
            </div>
            <div class="relative flex items-center group">
              <Button
                icon="i-lucide-plus"
                variant="solid"
                color="teal"
                size="sm"
                :label="t('KANBAN.CREATE_FUNNEL')"
                class="flex-shrink-0 whitespace-nowrap create-dropdown-button"
                @click.stop="showCreateDropdown = !showCreateDropdown"
              />
              <DropdownMenu
                v-if="showCreateDropdown"
                :menu-items="createMenuItems"
                class="mt-1 ltr:left-0 rtl:right-0 top-full z-50"
                @action="handleCreateAction"
              />
            </div>
          </div>
          <div class="flex items-center gap-2 flex-shrink-0">
            <div class="relative w-[240px] h-10">
              <input
                v-model="searchQuery"
                type="text"
                :placeholder="t('KANBAN.SEARCH_PLACEHOLDER')"
                class="w-full h-full px-4 pr-10 text-sm border border-n-weak rounded-lg bg-n-background text-n-slate-12 focus:outline-none focus:border-n-strong focus:ring-1 focus:ring-n-weak"
                @input="searchContactsDebounced(searchQuery, 1)"
              />
              <Icon
                icon="i-lucide-search"
                class="absolute right-3 top-1/2 -translate-y-1/2 size-4 text-n-slate-10 pointer-events-none"
              />
            </div>
            <div class="relative flex-shrink-0">
              <Button
                id="toggleKanbanFilterButton"
                icon="i-lucide-filter"
                variant="ghost"
                color="slate"
                size="sm"
                :label="t('KANBAN.FILTER')"
                class="whitespace-nowrap"
                :class="{ 'bg-n-slate-3': showFilterDialog }"
                @click="handleFilter"
              />
              <div
                v-if="showFilterDialog"
                id="kanbanFilterTeleportTarget"
                class="absolute z-50 mt-2 ltr:right-0 rtl:left-0"
              />
              <TeleportWithDirection
                v-if="showFilterDialog"
                to="#kanbanFilterTeleportTarget"
              >
                <KanbanFilter
                  v-model="appliedFilters"
                  @apply-filter="handleApplyFilter"
                  @clear-filters="handleClearFilters"
                  @close="showFilterDialog = false"
                />
              </TeleportWithDirection>
            </div>
          </div>
        </div>

        <div v-if="isFetching" class="flex items-center justify-center flex-1">
          <Spinner />
        </div>

        <template v-else>
          <div
            v-if="
              currentFunnel &&
              currentFunnel.columns &&
              Array.isArray(currentFunnel.columns)
            "
            class="flex-1 overflow-x-auto"
          >
            <div class="flex gap-4 px-6 py-4 min-w-max">
              <div
                v-for="(column, columnIndex) in sortedColumns"
                :key="column.id || column"
                class="kanban-column-wrapper transition-all duration-200"
                :class="{
                  'opacity-50 scale-95': draggedColumnIndex === columnIndex,
                  'ring-4 ring-n-teal-9 ring-opacity-60 shadow-lg scale-105':
                    draggedOverColumnIndex === columnIndex &&
                    draggedColumnIndex !== columnIndex,
                  'ring-2 ring-n-teal-7 ring-opacity-40':
                    draggedOverColumnIndex === columnIndex &&
                    draggedColumnIndex === columnIndex,
                }"
                @dragover.prevent="handleColumnDragOver($event, columnIndex)"
                @dragleave="handleColumnDragLeave"
                @drop.prevent="handleColumnDrop($event, columnIndex)"
              >
                <KanbanColumn
                  :funnel-id="currentFunnel.id"
                  :column="column"
                  :column-index="columnIndex"
                  :search-query="searchQuery"
                  :applied-filters="appliedFilters"
                  :is-dragging="draggedColumnIndex === columnIndex"
                  @contact-moved="handleContactMoved"
                  @add-contact-from-sidebar="handleAddContactFromSidebar"
                  @column-drag-start="handleColumnDragStart"
                  @column-deleted="handleColumnDeleted"
                />
              </div>
            </div>
          </div>

          <div
            v-else
            class="flex flex-col items-center justify-center flex-1 gap-4 text-n-slate-11"
          >
            <Icon icon="i-lucide-layout-kanban" class="size-12" />
            <p>{{ t('KANBAN.NO_FUNNELS') }}</p>
            <Button
              :label="t('KANBAN.CREATE_FIRST_FUNNEL')"
              variant="solid"
              color="teal"
              @click="handleCreateFunnel"
            />
          </div>
        </template>
      </template>

      <CreateFunnelDialog
        v-model:show="showCreateDialog"
        :teams="teams"
        :is-loading="isCreating"
        @create="handleFunnelCreated"
      />
      <CreateColumnDialog
        v-model:show="showCreateColumnDialog"
        :is-loading="isUpdating"
        :funnel="currentFunnel"
        @create="handleColumnCreated"
      />
    </div>
  </div>
</template>

<style scoped>
.funnel-select {
  appearance: none !important;
  -webkit-appearance: none !important;
  -moz-appearance: none !important;
  background-image: none !important;
}

.funnel-select::-ms-expand {
  display: none !important;
}
</style>
