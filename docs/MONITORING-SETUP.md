# Multi-application uptime and alert setup

## Uptime Kuma — application availability and team notification

1. Start the stack and open `http://127.0.0.1:3001` through a local session or SSH tunnel.
2. Create the initial administrator account. Enable two-factor authentication after setup.
3. Add one monitor for every inventory row with a real public health URL. Use HTTP(s) for application checks and TCP for ports that should be reachable only from an approved network.
4. Use a 60-second interval initially; adjust critical applications and network constraints with the team.
5. Add the approved team notification integration (for example, company email SMTP, Teams/Slack webhook, Telegram, or another supported channel).
6. Use the built-in test notification and confirm that the intended team channel receives it.
7. Simulate an outage in staging, verify one alert is received, restore the service, and verify the recovery notification.
8. Enable a status page only if the business owner approves publishing service health externally.

Uptime Kuma supports HTTP/TCP/DNS and other monitor types, as well as multiple notification integrations. The official project installation guide recommends a persistent local volume for `/app/data`; network filesystems such as NFS are not supported for its SQLite data. Do not put the Uptime Kuma data volume on NFS.

## Grafana — resource and application alerts

1. Open Grafana → **Alerting** → **Contact points** → **New contact point**.
2. Select a destination approved by the company (SMTP, Teams/Slack webhook, or another configured integration). Enter only approved credentials in the protected Grafana UI/secret store; never commit them to this repository.
3. Use **Test** and ask the recipient to confirm arrival.
4. Create Grafana-managed alert rules using the Prometheus data source and queries below. Set evaluation periods to prevent noisy one-sample alerts.
5. Create a notification policy that routes the `severity` label to the agreed team contact point.

Suggested initial PromQL expressions (review thresholds against a measured baseline):

```promql
# Host CPU %
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100

# Host memory %
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Host root filesystem usage %
(1 - min(node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"})) * 100

# Down Prometheus targets
up == 0

# Failed HTTP probes
probe_success == 0

# PostgreSQL exporter connection state
pg_up == 0
```

Recommended starting evaluation windows: target down for 2 minutes, HTTP probe failure for 1 minute, CPU above 80% for 10 minutes, memory above 85% for 5 minutes. Tune after observing normal traffic and maintenance windows.

## Registering 60–160 applications

- Use `docs/application-inventory-template.csv` as the source inventory.
- Add each service's health URL as an Uptime Kuma monitor and assign a team owner/tag.
- Add critical application URLs to `monitoring/prometheus/prometheus.yml` under the `blackbox-web` target list when metric-based probes are needed; keep the URL list managed in source control.
- Group related applications by team/domain in Uptime Kuma; use consistent names such as `prod | recruitment-api | health`.
- Do not monitor only the homepage when the critical journey is login, checkout, candidate submission, or another API-backed flow. Add a dedicated safe health endpoint or synthetic transaction that does not modify real customer records.

## Security note

Uptime Kuma and Grafana are bound to `127.0.0.1` by default. Access them through a VPN/SSH tunnel or an approved authenticated TLS proxy. Use a separate administrator account, enable MFA where supported, back up Uptime Kuma's local data volume, and restrict access to notification credentials.
