# SRE operations lab — 15-minute leadership demo

## 1. What is being demonstrated (2 min)

This is a safe local lab, not the production company server. It demonstrates two websites behind one Nginx reverse proxy, a PostgreSQL-backed API, health checks, resource metrics, container logs, persistent database storage and a recoverable backup process.

## 2. Start the core and monitoring profiles (3 min)

    cp .env.example .env
    # Set unique passwords in .env
    docker compose up -d --build
    docker compose ps
    docker compose --profile monitoring up -d
    docker compose ps

Open the main website at http://127.0.0.1:8080, use the PostgreSQL event journal to save a sample backup-drill record, and open the independent second website at http://127.0.0.1:8080/second/. Both are routed by the same Nginx entry point. Open Grafana at http://127.0.0.1:3000, Prometheus at http://127.0.0.1:9090, Alertmanager at http://127.0.0.1:9093, Mailpit at http://127.0.0.1:8025, and Uptime Kuma at http://127.0.0.1:3001. Grafana credentials come from .env; create the Uptime Kuma administrator on first launch. Mailpit captures alert emails locally and never sends them to real recipients.

## 3. Show routing, health and metrics (3 min)

    curl -i http://127.0.0.1:8080/health
    curl -i http://127.0.0.1:8080/api/health
    curl -i http://127.0.0.1:8080/second/health
    curl -i http://127.0.0.1:8080/api/info

In Grafana, open **Server Operations Overview**. Explain host CPU/memory/disk and individual container usage. In Prometheus, show /targets and /alerts; the blackbox job checks the main web endpoint, API liveness and second website health endpoint.

## 4. Simulate and recover a service incident (4 min)

    docker compose stop api
    curl -i http://127.0.0.1:8080/api/health
    docker compose logs --tail=80 api
    docker compose start api
    curl -i http://127.0.0.1:8080/api/health

Explain that the main Nginx health endpoint and second website can remain available while the API route fails. Show the pending/firing probe alert in Prometheus, then open Mailpit and show the captured PublicProbeFailed email. Restart the API, confirm the alert resolves, and show the recovery email in Mailpit. Prometheus evaluates the rule for one minute before it fires.

## 5. Demonstrate database recovery discipline (3 min)

Create a sample operational event, then back it up and restore it into an isolated temporary database:

~~~bash
curl -i -H 'Content-Type: application/json' -X POST \
  -d '{"eventType":"backup-drill","message":"Manager demo record for restore proof","metadata":{"source":"demo"}}' \
  http://127.0.0.1:8080/api/events
curl -i http://127.0.0.1:8080/api/events
./ops/backup-postgres.sh
./ops/restore-test.sh
~~~

The restore script checks the checksum, verifies that the events table exists and confirms at least one event row was recovered in a temporary database. It drops only the temporary database, not the source data. Off-host encrypted copies and an agreed retention policy remain required before production.

## 6. Close (2 min)

Show the inventory, incident template and monitoring dashboard. Explain that every application needs an owner, health URL, SLO, runbook, rollback, backup policy and escalation route before it is onboarded to a shared server.
