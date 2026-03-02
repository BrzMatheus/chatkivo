# ChatKivo Upgrade Runbook (`4.8.0` -> `4.11.1`)

## Scope
- Base branch: `upgrade/v4.11.1-prep`
- Upgrade strategy: incremental merge (`v4.9.2`, `v4.10.1`, `v4.11.1`)
- Conflict policy: preserve custom behavior where business flow can break
- Critical flow: custom API contracts

## 1) Pre-flight (mandatory)
1. Freeze pushes to the production branch configured in EasyPanel.
2. On VPS, run backup:
   ```bash
   bash script/upgrade/backup_chatwoot.sh \
     --compose-file docker-compose.production.yaml \
     --backup-dir /var/backups/chatkivo \
     --storage-volume <EASYPANEL_STORAGE_VOLUME_NAME>
   ```
3. Copy backup files to external storage (S3, GDrive, etc.).
4. Record current production image tag (rollback target).

## 2) Validation before production
1. Validate merge branch locally:
   ```bash
   bundle exec rails zeitwerk:check
   ```
2. Run focused API specs:
   ```bash
   bundle exec rspec \
     spec/controllers/api/v1/accounts/funnels_controller_spec.rb \
     spec/controllers/api/v1/accounts/funnels/funnel_contacts_controller_spec.rb \
     spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb \
     spec/controllers/api/v1/profiles_controller_spec.rb
   ```
3. Build release image tag (example):
   ```bash
   docker build -t houi/chatkivo:4.11.1-kivo.0 -f docker/Dockerfile .
   docker push houi/chatkivo:4.11.1-kivo.0
   ```

## 3) Production rollout (maintenance window)
1. Update EasyPanel service image to `houi/chatkivo:4.11.1-kivo.0`.
2. Deploy and run migration:
   ```bash
   docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails db:chatwoot_prepare
   ```
3. Smoke checks:
- Agent login
- Inbox load
- Send/receive one message
- Custom API flow (funnels + custom conversation/message paths)
- Sidekiq processing health

## 4) Rollback
Trigger rollback if migration fails, login/inbox is broken, or custom API contracts fail.

1. Switch image back to previous stable tag in EasyPanel.
2. Restore DB + storage:
   ```bash
   bash script/upgrade/restore_chatwoot.sh \
     --compose-file docker-compose.production.yaml \
     --postgres-sql /var/backups/chatkivo/<snapshot>_postgres.sql \
     --storage-archive /var/backups/chatkivo/<snapshot>_storage.tar.gz \
     --storage-volume <EASYPANEL_STORAGE_VOLUME_NAME>
   ```
3. Re-run smoke checks.

## 5) Post-deploy monitoring (24h)
- API error rate
- Background job failures
- Message delivery failures
- OAuth login behavior
