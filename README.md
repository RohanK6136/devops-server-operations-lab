# Server Operations & SRE Lab

A free/open-source local lab for practical server administration, multi-site reverse proxying, application observability, uptime checks, a PostgreSQL-backed operational event API, backups and data-bearing restore verification.

## Scope

This repository is a standalone learning and proof-of-concept lab. It is not deployed to the company server and must be reviewed against actual host capacity, network policy, security requirements and backup retention before production use.

## Quick start

1. On Windows, start Docker Desktop and wait for its Linux engine to show **Running**. See [Windows quick start](docs/WINDOWS-QUICKSTART.md).
2. On Windows, run .\\ops\\windows-setup.ps1 to generate local-only credentials. On Linux, copy .env.example to .env and replace both password placeholders with different strong passwords. Never commit .env.
3. Start the core lab: docker compose up -d --build.
4. Verify the main site at http://127.0.0.1:8080 and the second independent site at http://127.0.0.1:8080/second/. Both are routed through Nginx.
5. Verify persisted event records through GET/POST /api/events; then start monitoring when core services are healthy: docker compose --profile monitoring up -d.
6. Open Grafana at http://127.0.0.1:3000, Prometheus at http://127.0.0.1:9090, Alertmanager at http://127.0.0.1:9093, Mailpit at http://127.0.0.1:8025 and Uptime Kuma at http://127.0.0.1:3001. Keep these interfaces on trusted/local access only. Alert emails are captured locally by Mailpit and are not sent externally.
7. Read docs/MONITORING-SETUP.md and docs/DATABASE-BACKUP-RESTORE.md before using backup scripts.

## Windows operator commands

PowerShell 5.1 preflight and lab commands are provided:

    .\ops\windows-preflight.ps1
    .\ops\windows-lab.ps1 -Action Up
    .\ops\windows-lab.ps1 -Action MonitoringUp
    .\ops\windows-lab.ps1 -Action Health
    .\ops\windows-incident-demo.ps1

The preflight distinguishes an installed Docker CLI from a reachable Docker Engine. The setup script creates different local secrets without printing them. The lab script provides status, logs, controlled API recovery and a safe stop that preserves named volumes. The incident demo captures a timestamped failure-and-recovery transcript and, when monitoring is running, checks for both firing and resolved alert emails in Mailpit. The API writes validated sample events to PostgreSQL so the backup/restore drill can verify a real row, not just an empty archive.

## Validation

Run API tests with cd api; npm test. GitHub Actions also validates the Compose configuration and builds the local web/API images. Shell scripts can be syntax-checked using bash -n ops/*.sh.

## Important

No company credentials, production data, or real customer information belong in this repository. The monitoring containers are for a local proof of concept only; assess privileged host mounts, resource limits, networking, authentication, alert routing and off-host backups before any production use.
