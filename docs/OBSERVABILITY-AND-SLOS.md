# Monitoring, observability and service objectives

## Monitoring vs observability

Monitoring answers known questions: is a target up, is CPU high, is disk nearly full? Observability helps investigate unfamiliar behaviour by correlating metrics, logs and traces. This lab starts with health checks, metrics and container logs. Distributed tracing and central log aggregation are later increments.

## Signals

- **Metrics:** Prometheus scrapes the API, PostgreSQL exporter, Node Exporter, cAdvisor and Blackbox Exporter.
- **Logs:** Docker JSON logs have size/file rotation. Use `docker compose logs` for this lab. A multi-app production server should send logs to a central searchable store with access control and retention.
- **Traces:** not yet configured. Add OpenTelemetry only after identifying service boundaries and a storage/backend choice.

## Health endpoint semantics

- `/health` is liveness: the process is alive and can respond.
- `/health/ready` is readiness: the process can reach its configured PostgreSQL TCP dependency.
- `/api/health` is a compatibility alias for readiness.
- `/metrics` exposes Prometheus metrics with bounded route labels. It deliberately avoids raw URL labels to prevent unbounded cardinality.

A TCP readiness probe is not a full SQL query and does not prove that all database operations work. The PostgreSQL exporter provides a separate database-level signal.

## Initial SLO worksheet

Do not invent an SLA for a service. Agree the following with the application owner and leadership for each critical service:

| Item | Decision to record |
|---|---|
| Service | Name, owner, criticality, public URL |
| User journey | The specific transaction that matters |
| Availability SLI | Successful eligible requests / eligible requests |
| Latency SLI | Proportion of eligible requests below the agreed threshold |
| Error SLI | Failed eligible requests / eligible requests |
| SLO target | Agreed target and measurement window |
| Exclusions | Planned maintenance, test traffic, upstream dependency? |
| Alert policy | Fast burn, slow burn, owner and escalation route |
| Error budget | Allowed unreliability during the SLO window |

An HTTP 200 homepage alone is not proof that checkout, login, upload, or database-backed features work. Add journey-level synthetic probes for critical user actions in a controlled test environment.

## Alert hygiene

- Page only when a user-impacting or imminent issue needs human action.
- Group duplicate alerts by application and incident.
- Include the affected URL/service, first-seen time, severity, runbook link and owner.
- Test the notification route by sending a known test alert.
- Review noisy alerts and thresholds after incidents; do not silence alerts without recording why and for how long.
