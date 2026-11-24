# Incident runbook

Use this for an application outage, elevated latency, resource pressure, or a suspected data issue. Record times in UTC and keep one incident owner/coordinator.

## 1. Confirm and scope

1. Open the Grafana **Server Operations Overview** dashboard.
2. Check Prometheus targets at `http://127.0.0.1:9090/targets` and active alert expressions at `http://127.0.0.1:9090/alerts`.
3. Run `./ops/probe-urls.sh` from the project directory; compare external checks with internal service health.
4. Identify affected application(s), region/network, start time, user impact, and whether the database is involved.
5. Start an incident record using `docs/INCIDENT-TEMPLATE.md`.

## 2. Collect evidence before changing anything

```bash
docker compose ps
docker compose logs --since=30m --tail=500 web api postgres
docker stats --no-stream
df -h
free -h
sudo journalctl -u docker --since '30 minutes ago' --no-pager
```

Do not run `docker system prune`, delete volumes, or restart PostgreSQL as a first reaction. Those actions can remove useful evidence or data.

## 3. Common recovery paths

### Nginx or website is down

```bash
docker compose ps web
docker compose logs --tail=200 web
docker compose exec web nginx -t
docker compose restart web
curl -fsS http://127.0.0.1:${WEB_PORT:-8080}/health
```

### API is unhealthy

```bash
docker compose ps api
docker compose logs --tail=300 api
curl -i http://127.0.0.1:${WEB_PORT:-8080}/api/health
```

Check whether the failure is an app process issue, DB connectivity issue, configuration error, or a dependency outage. Do not mask a failed readiness check by changing it to always return HTTP 200.

### PostgreSQL is unhealthy

```bash
docker compose ps postgres
docker compose logs --tail=300 postgres
docker compose exec postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
docker volume ls
```

Protect the persistent volume. Before a risky database repair or migration, take a verified backup and get approval from the database/application owner. A container restart does not normally remove a named volume, but volume deletion does.

### Disk pressure

```bash
df -h
docker system df
docker compose logs --disk-usage
```

Identify the filesystem and the largest safe-to-remove files. Check log rotation, image cache, backups, database growth and application upload directories. Never delete PostgreSQL data or the only backup to free space.

### CPU or memory pressure

```bash
docker stats --no-stream
ps aux --sort=-%cpu | head -20
ps aux --sort=-%mem | head -20
```

Correlate the resource spike with request rate, deployments, scheduled jobs and database connections. Apply a short-term mitigation only after recording evidence; then create a follow-up for root cause.

## 4. Recovery and validation

1. Make one controlled change at a time.
2. Check container health and the public/internal HTTP probe.
3. Verify the primary user journey, not only that the homepage responds.
4. Confirm DB writes/reads with the application owner where relevant.
5. Watch metrics for at least 10–15 minutes after recovery.
6. Communicate current status, impact, mitigation, and next update time to the team.

## 5. Close and learn

- Save timestamps, relevant logs, dashboard snapshots, and deployment commit.
- Record root cause separately from the trigger and detection gap.
- Create named corrective actions with owners and due dates.
- Update this runbook if a new recovery step was validated.
- Do not declare full resolution until the affected workflow has been verified.
