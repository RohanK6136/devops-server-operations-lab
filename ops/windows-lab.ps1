[CmdletBinding()]
param(
    [ValidateSet("Up", "MonitoringUp", "Status", "Health", "Logs", "StopApi", "StartApi", "StopAll")]
    [string]$Action = "Status",
    [ValidateRange(1, 1000)]
    [int]$Tail = 80
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Invoke-Compose {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    Write-Host ("docker compose {0}" -f ($Arguments -join " ")) -ForegroundColor DarkCyan
    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) { throw ("docker compose command failed with exit code {0}." -f $LASTEXITCODE) }
}

function Assert-DockerEngine {
    $null = & docker info --format "{{.ServerVersion}}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Engine is not reachable. Open Docker Desktop, wait for the engine to be Running, then rerun this command."
    }
}

function Get-WebPort {
    $Port = 8080
    $EnvFile = Join-Path $RepoRoot ".env"
    if (Test-Path $EnvFile) {
        $Match = Select-String -Path $EnvFile -Pattern "^\s*WEB_PORT\s*=\s*(\d+)\s*$" | Select-Object -First 1
        if ($null -ne $Match -and $Match.Matches.Count -gt 0) { $Port = [int]$Match.Matches[0].Groups[1].Value }
    }
    return $Port
}

function Test-AppHealth {
    param([int]$Port)
    $AllHealthy = $true
    $Urls = @(
        "http://127.0.0.1:$Port/health",
        "http://127.0.0.1:$Port/api/health",
        "http://127.0.0.1:$Port/second/health"
    )
    foreach ($Url in $Urls) {
        try {
            $Response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 5 -UseBasicParsing
            Write-Host ("[{0}] HTTP {1}" -f $Url, [int]$Response.StatusCode) -ForegroundColor Green
            Write-Host $Response.Content
            if ([int]$Response.StatusCode -lt 200 -or [int]$Response.StatusCode -ge 300) { $AllHealthy = $false }
        }
        catch {
            Write-Host ("[{0}] FAILED: {1}" -f $Url, $_.Exception.Message) -ForegroundColor Red
            $AllHealthy = $false
        }
    }
    return $AllHealthy
}

try {
    Assert-DockerEngine
    $WebPort = Get-WebPort
    switch ($Action) {
        "Up" {
            if (-not (Test-Path (Join-Path $RepoRoot ".env"))) {
                throw ".env is missing. Copy .env.example to .env and replace the example passwords before starting the stack."
            }
            Invoke-Compose -Arguments @("up", "-d", "--build")
            Invoke-Compose -Arguments @("ps")
            Write-Host "Core web, API, second-site and database services started. Run -Action Health to verify."
            Write-Host "Add monitoring later with -Action MonitoringUp."
        }
        "MonitoringUp" {
            if (-not (Test-Path (Join-Path $RepoRoot ".env"))) {
                throw ".env is missing. Copy .env.example to .env and replace the example passwords before starting the stack."
            }
            Invoke-Compose -Arguments @("--profile", "monitoring", "up", "-d", "--build")
            Invoke-Compose -Arguments @("ps")
            Write-Host "Monitoring profile requested. Grafana, Prometheus and Uptime Kuma should become available after their health/startup checks."
        }
        "Status" {
            Invoke-Compose -Arguments @("ps")
            Write-Host ""
            Write-Host "Resource usage:"
            & docker stats --no-stream
            if ($LASTEXITCODE -ne 0) { throw "docker stats failed." }
        }
        "Health" {
            if (-not (Test-AppHealth -Port $WebPort)) { throw "One or more application health checks failed." }
            Write-Host "PASS: main website, API and second website health endpoints returned successful responses." -ForegroundColor Green
        }
        "Logs" { Invoke-Compose -Arguments @("logs", "--tail", "$Tail", "web", "api", "site-two", "postgres") }
        "StopApi" {
            Write-Warning "This intentionally stops only the API container to simulate an application incident."
            Invoke-Compose -Arguments @("stop", "api")
            Write-Host "API stop command completed. Run -Action Health to observe the impact."
        }
        "StartApi" {
            Invoke-Compose -Arguments @("start", "api")
            Write-Host "Waiting up to 60 seconds for the application health endpoints..."
            $Recovered = $false
            for ($Attempt = 1; $Attempt -le 12; $Attempt++) {
                Start-Sleep -Seconds 5
                if (Test-AppHealth -Port $WebPort) { $Recovered = $true; break }
                Write-Host ("Recovery check {0}/12: not healthy yet." -f $Attempt) -ForegroundColor Yellow
            }
            if (-not $Recovered) { throw "API did not recover within 60 seconds. Inspect -Action Logs and docker compose ps." }
            Write-Host "PASS: application health checks recovered." -ForegroundColor Green
        }
        "StopAll" {
            Write-Warning "Stopping containers only. Named database and monitoring volumes are preserved."
            Invoke-Compose -Arguments @("stop")
            Write-Host "All services stopped. No volumes were deleted."
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
exit 0
