# SRE operations lab — 15-minute leadership demo

## 1. What is being demonstrated (2 min)

This is a safe local lab, not the production company server. It demonstrates the operating pattern we intend to apply to each approved application: health checks, resource metrics, container logs, persistent database storage, and a recoverable backup process.

## 2. Start the stack (2 min)

```bash
cp .env.example .env
# Set unique passwords in .env
docker compose up -d --build
docker compose ps
```

Open the storefront/API at `http://127.0.0.1:8080`, Grafana at `http://127.0.0.1:3000`, Prometheus at `http://127.0.0.1:9090`, and Uptime Kuma at `http://127.0.0.1:3001`. Credentials come from `.env` for Grafana; create the Uptime Kuma administrator on first launch.

## 3. Show health and metrics (3 min)

```bash
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/api/health
curl -i http://127.0.0.1:8080/api/info
```

In Grafana, open **Server Operations Overview**. Explain host CPU/memory/disk and individual container usage. In Prometheus, show `/targets` and `/alerts`.

## 4. Simulate and recover a service incident (3 min)

```bash
docker compose stop api
curl -i http://127.0.0.1:8080/api/health
docker compose logs --tail=80 api

docker compose start api
curl -i http://127.0.0.1:8080/api/health
```

Explain the difference between the Nginx liveness endpoint and the API readiness endpoint. Confirm the probe recovers.

## 5. Demonstrate database recovery discipline (3 min)

```bash
./ops/backup-postgres.sh
./ops/restore-test.sh
```

Explain that the restore test uses a temporary database and does not overwrite the original database. Off-host encrypted copies and a tested notification route remain required before production.

## 6. Show uptime monitors and notifications (2 min)

In Uptime Kuma, create HTTP monitors for the approved application health URLs and add the team-approved notification route. Use the test notification feature. Do not use a personal destination without team approval.

## 7. Close (1 min)

Show the inventory and incident templates. Explain that every application needs an owner, health URL, SLO, runbook, rollback, backup policy and escalation route before it is onboarded to a shared server.
