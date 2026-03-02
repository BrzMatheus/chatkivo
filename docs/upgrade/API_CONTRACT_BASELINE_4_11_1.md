# API Contract Baseline (`4.11.1`)

## Goal
Lock critical custom API behavior to avoid regressions during upstream upgrades.

## Funnels
- `GET /api/v1/accounts/:account_id/funnels`
  - Auth required
  - Creates default funnel when account has none
  - Returns array of funnels
- `POST /api/v1/accounts/:account_id/funnels`
  - Auth required
  - Creates funnel with `name` and `columns`
- `PATCH /api/v1/accounts/:account_id/funnels/:id`
  - Auth required
  - Updates funnel attributes
- `POST /api/v1/accounts/:account_id/funnels/:id/move_contact`
  - Auth required
  - Upserts funnel contact position/column

## Funnel Contacts
- `GET /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_contacts`
  - Auth required
  - Returns funnel contact list ordered by `column_id`, `position`
- `POST /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_contacts`
  - Auth required
  - Upserts by `contact_id`
  - Defaults `column_id` to first funnel column if omitted
- `PATCH /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_contacts/:contact_id`
  - Auth required
  - Updates `column_id` and `position`
- `DELETE /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_contacts/:contact_id`
  - Auth required
  - Deletes mapping

## Conversation Messages
- `PUT /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id`
  - `status` flow only for API inboxes
  - `content` edit only for API and Telegram inboxes
  - Transient failed statuses are ignored for known timeout errors

## Profile
- `PUT /api/v1/profile/set_active_account`
  - Updates `active_at` when user belongs to target account
  - Returns unauthorized otherwise
- `POST /api/v1/profile/reset_access_token`
  - Regenerates current user access token
