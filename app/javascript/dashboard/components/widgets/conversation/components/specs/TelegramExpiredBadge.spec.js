import { shallowMount } from '@vue/test-utils';
import TelegramExpiredBadge from '../TelegramExpiredBadge.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key =>
      ({
        'CONVERSATION.TELEGRAM_EXPIRATION.BADGE': 'Expired Conversation',
        'CONVERSATION.TELEGRAM_EXPIRATION.TOOLTIP':
          'This conversation expired after 24 hours. Your messages may not reach the user.',
      })[key] || key,
  }),
}));

describe('TelegramExpiredBadge.vue', () => {
  it('renders the expired conversation label', () => {
    const wrapper = shallowMount(TelegramExpiredBadge, {
      global: {
        stubs: {
          FluentIcon: true,
        },
      },
    });

    expect(wrapper.text()).toContain('Expired Conversation');
  });
});
