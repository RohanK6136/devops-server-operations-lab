# Windows quick start — PowerShell 5.1

This project is a local learning lab. The Windows scripts are designed for Windows PowerShell 5.1 and do not require PowerShell 7.

## 1. Choose one Docker engine for the lab

The simplest Windows setup is Docker Desktop using its Linux-container engine and WSL 2 backend. The commands below use the Docker context already selected by Docker Desktop.

Multipass is useful for separate Ubuntu Server administration practice, but it is a separate virtual machine and is not automatically the Docker engine used by the Windows Docker CLI. Do not assume that starting a Multipass VM starts Docker Desktop or makes its containers available to the current Docker context.

To inspect the Windows environment:

    .\ops\windows-preflight.ps1

The script records evidence under the evidence folder. It checks the Docker CLI and daemon separately, Docker contexts, Compose, Docker Desktop service/process, WSL 2, optional Multipass status and the lab ports.

If Docker Desktop is installed but not running, start it from the Windows Start menu and wait for the Docker Engine status to show Running. You may also use:

    .\ops\windows-preflight.ps1 -StartDockerDesktop

This starts the Docker Desktop application only. It does not bypass the normal startup process; wait for the engine and rerun the preflight.

A message such as "failed to connect to the docker API ... dockerDesktopLinuxEngine ... The system cannot find the file specified" means the CLI cannot reach the selected Docker Desktop engine. It does not by itself indicate a defect in the Compose application.

## 2. Configure local credentials once

From the repository root:

    Copy-Item .env.example .env
    notepad .env

Replace both password placeholders with different, strong local-only passwords. Do not commit .env, share its contents in screenshots, or use company/production credentials in this lab.

## 3. Start and inspect the stack

    .\ops\windows-lab.ps1 -Action Up
    .\ops\windows-lab.ps1 -Action Status
    .\ops\windows-lab.ps1 -Action Health

The default local endpoints are:

| Service | Address |
|---|---|
| Web / Nginx | http://127.0.0.1:8080 |
| Prometheus | http://127.0.0.1:9090 |
| Grafana | http://127.0.0.1:3000 |
| Uptime Kuma | http://127.0.0.1:3001 |

Grafana credentials are the values set in .env. Uptime Kuma asks you to create its administrator on first visit. The dashboards and monitoring UIs bind to localhost by default.

## 4. Demonstrate a controlled incident

Only do this against the local lab:

    .\ops\windows-lab.ps1 -Action StopApi
    .\ops\windows-lab.ps1 -Action Health
    .\ops\windows-lab.ps1 -Action Logs
    .\ops\windows-lab.ps1 -Action StartApi
    .\ops\windows-lab.ps1 -Action Status

The API stop is intentional. The health command should show the impact while the API is stopped; the start command waits up to 60 seconds for the web and API health endpoints to recover. Save the terminal output or record the screen for the demo.

To stop containers without deleting persistent volumes:

    .\ops\windows-lab.ps1 -Action StopAll

Do not run docker compose down -v for this learning lab unless you deliberately intend to delete its named database and monitoring volumes.

## 5. Understand what host metrics represent

When this Compose stack runs through Docker Desktop's Linux engine, Node Exporter and cAdvisor observe the Docker Linux environment and its containers. They do not provide a complete view of Windows host CPU/memory/disk. For genuine Ubuntu VM host metrics, install/run Node Exporter in the Ubuntu VM and configure Prometheus to scrape that VM over a private network.

## 6. Evidence to keep for the manager demo

Keep these artefacts in the local evidence folder:

- windows-preflight-*.txt — confirms the local toolchain and engine status.
- baseline-*.txt — container status, resource usage, HTTP health checks and logs.
- incident-*.txt — API stop, failed health probe, recovery and final status.
- Grafana screenshots showing API, host and container metrics.
- A short screen recording showing the incident and recovery.

A successful GitHub CI run validates code/tests and Compose syntax; it does not prove that Docker Desktop is running on your laptop or that the local environment has been exercised.
