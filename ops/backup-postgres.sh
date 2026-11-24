#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: .env is missing. Copy .env.example to .env and set database credentials." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${POSTGRES_USER:?POSTGRES_USER is required in .env}"
: "${POSTGRES_DB:?POSTGRES_DB is required in .env}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
mkdir -p "$BACKUP_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="$BACKUP_DIR/${POSTGRES_DB}_${STAMP}.dump"
TMP_FILE="$BACKUP_FILE.tmp"
trap 'rm -f "$TMP_FILE"' EXIT

# A custom-format dump is compressed by pg_dump and can be selectively restored.
docker compose exec -T postgres pg_dump \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --format=custom \
  --no-owner \
  --no-acl > "$TMP_FILE"

if [[ ! -s "$TMP_FILE" ]]; then
  echo "ERROR: dump is empty; refusing to mark it as successful." >&2
  exit 1
fi

docker compose exec -T postgres pg_restore --list < "$TMP_FILE" >/dev/null
mv "$TMP_FILE" "$BACKUP_FILE"
sha256sum "$BACKUP_FILE" > "$BACKUP_FILE.sha256"

find "$BACKUP_DIR" -type f -name "${POSTGRES_DB}_*.dump" -mtime "+$RETENTION_DAYS" -print -delete
find "$BACKUP_DIR" -type f -name "${POSTGRES_DB}_*.dump.sha256" -mtime "+$RETENTION_DAYS" -print -delete

printf 'Backup created and archive-list check passed: %s\n' "$BACKUP_FILE"
printf 'Size: %s\n' "$(du -h "$BACKUP_FILE" | awk '{print $1}')"
printf 'Retention: %s days\n' "$RETENTION_DAYS"
