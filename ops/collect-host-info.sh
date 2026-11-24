#!/usr/bin/env bash
set -Eeuo pipefail
printf '\n== Capture time ==\n'; date -Is
printf '\n== Operating system ==\n'; (cat /etc/os-release || true)
printf '\n== CPU ==\n'; (lscpu || true)
printf '\n== Memory ==\n'; (free -h || true)
printf '\n== Disk ==\n'; (df -hT || true)
printf '\n== Docker ==\n'; (docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}' || true)
printf '\n== Docker Compose ==\n'; (docker compose version || true)
printf '\n== Container resource summary ==\n'; (docker stats --no-stream || true)
printf '\n== Docker storage usage ==\n'; (docker system df || true)
