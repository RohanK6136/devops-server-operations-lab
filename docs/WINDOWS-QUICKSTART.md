# Windows quick start — PowerShell 5.1

This project is a local learning lab. The Windows scripts are designed for Windows PowerShell 5.1 and do not require PowerShell 7.

## 1. Choose one Docker engine for the lab

The simplest Windows setup is Docker Desktop using its Linux-container engine and WSL 2 backend. The commands use the Docker context already selected by Docker Desktop.

Multipass is useful for separate Ubuntu Server administration practice, but it is a separate virtual machine and is not automatically the Docker engine used by the Windows Docker CLI. Starting a Multipass VM does not start Docker Desktop or make its containers available to the current Docker context.

Inspect the Windows environment:

    .\ops\windows-preflight.ps1

The script records evidence under the evidence folder. It checks the Docker CLI and daemon separately, Docker contexts, Compose, Docker Desktop service/process, WSL 2, optional Multipass status and lab ports.

If Docker Desktop is installed but not running, start it from the Windows Start menu and wait for the Docker Engine status to show Running. You may also use:

    .\ops\windows-preflight.ps1 -StartDockerDesktop

This starts the Docker Desktop application only. Wait for the engine and rerun the preflight.

A message such as "failed to connect to the docker API ... dockerDesktopLinuxEngine ... The system cannot find the file specified" means the CLI cannot reach the selected Docker Desktop engine. It does not by itself indicate a defect in the Compose application.

## 2. Configure local credentials once

From the repository root:

    .\ops\windows-setup.ps1

The setup script generates two different cryptographically random local passwords, writes them to .env without printing them, and checks Compose syntax when the Docker CLI is installed. It will not overwrite an existing .env. Do not commit .env, share its contents in screenshots, or use company/production credentials in this lab.

## 3. Start the core application services

    .\ops\windows-setup.ps1
    .\ops\windows-lab.ps1 -Action Up
    .\ops\windows-lab.ps1 -Action Status
    .\ops\windows-lab.ps1 -Action Health

The core profile starts the main website, API, second website and PostgreSQL. It keeps the monitoring stack stopped initially to reduce laptop memory use.

The two websites share one Nginx entry point:

| Service | Address |
|---|---|
| Main website / Nginx | http://127.0.0.1:8080 |
| Second independent website | http://127.0.0.1:8080/second/ |
| Main website health | http://127.0.0.1:8080/health |
| API readiness through Nginx | http://127.0.0.1:8080/api/health |

Only Nginx publishes the website port. The API, second website and database remain on private Docker networks.

## 4. Start monitoring when the core stack is healthy

    .\ops\windows-lab.ps1 -Action MonitoringUp
    .\ops\windows-lab.ps1 -Action Status

The monitoring profile adds Prometheus, Grafana, Uptime Kuma, Node Exporter, cAdvisor, Blackbox Exporter and the PostgreSQL exporter.

| Monitoring service | Address |
|---|---|
| Prometheus | http://127.0.0.1:9090 |
| Grafana | http://127.0.0.1:3000 |
| Uptime Kuma | http://127.0.0.1:3001 |

Grafana credentials are the values set in .env. Uptime Kuma asks you to create its administrator on first visit. These interfaces bind to localhost by default.

## 5. Demonstrate a controlled application incident

The recommended manager demonstration is a single command:

    .\ops\windows-incident-demo.ps1

It verifies the baseline first, stops only the local API container, confirms the main and second websites remain available, checks that the API route returns a 5xx response, restarts the API, verifies recovery, and saves a timestamped transcript under evidence. It attempts to restart the API during cleanup if a check fails.

For manual control, only do the following against the local lab:

    .\ops\windows-lab.ps1 -Action StopApi
    .\ops\windows-lab.ps1 -Action Health
    .\ops\windows-lab.ps1 -Action Logs
    .\ops\windows-lab.ps1 -Action StartApi
    .\ops\windows-lab.ps1 -Action Status

The API stop is intentional. The health command should show the API route failing while the main Nginx and second website health endpoints remain available. The start command waits up to 60 seconds for all application health endpoints to recover.

To stop containers without deleting persistent volumes:

    .\ops\windows-lab.ps1 -Action StopAll

Do not run docker compose down -v for this learning lab unless you deliberately intend to delete its named database and monitoring volumes.

## 6. Understand what host metrics represent

When this Compose stack runs through Docker Desktop's Linux engine, Node Exporter and cAdvisor observe the Docker Linux environment and its containers. They do not provide a complete view of Windows host CPU/memory/disk. For genuine Ubuntu VM host metrics, install/run Node Exporter in the Ubuntu VM and configure Prometheus to scrape that VM over a private network.

## 7. Evidence to keep for the manager demo

Keep these artefacts in the local evidence folder:

- windows-preflight-*.txt — confirms the local toolchain and engine status.
- baseline-*.txt — container status, resource usage, HTTP health checks and logs.
- incident-*.txt — API stop, failed health probe, recovery and final status.
- Grafana screenshots showing API, host and container metrics.
- A short screen recording showing both websites, the failure and recovery.

A successful GitHub CI run validates code/tests and Compose syntax; it does not prove Docker Desktop is running on the laptop or that the local environment has been exercised.
