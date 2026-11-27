[CmdletBinding()]
param([switch]$StartDockerDesktop)

$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$EvidenceDir = Join-Path $RepoRoot "evidence"
if (-not (Test-Path $EvidenceDir)) { New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null }
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$TranscriptPath = Join-Path $EvidenceDir "windows-preflight-$Stamp.txt"
$EngineReady = $false

Start-Transcript -Path $TranscriptPath -Force | Out-Null
try {
    Set-Location $RepoRoot
    Write-Host ""
    Write-Host "=== WINDOWS / DEVOPS LAB PREFLIGHT ===" -ForegroundColor Cyan
    Write-Host ("Captured: {0}" -f (Get-Date -Format o))
    Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion)
    Write-Host ("Computer: {0}" -f $env:COMPUTERNAME)
    Write-Host ("Repository: {0}" -f $RepoRoot)

    Write-Host ""
    Write-Host "=== DOCKER CLI ===" -ForegroundColor Cyan
    $DockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $DockerCommand) {
        Write-Host "Docker CLI was not found in PATH." -ForegroundColor Red
    }
    else {
        & docker --version
        Write-Host ""
        Write-Host "Docker contexts:"
        & docker context ls
        Write-Host ""
        Write-Host "Active Docker context:"
        & docker context show
        Write-Host ""
        Write-Host "Docker Engine connectivity:"
        $DockerInfo = & docker info --format "Server={{.ServerVersion}} | OS={{.OperatingSystem}} | CPUs={{.NCPU}} | Memory={{.MemTotal}}" 2>&1
        $DockerInfoExitCode = $LASTEXITCODE
        $DockerInfo | ForEach-Object { Write-Host $_ }
        if ($DockerInfoExitCode -eq 0) {
            $EngineReady = $true
            Write-Host "Docker Engine is reachable." -ForegroundColor Green
        }
        else {
            Write-Host "Docker CLI is present, but the Docker Engine is not reachable." -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "Docker Compose:"
        & docker compose version
    }

    Write-Host ""
    Write-Host "=== DOCKER DESKTOP ===" -ForegroundColor Cyan
    $DockerService = Get-Service -Name "com.docker.service" -ErrorAction SilentlyContinue
    if ($null -ne $DockerService) {
        $DockerService | Select-Object Name, Status, StartType | Format-Table -AutoSize
    }
    else { Write-Host "Docker Desktop Windows service was not found." }

    $DockerDesktopPath = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (Test-Path $DockerDesktopPath) {
        Write-Host ("Docker Desktop executable found: {0}" -f $DockerDesktopPath)
        $DockerDesktopProcess = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
        if ($null -eq $DockerDesktopProcess) {
            Write-Host "Docker Desktop UI process is not running."
            if ($StartDockerDesktop) {
                Write-Host "Starting Docker Desktop UI. Wait until its engine reports Running, then rerun this script."
                Start-Process -FilePath $DockerDesktopPath
            }
        }
        else { Write-Host "Docker Desktop UI process is running." }
    }
    else { Write-Host "Docker Desktop executable was not found at the standard installation path." }

    Write-Host ""
    Write-Host "=== WSL2 ===" -ForegroundColor Cyan
    $WslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -ne $WslCommand) {
        & wsl.exe --status
        & wsl.exe --list --verbose
    }
    else { Write-Host "wsl.exe was not found." }

    Write-Host ""
    Write-Host "=== MULTIPASS (OPTIONAL) ===" -ForegroundColor Cyan
    $MultipassCommand = Get-Command multipass.exe -ErrorAction SilentlyContinue
    if ($null -ne $MultipassCommand) {
        & multipass.exe version
        & multipass.exe list
    }
    else { Write-Host "Multipass CLI was not found. This is not an error if Docker Desktop is the selected lab engine." }

    Write-Host ""
    Write-Host "=== LOCAL LAB PORTS ===" -ForegroundColor Cyan
    foreach ($Port in @(8080, 9090, 3000, 3001)) {
        $PortResult = Test-NetConnection -ComputerName "127.0.0.1" -Port $Port -WarningAction SilentlyContinue
        Write-Host ("127.0.0.1:{0} reachable: {1}" -f $Port, $PortResult.TcpTestSucceeded)
    }

    Write-Host ""
    Write-Host "=== RESULT ===" -ForegroundColor Cyan
    if ($EngineReady) {
        Write-Host "PASS: Docker Engine is available. Run ops\windows-lab.ps1 -Action Status." -ForegroundColor Green
    }
    else {
        Write-Host "BLOCKED: Docker Engine is unavailable. Open Docker Desktop and wait until the engine is Running." -ForegroundColor Yellow
        Write-Host "Then rerun: .\ops\windows-preflight.ps1"
        Write-Host "Optional: .\ops\windows-preflight.ps1 -StartDockerDesktop"
    }
    Write-Host ("Evidence saved to: {0}" -f $TranscriptPath)
}
finally { Stop-Transcript | Out-Null }

if (-not $EngineReady) { exit 2 }
exit 0
