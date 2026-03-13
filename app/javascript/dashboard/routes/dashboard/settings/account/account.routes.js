import { frontendURL } from '../../../../helper/URLHelper';
import Index from './Index.vue';
import Specific from './Specific.vue';
import SettingsWrapper from '../SettingsWrapper.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/general'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'general_settings_index',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/specific'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'specific_settings_index',
          component: Specific,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
