import { API } from 'widget/helpers/axios';
import { actions } from '../../message';

const commit = vi.fn();
const dispatch = vi.fn();
vi.mock('widget/helpers/axios');

describe('#actions', () => {
  describe('#update', () => {
    it('sends correct actions', async () => {
      const user = {
        email: 'john@acme.inc',
        messageId: 10,
        submittedValues: {
          email: 'john@acme.inc',
        },
      };
      API.patch.mockResolvedValue({
        data: { contact: { pubsub_token: '8npuMUfDgizrwVoqcK1t7FMY' } },
      });
      await actions.update(
        {
          commit,
          dispatch,
          getters: {
            getUIFlags: {
              isUpdating: false,
            },
          },
        },
        user
      );
      expect(commit.mock.calls).toEqual([
        ['toggleUpdateStatus', true],
        [
          'conversation/updateMessage',
          {
            id: 10,
            content_attributes: {
              submitted_email: 'john@acme.inc',
              submitted_values: null,
            },
          },
          { root: true },
        ],
        ['toggleUpdateStatus', false],
      ]);
      expect(dispatch.mock.calls).toEqual([
        ['contacts/get', {}, { root: true }],
        ['conversation/clearConversations', {}, { root: true }],
        ['conversation/fetchOldConversations', {}, { root: true }],
        ['conversationAttributes/getAttributes', {}, { root: true }],
      ]);
    });

    it('blocks all new action calls when isUpdating', async () => {
      await actions.update(
        {
          commit,
          getters: {
            getUIFlags: {
              isUpdating: true,
            },
          },
        },
        {}
      );

      expect(commit.mock.calls).toEqual([]);
    });
  });
});
