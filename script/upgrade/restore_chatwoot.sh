#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  restore_chatwoot.sh \
    --compose-file <file> \
    --postgres-sql <dump.sql> \
    --storage-archive <storage.tar.gz> \
    --storage-volume <docker_volume>

Example:
  restore_chatwoot.sh \
    --compose-file docker-compose.production.yaml \
    --postgres-sql /var/backups/chatkivo/chatkivo_20260302_120000_postgres.sql \
    --storage-archive /var/backups/chatkivo/chatkivo_20260302_120000_storage.tar.gz \
    --storage-volume chatwootsrc_storage_data
EOF
}

compose_file=""
postgres_sql=""
storage_archive=""
storage_volume=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-file)
      compose_file="$2"
      shift 2
      ;;
    --postgres-sql)
      postgres_sql="$2"
      shift 2
      ;;
    --storage-archive)
      storage_archive="$2"
      shift 2
      ;;
    --storage-volume)
      storage_volume="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$compose_file" || -z "$postgres_sql" || -z "$storage_archive" || -z "$storage_volume" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$compose_file" ]]; then
  echo "Compose file not found: $compose_file"
  exit 1
fi
if [[ ! -f "$postgres_sql" ]]; then
  echo "PostgreSQL dump not found: $postgres_sql"
  exit 1
fi
if [[ ! -f "$storage_archive" ]]; then
  echo "Storage archive not found: $storage_archive"
  exit 1
fi

echo "[1/4] Stopping application services..."
docker compose -f "$compose_file" stop rails sidekiq || true

echo "[2/4] Restoring PostgreSQL..."
cat "$postgres_sql" | docker compose -f "$compose_file" exec -T postgres sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" "$POSTGRES_DB"'

echo "[3/4] Restoring storage volume..."
archive_dir="$(cd "$(dirname "$storage_archive")" && pwd)"
archive_name="$(basename "$storage_archive")"
docker run --rm \
  -v "${storage_volume}:/volume" \
  -v "${archive_dir}:/backup:ro" \
  alpine:3.20 sh -lc \
  "rm -rf /volume/* && tar xzf /backup/${archive_name} -C /volume"

echo "[4/4] Starting services..."
docker compose -f "$compose_file" up -d
docker compose -f "$compose_file" run --rm rails bundle exec rails db:chatwoot_prepare

echo "Restore completed."
