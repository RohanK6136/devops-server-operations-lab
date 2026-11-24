# Deploying this lab to the company Docker server

The deploy workflow is deliberately manual. A push to GitHub runs CI but does not change the company server. A production deploy occurs only when an authorised maintainer manually runs **Actions → deploy-server-operations-lab → Run workflow** and checks `confirm_deploy`.

## Server prerequisites

- A Linux host with Docker Engine and Docker Compose v2 installed.
- A dedicated deployment user with SSH key authentication and permission to run Docker Compose (usually membership of the `docker` group; treat Docker group membership as highly privileged).
- The deployment directory `/opt/server-operations-lab` or `/srv/server-operations-lab`, owned by that deployment user and writable by it.
- A pre-created `.env` file in that directory containing strong, unique PostgreSQL and Grafana credentials. It must not be committed to Git.
- Confirmed host SSH public-key fingerprint, network/firewall access, sufficient disk space, and a backup/rollback plan.

Do not enable the cAdvisor privileged container on a production server until the infrastructure owner has reviewed its host mounts and privilege requirements.

## GitHub Actions secrets and variable

Under **Repository → Settings → Secrets and variables → Actions**, configure:

| Name | Type | Value |
|---|---|---|
| `SRE_SERVER_HOST` | Secret | Server DNS name or IP address |
| `SRE_SERVER_USER` | Secret | Dedicated deploy username |
| `SRE_SERVER_SSH_PRIVATE_KEY` | Secret | Private SSH key for the deploy user; never commit or paste it into chat |
| `SRE_SERVER_KNOWN_HOSTS` | Secret | Pre-verified `known_hosts` line for this server; do not trust an unverified `ssh-keyscan` result |
| `SRE_SERVER_DEPLOY_PATH` | Variable | Optional; `/opt/server-operations-lab` or `/srv/server-operations-lab` |

The matching public key must already be in the deployment user's `~/.ssh/authorized_keys` on the server. The deploy user must be able to run `docker compose` without an interactive password prompt.

## Run a deployment

1. Confirm server prerequisites, `.env`, SSH firewall rule and the team's maintenance window.
2. Open the repository's **Actions** tab.
3. Select **deploy-server-operations-lab** and click **Run workflow**.
4. Select `main`, set `confirm_deploy` to `true`, and start the run.
5. Inspect the workflow output and verify every container health state on the host.
6. Open Grafana/Uptime Kuma only through an approved VPN/SSH tunnel or authenticated TLS proxy. These interfaces bind to localhost by default.

The workflow copies source files but deliberately preserves the server's `.env` and `backups/` directory. It is not a substitute for backup verification or a rollback plan. It does not configure DNS, TLS, firewall rules, alert destinations, or off-host backup storage.
