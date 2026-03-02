#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  backup_chatwoot.sh --compose-file <file> --backup-dir <dir> --storage-volume <docker_volume>

Example:
  backup_chatwoot.sh \
    --compose-file docker-compose.production.yaml \
    --backup-dir /var/backups/chatkivo \
    --storage-volume chatwootsrc_storage_data
EOF
}

compose_file=""
backup_dir=""
storage_volume=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-file)
      compose_file="$2"
      shift 2
      ;;
    --backup-dir)
      backup_dir="$2"
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

if [[ -z "$compose_file" || -z "$backup_dir" || -z "$storage_volume" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$compose_file" ]]; then
  echo "Compose file not found: $compose_file"
  exit 1
fi

mkdir -p "$backup_dir"
timestamp="$(date -u +%Y%m%d_%H%M%S)"
backup_prefix="$backup_dir/chatkivo_${timestamp}"

echo "[1/4] Saving environment and compose snapshot..."
cp "$compose_file" "${backup_prefix}_compose.yaml"
if [[ -f ".env" ]]; then
  cp ".env" "${backup_prefix}.env"
fi

echo "[2/4] Dumping PostgreSQL..."
docker compose -f "$compose_file" exec -T postgres sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  > "${backup_prefix}_postgres.sql"

echo "[3/4] Archiving storage volume..."
docker run --rm \
  -v "${storage_volume}:/volume:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.20 sh -lc \
  "cd /volume && tar czf /backup/$(basename "${backup_prefix}")_storage.tar.gz ."

echo "[4/4] Writing backup manifest..."
cat > "${backup_prefix}_manifest.txt" <<EOF
timestamp_utc=${timestamp}
compose_file=${compose_file}
postgres_dump=$(basename "${backup_prefix}_postgres.sql")
storage_archive=$(basename "${backup_prefix}_storage.tar.gz")
env_snapshot=$(basename "${backup_prefix}.env")
EOF

echo "Backup completed:"
echo "  - ${backup_prefix}_postgres.sql"
echo "  - ${backup_prefix}_storage.tar.gz"
echo "  - ${backup_prefix}_compose.yaml"
echo "  - ${backup_prefix}.env (if present)"
echo "  - ${backup_prefix}_manifest.txt"
