<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import {
  useStore,
  useMapGetter,
  useStoreGetters,
} from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Auth from '../../../../api/auth';
import wootConstants from 'dashboard/constants/globals';
import InboxMembersAPI from '../../../../api/inboxMembers';

const props = defineProps({
  id: {
    type: Number,
    required: true,
  },
  name: {
    type: String,
    required: true,
  },
  email: {
    type: String,
    default: '',
  },
  type: {
    type: String,
    default: '',
  },
  availability: {
    type: String,
    default: '',
  },
  provider: {
    type: String,
    default: '',
  },
  customRoleId: {
    type: Number,
    default: null,
  },
  conversationFilterMode: {
    type: String,
    default: 'all_conversations',
  },
  visibleTeamIds: {
    type: Array,
    default: () => [],
  },
  filterAssignedOnly: {
    type: Boolean,
    default: false,
  },
  filterUnassignedOnly: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close']);

const { AVAILABILITY_STATUS_KEYS } = wootConstants;

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const agentName = ref(props.name);
const agentAvailability = ref(props.availability);
const selectedRoleId = ref(props.customRoleId || props.type);
const conversationFilterMode = ref(props.conversationFilterMode);
const visibleTeamIds = ref([...(props.visibleTeamIds || [])]);
const filterAssignedOnly = ref(props.filterAssignedOnly || false);
const filterUnassignedOnly = ref(props.filterUnassignedOnly || false);
const activeTab = ref('sectors');
const agentCredentials = ref({ email: props.email });

const tabs = computed(() => [
  {
    id: 'sectors',
    label: t('AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.TABS.SECTORS'),
  },
  {
    id: 'filters',
    label: t('AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.TABS.FILTERS'),
  },
  {
    id: 'inboxes',
    label: t('AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.TABS.INBOXES'),
  },
]);

// Inbox management
const selectedInboxIds = ref([]);
const isLoadingInboxes = ref(false);
const initialInboxIds = ref([]);

const rules = {
  agentName: { required, minLength: minLength(1) },
  selectedRoleId: { required },
  agentAvailability: { required },
};

const v$ = useVuelidate(rules, {
  agentName,
  selectedRoleId,
  agentAvailability,
});

const pageTitle = computed(
  () => `${t('AGENT_MGMT.EDIT.TITLE')} - ${props.name}`
);

const uiFlags = useMapGetter('agents/getUIFlags');
const getCustomRoles = useMapGetter('customRole/getCustomRoles');
const teamsList = useMapGetter('teams/getTeams');
const inboxesList = computed(() => getters['inboxes/getInboxes'].value || []);

// Check if inboxes have changed from initial state
const inboxesHaveChanged = computed(() => {
  if (selectedInboxIds.value.length !== initialInboxIds.value.length) {
    return true;
  }
  const sortedSelected = [...selectedInboxIds.value].sort();
  const sortedInitial = [...initialInboxIds.value].sort();
  return !sortedSelected.every((id, index) => id === sortedInitial[index]);
});

const roles = computed(() => {
  const defaultRoles = [
    {
      id: 'administrator',
      name: 'administrator',
      label: t('AGENT_MGMT.AGENT_TYPES.ADMINISTRATOR'),
    },
    {
      id: 'agent',
      name: 'agent',
      label: t('AGENT_MGMT.AGENT_TYPES.AGENT'),
    },
  ];

  const customRoles = getCustomRoles.value.map(role => ({
    id: role.id,
    name: `custom_${role.id}`,
    label: role.name,
  }));

  return [...defaultRoles, ...customRoles];
});

const selectedRole = computed(() =>
  roles.value.find(
    role =>
      role.id === selectedRoleId.value || role.name === selectedRoleId.value
  )
);

const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

const availabilityStatuses = computed(() =>
  statusList.value.map((statusLabel, index) => ({
    label: statusLabel,
    value: AVAILABILITY_STATUS_KEYS[index],
    disabled: props.availability === AVAILABILITY_STATUS_KEYS[index],
  }))
);

// Toggle inbox selection
const toggleInbox = inboxId => {
  const index = selectedInboxIds.value.indexOf(inboxId);
  if (index === -1) {
    selectedInboxIds.value.push(inboxId);
  } else {
    selectedInboxIds.value.splice(index, 1);
  }
};

// Select all inboxes
const selectAllInboxes = () => {
  selectedInboxIds.value = inboxesList.value.map(inbox => inbox.id);
};

// Deselect all inboxes
const deselectAllInboxes = () => {
  selectedInboxIds.value = [];
};

// Fetch inboxes where the agent is a member
const fetchAgentInboxes = async () => {
  isLoadingInboxes.value = true;

  try {
    if (inboxesList.value.length === 0) {
      await store.dispatch('inboxes/get');
    }

    const inboxIds = [];
    await Promise.all(
      inboxesList.value.map(async inbox => {
        try {
          const response = await InboxMembersAPI.show(inbox.id);
          const members = response.data?.payload || [];
          if (members.some(member => member.id === props.id)) {
            inboxIds.push(inbox.id);
          }
        } catch (err) {
          // Silently ignore errors for individual inboxes
        }
      })
    );

    selectedInboxIds.value = [...inboxIds];
    initialInboxIds.value = [...inboxIds];
  } catch (error) {
    // Error is handled silently
  } finally {
    isLoadingInboxes.value = false;
  }
};

// Update inbox membership for the agent
const updateAgentInboxes = async (showAlert = true) => {
  if (!inboxesHaveChanged.value) return;

  try {
    // Find inboxes to add and remove
    const inboxesToAdd = selectedInboxIds.value.filter(
      id => !initialInboxIds.value.includes(id)
    );
    const inboxesToRemove = initialInboxIds.value.filter(
      id => !selectedInboxIds.value.includes(id)
    );

    // Process additions - add agent to new inboxes
    await Promise.all(
      inboxesToAdd.map(async inboxId => {
        try {
          const response = await InboxMembersAPI.show(inboxId);
          const currentMembers = response.data?.payload || [];
          const memberIds = currentMembers.map(m => m.id);

          if (!memberIds.includes(props.id)) {
            memberIds.push(props.id);
            await InboxMembersAPI.update({ inboxId, agentList: memberIds });
          }
        } catch (error) {
          // Error is handled silently
        }
      })
    );

    // Process removals - remove agent from inboxes
    await Promise.all(
      inboxesToRemove.map(async inboxId => {
        try {
          const response = await InboxMembersAPI.show(inboxId);
          const currentMembers = response.data?.payload || [];
          const memberIds = currentMembers
            .map(m => m.id)
            .filter(id => id !== props.id);

          await InboxMembersAPI.update({ inboxId, agentList: memberIds });
        } catch (error) {
          // Error is handled silently
        }
      })
    );

    // Update initial state to reflect current state
    initialInboxIds.value = [...selectedInboxIds.value];

    // Refresh the inboxes in the global store to ensure UI sync
    await store.dispatch('inboxes/get');

    if (showAlert) {
      useAlert(t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    }
  } catch (error) {
    if (showAlert) {
      useAlert(t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
    }
    throw error;
  }
};

const editAgent = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const payload = {
      id: props.id,
      name: agentName.value,
      availability: agentAvailability.value,
      conversation_filter_mode: conversationFilterMode.value,
      visible_team_ids: visibleTeamIds.value,
      filter_assigned_only: filterAssignedOnly.value,
      filter_unassigned_only: filterUnassignedOnly.value,
    };

    if (selectedRole.value.name.startsWith('custom_')) {
      payload.custom_role_id = selectedRole.value.id;
    } else {
      payload.role = selectedRole.value.name;
      payload.custom_role_id = null;
    }

    await store.dispatch('agents/update', payload);

    // Also update inbox memberships if changed
    if (inboxesHaveChanged.value) {
      await updateAgentInboxes(false); // false = don't show separate alert
    }

    useAlert(t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    emit('close');
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

const resetPassword = async () => {
  try {
    await Auth.resetPassword(agentCredentials.value);
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ERROR_MESSAGE'));
  }
};

// Load inboxes when tab is changed to 'inboxes'
watch(activeTab, newTab => {
  if (
    newTab === 'inboxes' &&
    initialInboxIds.value.length === 0 &&
    !isLoadingInboxes.value
  ) {
    fetchAgentInboxes();
  }
});

// Also load if starting on inboxes tab
onMounted(() => {
  store.dispatch('inboxes/get');
});
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="pageTitle" />
    <form class="w-full" @submit.prevent="editAgent">
      <div class="w-full">
        <label :class="{ error: v$.agentName.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.NAME.LABEL') }}
          <input
            v-model="agentName"
            type="text"
            :placeholder="$t('AGENT_MGMT.EDIT.FORM.NAME.PLACEHOLDER')"
            @input="v$.agentName.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.selectedRoleId.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.LABEL') }}
          <select v-model="selectedRoleId" @change="v$.selectedRoleId.$touch">
            <option v-for="role in roles" :key="role.id" :value="role.id">
              {{ role.label }}
            </option>
          </select>
          <span v-if="v$.selectedRoleId.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.agentAvailability.$error }">
          {{ $t('PROFILE_SETTINGS.FORM.AVAILABILITY.LABEL') }}
          <select
            v-model="agentAvailability"
            @change="v$.agentAvailability.$touch"
          >
            <option
              v-for="status in availabilityStatuses"
              :key="status.value"
              :value="status.value"
            >
              {{ status.label }}
            </option>
          </select>
          <span v-if="v$.agentAvailability.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_AVAILABILITY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full mt-4">
        <nav class="flex border-b border-n-weak mb-4 overflow-x-auto">
          <button
            v-for="tab in tabs"
            :key="tab.id"
            type="button"
            class="px-4 py-2 text-sm font-medium border-b-2 transition-colors duration-200 whitespace-nowrap"
            :class="
              activeTab === tab.id
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
            "
            @click="activeTab = tab.id"
          >
            {{ tab.label }}
          </button>
        </nav>

        <div v-if="activeTab === 'sectors'" class="py-2 flex flex-col gap-2">
          <label class="flex items-center gap-2 mb-2 cursor-pointer">
            <input
              type="checkbox"
              :checked="visibleTeamIds.length === 0"
              @change="visibleTeamIds = []"
            />
            <span class="text-sm">
              {{ $t('AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.ALL_TEAMS') }}
            </span>
          </label>
          <div
            class="h-[200px] overflow-y-auto border border-n-weak rounded p-2"
          >
            <label
              v-for="team in teamsList"
              :key="team.id"
              class="flex items-center gap-2 py-1 cursor-pointer hover:bg-n-slate-3 rounded px-2"
            >
              <input
                v-model="visibleTeamIds"
                type="checkbox"
                :value="team.id"
                :disabled="visibleTeamIds.length === 0 && false"
              />
              <span class="text-sm uppercase">{{ team.name }}</span>
            </label>
          </div>
        </div>

        <div v-if="activeTab === 'filters'" class="py-2 flex flex-col gap-4">
          <label class="flex items-center gap-2 cursor-pointer">
            <input v-model="filterAssignedOnly" type="checkbox" />
            <span class="text-sm">
              {{
                $t(
                  'AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.FILTERS_LIST.ONLY_MINE'
                )
              }}
            </span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input v-model="filterUnassignedOnly" type="checkbox" />
            <span class="text-sm">
              {{
                $t(
                  'AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.FILTERS_LIST.ONLY_UNASSIGNED'
                )
              }}
            </span>
          </label>
        </div>

        <div v-if="activeTab === 'inboxes'" class="py-2 flex flex-col gap-2">
          <p class="text-sm text-n-slate-11 mb-2">
            {{
              $t('AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.INBOXES.DESCRIPTION')
            }}
          </p>

          <div
            v-if="isLoadingInboxes"
            class="flex items-center justify-center py-8"
          >
            <span class="text-sm text-n-slate-11">
              {{
                $t('AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.INBOXES.LOADING')
              }}
            </span>
          </div>

          <template v-else>
            <div class="flex items-center gap-4 mb-2">
              <button
                type="button"
                class="text-sm text-n-brand hover:underline"
                @click="selectAllInboxes"
              >
                {{
                  $t(
                    'AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.INBOXES.SELECT_ALL'
                  )
                }}
              </button>
              <button
                type="button"
                class="text-sm text-n-brand hover:underline"
                @click="deselectAllInboxes"
              >
                {{
                  $t(
                    'AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.INBOXES.DESELECT_ALL'
                  )
                }}
              </button>
            </div>

            <div
              v-if="inboxesList.length === 0"
              class="py-4 text-center text-sm text-n-slate-11"
            >
              {{
                $t(
                  'AGENT_MGMT.EDIT.FORM.CONVERSATION_FILTER.INBOXES.NO_INBOXES'
                )
              }}
            </div>

            <div
              v-else
              class="h-[200px] overflow-y-auto border border-n-weak rounded p-2"
            >
              <label
                v-for="inbox in inboxesList"
                :key="inbox.id"
                class="flex items-center gap-2 py-1 cursor-pointer hover:bg-n-slate-3 rounded px-2"
              >
                <input
                  type="checkbox"
                  :checked="selectedInboxIds.includes(inbox.id)"
                  @change="toggleInbox(inbox.id)"
                />
                <span class="text-sm">{{ inbox.name }}</span>
                <span class="text-xs text-n-slate-10 ml-auto">
                  {{ inbox.channel_type }}
                </span>
              </label>
            </div>
          </template>
        </div>
      </div>

      <div class="flex flex-row justify-start w-full gap-2 px-0 py-2">
        <div class="w-[50%] ltr:text-left rtl:text-right">
          <Button
            v-if="provider !== 'saml'"
            ghost
            type="button"
            icon="i-lucide-lock-keyhole"
            class="!px-2"
            :label="$t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_RESET_BUTTON')"
            @click.prevent="resetPassword"
          />
        </div>
        <div class="w-[50%] flex justify-end items-center gap-2">
          <Button
            faded
            slate
            type="reset"
            :label="$t('AGENT_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="emit('close')"
          />
          <Button
            type="submit"
            :label="$t('AGENT_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="v$.$invalid || uiFlags.isUpdating || isLoadingInboxes"
            :is-loading="uiFlags.isUpdating"
          />
        </div>
      </div>
    </form>
  </div>
</template>
