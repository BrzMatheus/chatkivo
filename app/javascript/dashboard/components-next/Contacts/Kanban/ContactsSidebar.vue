<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRouter, useRoute } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

const props = defineProps({
  funnelId: {
    type: Number,
    default: null,
  },
  appliedFilters: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['addContact', 'loadPage']);

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const contacts = useMapGetter('contacts/getContactsList');
const uiFlags = useMapGetter('contacts/getUIFlags');
const meta = useMapGetter('contacts/getMeta');
const getFunnelContacts = useMapGetter('funnels/getFunnelContacts');

// Paginação server-side
const currentPage = computed(() => meta.value?.currentPage || 1);
const totalItems = computed(() => meta.value?.count || 0);
const itemsPerPage = 15; // RESULTS_PER_PAGE do backend

// Watch para garantir que labels sejam carregados quando há filtros de labels
const labelsLoading = ref(false);
watch(
  () => [props.appliedFilters, contacts.value],
  async ([filters, contactsList]) => {
    if (!filters || !contactsList || labelsLoading.value) return;

    // Verificar se há filtro de labels
    const hasLabelFilter = filters.some(
      f =>
        f.attributeKey === 'labels' &&
        f.values &&
        (Array.isArray(f.values) ? f.values.length > 0 : f.values !== '')
    );

    if (hasLabelFilter && contactsList && contactsList.length > 0) {
      labelsLoading.value = true;
      const contactIds = contactsList.map(c => c.id).filter(Boolean);
      if (contactIds.length > 0) {
        // Buscar labels para todos os contatos em paralelo
        await Promise.all(
          contactIds.map(contactId => {
            return store.dispatch('contactLabels/get', contactId).catch(() => {
              // Ignorar erros silenciosamente
            });
          })
        );
      }
      labelsLoading.value = false;
    }
  },
  { immediate: true, deep: true }
);

// Filtrar apenas contatos que não estão no funil (filtro local)
const filteredContacts = computed(() => {
  if (!contacts.value || !Array.isArray(contacts.value)) {
    return [];
  }

  const funnelContactsList = props.funnelId
    ? getFunnelContacts.value(props.funnelId) || []
    : [];
  const funnelContactIds = funnelContactsList.map(fc => fc.contact_id);

  // A API já faz a busca e filtros, só precisamos remover os que estão no funil
  return contacts.value.filter(
    contact => !funnelContactIds.includes(contact.id)
  );
});

const handleContactClick = contact => {
  router.push(
    frontendURL(`accounts/${route.params.accountId}/contacts/${contact.id}`)
  );
};

const handleAddToFunnel = (contact, event) => {
  event.stopPropagation();
  if (props.funnelId) {
    emit('addContact', { contactId: contact.id, funnelId: props.funnelId });
  }
};

const handleDragStart = (e, contact) => {
  e.dataTransfer.effectAllowed = 'move';

  const dragData = {
    contactId: contact.id,
    fromSidebar: true,
  };

  e.dataTransfer.setData('application/json', JSON.stringify(dragData));
  e.dataTransfer.setData('text/plain', contact.id.toString());
};

const handleContactDrag = (e, contact) => {
  e.stopPropagation();
  handleDragStart(e, contact);
};

const handleDrop = async e => {
  e.preventDefault();

  let dragData = null;
  try {
    const jsonData = e.dataTransfer.getData('application/json');
    if (jsonData) {
      dragData = JSON.parse(jsonData);
    } else {
      return;
    }
  } catch (error) {
    // Se não conseguir parsear, não faz nada
    return;
  }

  const { contactId, fromSidebar, sourceFunnelId } = dragData;

  // Só trata drops vindos do Kanban, não da própria sidebar
  if (!contactId || fromSidebar) return;

  try {
    if (props.funnelId && sourceFunnelId === props.funnelId) {
      await store.dispatch('funnels/removeContact', {
        funnelId: props.funnelId,
        contactId,
      });
    }
    // Assim que remover do funil, o contato volta a aparecer na lista
  } catch (error) {
    // Silencia erro aqui; o usuário ainda pode remover pelo menu do card
    // e não queremos quebrar o drag-and-drop
  }
};

// Handler para mudança de página
const handlePageChange = page => {
  emit('loadPage', page);
};
</script>

<template>
  <div
    class="flex flex-col h-full bg-n-slate-1 border-r border-n-strong"
    @dragover.prevent
    @drop="handleDrop"
  >
    <div class="flex items-center px-4 h-[5rem] border-b border-n-strong">
      <div class="flex flex-col justify-center">
        <h3 class="text-sm font-semibold text-n-slate-12 leading-tight">
          {{ t('KANBAN.CONTACTS_SIDEBAR.TITLE') }}
        </h3>
        <p class="text-xs text-n-slate-10 mt-0.5 leading-tight">
          {{ t('KANBAN.CONTACTS_SIDEBAR.SUBTITLE') }}
        </p>
      </div>
    </div>
    <div class="flex-1 overflow-y-auto">
      <div
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center py-8"
      >
        <Icon
          icon="i-lucide-loader-2"
          class="size-5 animate-spin text-n-slate-10"
        />
      </div>
      <div
        v-else-if="filteredContacts.length === 0"
        class="flex flex-col items-center justify-center py-8 px-4 text-center"
      >
        <Icon icon="i-lucide-users" class="size-8 text-n-slate-10 mb-2" />
        <p class="text-sm text-n-slate-11">
          {{ t('KANBAN.CONTACTS_SIDEBAR.NO_CONTACTS') }}
        </p>
      </div>
      <div v-else class="divide-y divide-n-strong">
        <div
          v-for="contact in filteredContacts"
          :key="contact.id"
          class="flex items-center gap-2 px-4 py-3 hover:bg-n-slate-2 cursor-move transition-colors group"
          draggable="true"
          @dragstart="handleContactDrag($event, contact)"
          @click="handleContactClick(contact)"
        >
          <Avatar
            :name="contact.name"
            :src="contact.thumbnail"
            :size="32"
            :status="contact.availability_status"
            rounded-full
          />
          <div class="flex-1 min-w-0 mr-1">
            <h4 class="text-sm font-medium truncate text-n-slate-12">
              {{ contact.name || t('KANBAN.CONTACTS_SIDEBAR.UNNAMED') }}
            </h4>
            <p v-if="contact.email" class="text-xs text-n-slate-10 truncate">
              {{ contact.email }}
            </p>
          </div>
          <button
            v-if="funnelId"
            class="opacity-0 group-hover:opacity-100 p-1.5 rounded hover:bg-n-slate-3 transition-opacity cursor-pointer"
            :title="t('KANBAN.CONTACTS_SIDEBAR.ADD_TO_FUNNEL')"
            @click.stop="handleAddToFunnel(contact, $event)"
          >
            <Icon icon="i-lucide-plus" class="size-4 text-n-slate-11" />
          </button>
        </div>
      </div>
    </div>
    <footer
      v-if="totalItems > 0"
      class="sticky bottom-0 z-0 px-4 pb-4 border-t border-n-strong bg-n-slate-1"
    >
      <PaginationFooter
        current-page-info="CONTACTS_LAYOUT.PAGINATION_FOOTER.SHOWING"
        :current-page="currentPage"
        :total-items="totalItems"
        :items-per-page="itemsPerPage"
        @update:current-page="handlePageChange"
      />
    </footer>
  </div>
</template>
