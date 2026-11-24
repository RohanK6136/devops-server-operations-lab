# Server Operations & SRE Lab

A free/open-source starter lab for application observability, uptime checks, infrastructure metrics, PostgreSQL backups and restore verification, and operational runbooks.

## Scope

This repository is a standalone learning and proof-of-concept lab. It is not deployed to the company server and must be reviewed against actual host capacity, network policy, and backup retention requirements before production use.

## Quick start

1. Copy `.env.example` to `.env` and replace all example credentials with strong local secrets.
2. Review `docker-compose.yml`, firewall requirements, volume mounts and exposed ports.
3. Start the lab with `docker compose up -d --build`.
4. Open the web dashboard and monitoring services only from trusted networks; do not expose Prometheus, Grafana or exporters publicly without authentication and network controls.
5. Read `docs/MONITORING-SETUP.md` and `docs/DATABASE-BACKUP-RESTORE.md` before using backup scripts.

## Validation

Run API tests with `cd api && npm test`. Shell scripts can be syntax-checked using `bash -n ops/*.sh`.

## Important

No company credentials, production data, or real customer information belong in this repository. Use a private production configuration and a separate secret manager for deployment.
