/* global axios */
import ApiClient from './ApiClient';

class BulkActionsAPI extends ApiClient {
  constructor() {
    super('bulk_actions', { accountScoped: true });
  }

  exportConversations({ ids }) {
    return axios.post(`${this.url}/export_conversations`, { ids });
  }

  exportConversationsHtml({ ids }) {
    return axios.post(`${this.url}/export_conversations_html`, { ids });
  }
}

export default new BulkActionsAPI();
