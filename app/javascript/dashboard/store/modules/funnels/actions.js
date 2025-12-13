import {
  SET_FUNNEL_UI_FLAG,
  CLEAR_FUNNELS,
  SET_FUNNELS,
  SET_FUNNEL_ITEM,
  EDIT_FUNNEL,
  DELETE_FUNNEL,
  SET_FUNNEL_CONTACTS,
  UPDATE_FUNNEL_CONTACT,
  REMOVE_FUNNEL_CONTACT,
} from './types';
import FunnelsAPI from '../../../api/funnels';

export const actions = {
  create: async ({ commit }, funnelInfo) => {
    // #region agent log
    fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'funnels/actions.js:15',
        message: 'funnels/create action called',
        data: { funnelInfo },
        timestamp: Date.now(),
        sessionId: 'debug-session',
        runId: 'run1',
        hypothesisId: 'B',
      }),
    }).catch(() => {});
    // #endregion
    commit(SET_FUNNEL_UI_FLAG, { isCreating: true });
    try {
      // #region agent log
      fetch(
        'http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            location: 'funnels/actions.js:18',
            message: 'Calling FunnelsAPI.create',
            data: { funnelInfo, url: window.location.pathname },
            timestamp: Date.now(),
            sessionId: 'debug-session',
            runId: 'run1',
            hypothesisId: 'B',
          }),
        }
      ).catch(() => {});
      // #endregion
      const response = await FunnelsAPI.create({ funnel: funnelInfo });
      // #region agent log
      fetch(
        'http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            location: 'funnels/actions.js:20',
            message: 'FunnelsAPI.create success',
            data: {
              funnelId: response?.data?.id,
              funnelName: response?.data?.name,
            },
            timestamp: Date.now(),
            sessionId: 'debug-session',
            runId: 'run1',
            hypothesisId: 'B',
          }),
        }
      ).catch(() => {});
      // #endregion
      const funnel = response.data;
      commit(SET_FUNNEL_ITEM, funnel);
      return funnel;
    } catch (error) {
      // #region agent log
      fetch(
        'http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            location: 'funnels/actions.js:23',
            message: 'Error in funnels/create',
            data: {
              error: error?.message || error?.toString(),
              errorResponse: error?.response?.data,
              status: error?.response?.status,
            },
            timestamp: Date.now(),
            sessionId: 'debug-session',
            runId: 'run1',
            hypothesisId: 'B',
          }),
        }
      ).catch(() => {});
      // #endregion
      throw new Error(error);
    } finally {
      commit(SET_FUNNEL_UI_FLAG, { isCreating: false });
    }
  },

  get: async ({ commit }) => {
    commit(SET_FUNNEL_UI_FLAG, { isFetching: true });
    try {
      const response = await FunnelsAPI.get();
      const data = response?.data || [];
      commit(CLEAR_FUNNELS);
      commit(SET_FUNNELS, Array.isArray(data) ? data : []);
    } catch (error) {
      commit(CLEAR_FUNNELS);
      commit(SET_FUNNELS, []);
      throw error;
    } finally {
      commit(SET_FUNNEL_UI_FLAG, { isFetching: false });
    }
  },

  show: async ({ commit }, { id }) => {
    commit(SET_FUNNEL_UI_FLAG, { isFetchingItem: true });
    try {
      const response = await FunnelsAPI.show(id);
      commit(SET_FUNNEL_ITEM, response.data);
      commit(SET_FUNNEL_UI_FLAG, {
        isFetchingItem: false,
      });
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(SET_FUNNEL_UI_FLAG, {
        isFetchingItem: false,
      });
    }
  },

  update: async ({ commit }, { id, ...updateObj }) => {
    // #region agent log
    fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'funnels/actions.js:62',
        message: 'funnels/update action called',
        data: {
          id,
          updateObj,
          hasColumns: !!updateObj.columns,
          columnsCount: updateObj.columns?.length,
        },
        timestamp: Date.now(),
        sessionId: 'debug-session',
        runId: 'run1',
        hypothesisId: 'A',
      }),
    }).catch(() => {});
    // #endregion
    commit(SET_FUNNEL_UI_FLAG, { isUpdating: true });
    try {
      // #region agent log
      fetch(
        'http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            location: 'funnels/actions.js:65',
            message: 'Calling FunnelsAPI.update',
            data: { id, updateObj, url: window.location.pathname },
            timestamp: Date.now(),
            sessionId: 'debug-session',
            runId: 'run1',
            hypothesisId: 'A',
          }),
        }
      ).catch(() => {});
      // #endregion
      const response = await FunnelsAPI.update(id, { funnel: updateObj });
      // #region agent log
      fetch(
        'http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            location: 'funnels/actions.js:67',
            message: 'FunnelsAPI.update success',
            data: {
              funnelId: response?.data?.id,
              columnsCount: response?.data?.columns?.length,
            },
            timestamp: Date.now(),
            sessionId: 'debug-session',
            runId: 'run1',
            hypothesisId: 'A',
          }),
        }
      ).catch(() => {});
      // #endregion
      commit(EDIT_FUNNEL, response.data);
    } catch (error) {
      // #region agent log
      fetch(
        'http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            location: 'funnels/actions.js:69',
            message: 'Error in funnels/update',
            data: {
              error: error?.message || error?.toString(),
              errorResponse: error?.response?.data,
              status: error?.response?.status,
            },
            timestamp: Date.now(),
            sessionId: 'debug-session',
            runId: 'run1',
            hypothesisId: 'A',
          }),
        }
      ).catch(() => {});
      // #endregion
      throw new Error(error);
    } finally {
      commit(SET_FUNNEL_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, funnelId) => {
    commit(SET_FUNNEL_UI_FLAG, { isDeleting: true });
    try {
      await FunnelsAPI.delete(funnelId);
      commit(DELETE_FUNNEL, funnelId);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(SET_FUNNEL_UI_FLAG, { isDeleting: false });
    }
  },

  getContacts: async ({ commit }, { funnelId }) => {
    try {
      const { data } = await FunnelsAPI.getContacts(funnelId);
      commit(SET_FUNNEL_CONTACTS, { funnelId, contacts: data || [] });
    } catch (error) {
      commit(SET_FUNNEL_CONTACTS, { funnelId, contacts: [] });
      throw error;
    }
  },

  moveContact: async (
    { commit, state },
    { funnelId, contactId, columnId, position }
  ) => {
    // Optimistic update: salva estado atual e atualiza a UI imediatamente
    const funnel = state.records[funnelId];
    let previousContacts = null;

    if (funnel && funnel.contacts) {
      previousContacts = [...funnel.contacts];
      const contacts = [...funnel.contacts];
      const contactIndex = contacts.findIndex(c => c.contact_id === contactId);

      if (contactIndex !== -1) {
        const contact = { ...contacts[contactIndex] };
        const oldColumnId = contact.column_id;
        contact.column_id = columnId;
        contact.position = position;

        // Remove da coluna antiga
        contacts.splice(contactIndex, 1);

        // Reordena contatos na coluna de origem
        contacts
          .filter(c => c.column_id === oldColumnId)
          .forEach((c, idx) => {
            c.position = idx;
          });

        // Insere na posição correta na nova coluna
        const targetContacts = contacts.filter(c => c.column_id === columnId);
        const targetIndex = targetContacts.findIndex(
          c => (c.position || 0) >= position
        );

        if (targetIndex === -1) {
          contacts.push(contact);
        } else {
          const insertIndex = contacts.findIndex(
            c => c.column_id === columnId && (c.position || 0) >= position
          );
          if (insertIndex === -1) {
            contacts.push(contact);
          } else {
            contacts.splice(insertIndex, 0, contact);
          }
        }

        // Reordena contatos na coluna de destino
        contacts
          .filter(c => c.column_id === columnId)
          .forEach((c, idx) => {
            c.position = idx;
          });

        commit(SET_FUNNEL_CONTACTS, { funnelId, contacts });
      }
    }

    try {
      const { data } = await FunnelsAPI.moveContact(
        funnelId,
        contactId,
        columnId,
        position
      );
      // Atualiza com os dados do servidor
      commit(UPDATE_FUNNEL_CONTACT, { funnelId, contact: data });
      return data;
    } catch (error) {
      // Reverte em caso de erro
      if (previousContacts) {
        commit(SET_FUNNEL_CONTACTS, { funnelId, contacts: previousContacts });
      }
      throw new Error(error);
    }
  },

  addContact: async ({ commit }, { funnelId, contactId, columnId }) => {
    try {
      const { data } = await FunnelsAPI.addContact(
        funnelId,
        contactId,
        columnId
      );
      commit(UPDATE_FUNNEL_CONTACT, { funnelId, contact: data });
      return data;
    } catch (error) {
      throw new Error(error);
    }
  },

  removeContact: async ({ commit }, { funnelId, contactId }) => {
    try {
      await FunnelsAPI.removeContact(funnelId, contactId);
      commit(REMOVE_FUNNEL_CONTACT, { funnelId, contactId });
    } catch (error) {
      throw new Error(error);
    }
  },
};
