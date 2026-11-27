#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: .env is missing." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a
: "${POSTGRES_USER:?POSTGRES_USER is required in .env}"
: "${POSTGRES_DB:?POSTGRES_DB is required in .env}"

BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
BACKUP_FILE="${1:-$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${POSTGRES_DB}_*.dump" -printf '%T@ %p\n' | sort -nr | awk 'NR==1 {$1=""; sub(/^ /, ""); print}') }"
BACKUP_FILE="$(printf '%s' "$BACKUP_FILE" | xargs)"
if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
  echo "ERROR: no backup file found. Run ops/backup-postgres.sh first." >&2
  exit 1
fi

if [[ ! -f "$BACKUP_FILE.sha256" ]]; then
  echo "ERROR: checksum sidecar is missing: $BACKUP_FILE.sha256" >&2
  exit 1
fi
(cd "$(dirname "$BACKUP_FILE")" && sha256sum --check "$(basename "$BACKUP_FILE").sha256")

docker compose exec -T postgres pg_restore --list < "$BACKUP_FILE" >/dev/null
RESTORE_DB="ops_restore_verify_$(date -u +%Y%m%d%H%M%S)"
CREATED=0
cleanup() {
  if [[ "$CREATED" -eq 1 ]]; then
    docker compose exec -T postgres dropdb --if-exists --username "$POSTGRES_USER" "$RESTORE_DB" >/dev/null || true
  fi
}
trap cleanup EXIT

docker compose exec -T postgres createdb --username "$POSTGRES_USER" "$RESTORE_DB"
CREATED=1
cat "$BACKUP_FILE" | docker compose exec -T postgres pg_restore \
  --username "$POSTGRES_USER" \
  --dbname "$RESTORE_DB" \
  --no-owner --no-acl --exit-on-error

TABLE_COUNT="$(docker compose exec -T postgres psql -At --username "$POSTGRES_USER" --dbname "$RESTORE_DB" -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" | tr -d '\r')"

if [[ "$TABLE_COUNT" -lt 1 ]]; then
  echo "ERROR: restore completed but no public tables were restored." >&2
  exit 1
fi

EVENT_TABLE_COUNT="$(docker compose exec -T postgres psql -At --username "$POSTGRES_USER" --dbname "$RESTORE_DB" -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='lab_events' AND table_type='BASE TABLE';" | tr -d '\r')"
if [[ "$EVENT_TABLE_COUNT" -ne 1 ]]; then
  echo "ERROR: lab_events table was not restored." >&2
  exit 1
fi

EVENT_ROW_COUNT="$(docker compose exec -T postgres psql -At --username "$POSTGRES_USER" --dbname "$RESTORE_DB" -c "SELECT count(*) FROM public.lab_events;" | tr -d '\r')"
if [[ "$EVENT_ROW_COUNT" -lt 1 ]]; then
  echo "ERROR: no operational event rows were restored. Create a sample event before running the restore test." >&2
  exit 1
fi
printf 'Restore verification passed. Temporary database: %s; public tables restored: %s; lab event rows restored: %s\n' "$RESTORE_DB" "$TABLE_COUNT" "$EVENT_ROW_COUNT"
printf 'The temporary verification database will now be dropped. The source database was not modified.\n'
