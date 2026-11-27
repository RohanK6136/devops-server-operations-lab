# Operations API and PostgreSQL event journal

The API is a small Node.js service used to demonstrate liveness/readiness, Prometheus metrics, and real persistence to PostgreSQL.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | /health | Liveness; confirms the API process can respond |
| GET | /health/ready | Readiness; runs SELECT 1 against PostgreSQL |
| GET | /api/health | Compatibility alias for readiness |
| GET | /api/info | Runtime details; does not return credentials |
| GET | /metrics | Prometheus counters and request-latency histogram |
| GET | /api/events?limit=10 | Lists the most recent operational events |
| POST | /api/events | Stores a new operational event in PostgreSQL |

The API creates public.lab_events and an index on created_at when it starts. Table creation is idempotent. The application uses a bounded connection pool and parameterised SQL for event writes and reads.

## Create an event from PowerShell 5.1

~~~powershell
$payload = @{
    eventType = 'backup-drill'
    message = 'Verified sample backup and restore'
    metadata = @{
        source = 'manager-demo'
        scenario = 'postgres-restore'
    }
} | ConvertTo-Json -Depth 4

Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/events' -Method Post -ContentType 'application/json' -Body $payload

Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/events?limit=10'
~~~

## Validation and safety

- eventType is limited to 1–48 letters, digits, underscores or hyphens.
- message is required and limited to 500 characters.
- metadata must be a JSON object.
- Request bodies are capped at 4 KiB.
- The GET limit is clamped between 1 and 100.
- SQL values are passed as parameters, not concatenated into SQL.
- Event messages and metadata may be displayed in the browser; use only harmless demo text.
- This learning API has no user authentication. It is exposed only through the localhost-bound demo Nginx port. Do not expose it publicly or use it for company/customer data.

## Backup and restore proof

The CI smoke test writes a backup-drill event, reads it through the API, takes a custom-format PostgreSQL dump, restores the dump into a uniquely named temporary database, and verifies that the event table and at least one row were restored. The temporary database is dropped after the check; the source database is not overwritten.
