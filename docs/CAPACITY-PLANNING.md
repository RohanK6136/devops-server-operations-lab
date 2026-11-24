# Capacity planning — initial 4 vCPU / 32 GB RAM server assumption

The meeting mentioned a server around 4 vCPU and 32 GB RAM. Treat those figures as an initial planning assumption until the machine is inspected with `./ops/collect-host-info.sh`; confirm CPU model, memory, disk type/capacity, IOPS, network bandwidth, kernel, Docker limits and swap.

## Baseline before onboarding applications

Capture at least 7 days of normal usage where possible, including business-hour peaks and scheduled jobs:

- CPU: total utilisation, load average, CPU steal (if virtualised), per-process and per-container CPU.
- Memory: available memory, working set per container, page cache, swap activity and OOM events.
- Disk: used/free space, inode availability, IOPS/latency if available, database growth, logs, uploads and backup growth.
- Network: throughput, errors/drops, concurrent connections and public ingress limits.
- Application: request rate, latency percentiles, 4xx/5xx rate, queue depth, database connection pool, job duration.

## Review triggers (initial operating thresholds; tune after baseline)

- Start a capacity review when CPU is above 60% or memory above 70% for 15 minutes during normal peak load.
- Treat CPU above 80% for 10 minutes, memory above 85% for 5 minutes, or disk usage above 85% for 10 minutes as an alert requiring investigation.
- Review immediately when swapping increases, OOM kills occur, request latency rises, 5xx errors grow, database connections approach their limit, or backup jobs no longer complete.
- Preserve operational headroom. Do not plan to run a multi-tenant server at its theoretical maximum.

## How to measure user-load impact

Do not convert “100 users”, “1,000 users” or “100,000 users” directly into a server capacity estimate. Concurrent requests, think time, request mix, cache hit rate, database work, file size, background jobs and third-party dependencies change the result.

For each application, run a controlled load test against a staging environment:

1. Define realistic journeys and request mix with the product owner.
2. Start at a low concurrency, ramp gradually, and define a stop condition.
3. Record throughput, p50/p95/p99 latency, error rate, CPU, memory, DB connections, disk and network.
4. Repeat with caching enabled/disabled and with realistic test data.
5. Identify the first saturated resource and the point where the agreed SLO is breached.
6. Keep a safety margin and forecast the next 30–90 days of growth.

Never run a high-volume load test against production without written approval and an agreed test window.

## Multi-application server strategy

- Maintain an inventory for every deployed application; assign a technical owner, business owner, criticality and support route.
- Use a reverse proxy with TLS and explicit host routing. Keep app, database and monitoring ports private.
- Give each app a separate Compose project/network and persistent volumes where required; avoid shared credentials and fixed global container names.
- Establish resource requests/limits per workload, but verify the actual host-level effect under load.
- Track aggregate headroom across all applications, not only individual container limits.
- Keep monitoring, backups and deployment tooling within their own resource budget.
- Define onboarding gates: health endpoint, logs, owner, rollback, backup/restore, monitoring, security review and runbook.

## Capacity decision log

For each review, record the measured baseline, peak, trend, SLO impact, expected growth, proposed change, cost and decision owner. Scale vertically or split workloads before sustained saturation, not after an outage.
