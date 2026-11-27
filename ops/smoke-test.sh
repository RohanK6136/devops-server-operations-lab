#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BASE_URL="http://127.0.0.1:${WEB_PORT:-8080}"
TEMP_BODY="$(mktemp)"
cleanup() {
  rm -f "$TEMP_BODY"
  docker compose down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_http() {
  local url="$1"
  local description="$2"
  local attempt
  for attempt in $(seq 1 30); do
    if curl --silent --show-error --fail --max-time 5 "$url" -o "$TEMP_BODY"; then
      printf 'PASS: %s (%s)\n' "$description" "$url"
      return 0
    fi
    sleep 2
  done
  printf 'FAIL: %s did not become healthy (%s)\n' "$description" "$url" >&2
  return 1
}

echo "== Starting core services =="
docker compose up -d --build

echo "== Checking routing and service health =="
require_http "$BASE_URL/health" "Nginx main-site health"
require_http "$BASE_URL/api/health" "API readiness through Nginx"
require_http "$BASE_URL/second/health" "Second website health through Nginx"

curl --silent --show-error --fail "$BASE_URL/" -o "$TEMP_BODY"
grep -q "DevOps Operations Lab" "$TEMP_BODY"
echo "PASS: main website content is served."

curl --silent --show-error --fail "$BASE_URL/second/" -o "$TEMP_BODY"
grep -q "One server" "$TEMP_BODY"
echo "PASS: second independent website content is served."

curl --silent --show-error --fail "$BASE_URL/api/info" -o "$TEMP_BODY"
grep -q "devops-lab-api" "$TEMP_BODY"
echo "PASS: API runtime information endpoint responds."

echo "== Simulating API outage =="
docker compose stop api
API_STATUS="$(curl --silent --show-error --output "$TEMP_BODY" --write-out '%{http_code}' --max-time 8 "$BASE_URL/api/health" || true)"
case "$API_STATUS" in
  5??) echo "PASS: API failure detected through Nginx (HTTP $API_STATUS)." ;;
  *) echo "FAIL: expected a 5xx API response while API is stopped; got HTTP $API_STATUS." >&2; exit 1 ;;
esac

require_http "$BASE_URL/health" "Nginx remains available during API outage"
require_http "$BASE_URL/second/health" "Second website remains available during API outage"

echo "== Recovering API =="
docker compose start api
require_http "$BASE_URL/api/health" "API readiness after restart"
echo "PASS: API recovered."

echo "== Verifying PostgreSQL backup and isolated restore =="
./ops/backup-postgres.sh
./ops/restore-test.sh
echo "PASS: PostgreSQL backup archive validation and temporary-database restore test completed."

echo "== Final core service state =="
docker compose ps
echo "ALL SMOKE TESTS PASSED."
