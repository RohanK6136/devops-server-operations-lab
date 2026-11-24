#!/usr/bin/env bash
set -Eeuo pipefail
TARGET_FILE="${1:-ops/probe-targets.txt}"
if [[ ! -f "$TARGET_FILE" ]]; then
  echo "Missing target file: $TARGET_FILE" >&2
  exit 2
fi
failures=0
while IFS= read -r url || [[ -n "$url" ]]; do
  [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
  status="$(curl --silent --show-error --location --output /dev/null --max-time 10 --write-out '%{http_code}' "$url" 2>/dev/null || true)"
  if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
    printf 'UP   %s (%s)\n' "$url" "$status"
  else
    printf 'DOWN %s (%s)\n' "$url" "${status:-no-response}"
    failures=$((failures + 1))
  fi
done < "$TARGET_FILE"
exit "$failures"
