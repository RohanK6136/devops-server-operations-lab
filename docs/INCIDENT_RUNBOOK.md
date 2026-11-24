# Incident Runbook: API unavailable

## Symptoms

- Dashboard loads, but API health check fails.
- `/api/health` returns a gateway error.
- API container may be stopped, restarting, or unhealthy.

## Triage

1. Check container state: `docker compose ps`.
2. Inspect API logs: `docker compose logs --tail=100 api`.
3. Inspect recent events: `docker compose events --since 10m`.
4. Check resource pressure: `docker stats`.
5. Validate configuration: `docker compose config`.

## Recovery

If the service is intentionally stopped:

```bash
docker compose start api
```

If it is running but unhealthy, inspect logs before restarting:

```bash
docker compose restart api
docker compose ps
curl -i http://localhost:8080/api/health
```

## Close-out notes

Record:
- Start and end time of incident.
- User-visible impact.
- Root cause (confirmed, not guessed).
- Recovery action.
- Follow-up prevention task.

Do not delete volumes or run destructive cleanup commands during an incident.
