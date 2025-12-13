/* global axios */

const DEFAULT_API_VERSION = 'v1';

class ApiClient {
  constructor(resource, options = {}) {
    this.apiVersion = `/api/${options.apiVersion || DEFAULT_API_VERSION}`;
    this.options = options;
    this.resource = resource;
  }

  get url() {
    return `${this.baseUrl()}/${this.resource}`;
  }

  // eslint-disable-next-line class-methods-use-this
  get accountIdFromRoute() {
    const isInsideAccountScopedURLs =
      window.location.pathname.includes('/app/accounts');

    // #region agent log
    fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'ApiClient.js:17',
        message: 'accountIdFromRoute called',
        data: {
          pathname: window.location.pathname,
          isInsideAccountScopedURLs,
          accountId: isInsideAccountScopedURLs
            ? window.location.pathname.split('/')[3]
            : '',
        },
        timestamp: Date.now(),
        sessionId: 'debug-session',
        runId: 'run1',
        hypothesisId: 'C',
      }),
    }).catch(() => {});
    // #endregion

    if (isInsideAccountScopedURLs) {
      return window.location.pathname.split('/')[3];
    }

    return '';
  }

  baseUrl() {
    let url = this.apiVersion;

    if (this.options.enterprise) {
      url = `/enterprise${url}`;
    }

    const accountId = this.accountIdFromRoute;
    if (this.options.accountScoped && accountId) {
      url = `${url}/accounts/${accountId}`;
    }

    // #region agent log
    fetch('http://127.0.0.1:7243/ingest/f236a0bf-1671-49c4-876d-286a49e47814', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'ApiClient.js:35',
        message: 'baseUrl calculated',
        data: {
          resource: this.resource,
          apiVersion: this.apiVersion,
          accountScoped: this.options.accountScoped,
          accountId,
          finalUrl: url,
        },
        timestamp: Date.now(),
        sessionId: 'debug-session',
        runId: 'run1',
        hypothesisId: 'C',
      }),
    }).catch(() => {});
    // #endregion

    return url;
  }

  get() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, data);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, data);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default ApiClient;
