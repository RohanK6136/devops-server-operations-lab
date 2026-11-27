[CmdletBinding()]
param(
    [ValidateRange(10, 180)]
    [int]$RecoveryTimeoutSeconds = 60,
    [ValidateRange(30, 240)]
    [int]$AlertTimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$EvidenceDir = Join-Path $RepoRoot "evidence"
if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
}
$Stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$TranscriptPath = Join-Path $EvidenceDir "incident-demo-$Stamp.txt"
$TranscriptStarted = $false
$ApiStopped = $false
$ExitCode = 0
$WebPort = 8080
Set-Location $RepoRoot

function Invoke-Compose {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    Write-Host ("docker compose {0}" -f ($Arguments -join " ")) -ForegroundColor DarkCyan
    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ("docker compose command failed with exit code {0}." -f $LASTEXITCODE)
    }
}

function Get-HttpStatus {
    param([Parameter(Mandatory = $true)][string]$Url)
    try {
        $Response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 5 -UseBasicParsing
        return [int]$Response.StatusCode
    }
    catch {
        if ($null -ne $_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }
        return 0
    }
}

function Assert-Http200 {
    param([Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$Label)
    $Status = Get-HttpStatus -Url $Url
    Write-Host ("{0}: HTTP {1}" -f $Label, $Status)
    if ($Status -ne 200) {
        throw ("{0} expected HTTP 200 but received HTTP {1}." -f $Label, $Status)
    }
}

function Get-MailpitMessages {
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:8025/api/v1/messages?limit=50" -Method Get -TimeoutSec 5
    }
    catch {
        return $null
    }
}

function Wait-MailpitNotification {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Firing", "Resolved")]
        [string]$State,
        [Parameter(Mandatory = $true)]
        [string[]]$KnownMessageIds,
        [ValidateRange(10, 240)]
        [int]$TimeoutSeconds = 120
    )

    $Attempts = [Math]::Ceiling($TimeoutSeconds / 5)
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        $Mailbox = Get-MailpitMessages
        if ($null -ne $Mailbox -and $null -ne $Mailbox.messages) {
            foreach ($Message in $Mailbox.messages) {
                $MessageId = [string]$Message.ID
                if ([string]::IsNullOrWhiteSpace($MessageId) -or $KnownMessageIds -contains $MessageId) {
                    continue
                }

                $Summary = ([string]$Message.Subject) + " " + ([string]$Message.Snippet)
                if ($Summary -notmatch "PublicProbeFailed") {
                    continue
                }

                if ($State -eq "Firing" -and $Summary -match "(?i)resolved") {
                    continue
                }
                if ($State -eq "Resolved" -and $Summary -notmatch "(?i)resolved") {
                    continue
                }

                Write-Host ("PASS: {0} alert email captured by Mailpit: {1}" -f $State, [string]$Message.Subject) -ForegroundColor Green
                return $MessageId
            }
        }

        Write-Host ("Waiting for {0} notification: {1}/{2}" -f $State, $Attempt, $Attempts)
        Start-Sleep -Seconds 5
    }

    throw ("Mailpit did not receive a new {0} PublicProbeFailed notification within {1} seconds. Inspect Prometheus /alerts and Alertmanager logs." -f $State, $TimeoutSeconds)
}

function Assert-LocalEnvironment {
    $EnvPath = Join-Path $RepoRoot ".env"
    if (-not (Test-Path $EnvPath)) {
        throw ".env is missing. Run .\ops\windows-setup.ps1 first."
    }
    $Text = Get-Content -Path $EnvPath -Raw
    if ($Text -match "REPLACE_WITH_") {
        throw ".env still contains example credentials. Run .\ops\windows-setup.ps1 or replace both passwords."
    }
    $PostgresMatch = [regex]::Match($Text, "(?m)^\s*POSTGRES_PASSWORD\s*=\s*([^\r\n]+)\s*$")
    $GrafanaMatch = [regex]::Match($Text, "(?m)^\s*GRAFANA_ADMIN_PASSWORD\s*=\s*([^\r\n]+)\s*$")
    if (-not $PostgresMatch.Success -or -not $GrafanaMatch.Success) {
        throw ".env must define POSTGRES_PASSWORD and GRAFANA_ADMIN_PASSWORD."
    }
    $PostgresSecret = $PostgresMatch.Groups[1].Value.Trim()
    $GrafanaSecret = $GrafanaMatch.Groups[1].Value.Trim()
    if ($PostgresSecret.Length -lt 32 -or $GrafanaSecret.Length -lt 32 -or $PostgresSecret -eq $GrafanaSecret) {
        throw "Use two different passwords with at least 32 characters. Run .\ops\windows-setup.ps1 to generate secure local values."
    }
    & docker compose --project-directory $RepoRoot config --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose configuration validation failed. Secret values were not displayed."
    }
    if (Test-Path $EnvPath) {
        $PortMatch = [regex]::Match($Text, "(?m)^\s*WEB_PORT\s*=\s*(\d+)\s*$")
        if ($PortMatch.Success) { $script:WebPort = [int]$PortMatch.Groups[1].Value }
    }
}

try {
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
    $TranscriptStarted = $true

    Write-Host "=== LOCAL DEVOPS LAB INCIDENT DEMO ===" -ForegroundColor Cyan
    Write-Host ("UTC start: {0}" -f (Get-Date).ToUniversalTime().ToString("o"))
    Write-Host "This script affects only the local Docker Compose lab. It does not connect to a production server."

    $null = & docker info --format "{{.ServerVersion}}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Engine is not reachable. Start Docker Desktop and rerun the demo."
    }

    Assert-LocalEnvironment
    $BaseUrl = "http://127.0.0.1:$WebPort"
    $MailpitMessages = Get-MailpitMessages
    $KnownMailMessageIds = @()
    $AlertDeliveryEnabled = (
        (Get-HttpStatus -Url "http://127.0.0.1:9090/-/ready") -eq 200 -and
        (Get-HttpStatus -Url "http://127.0.0.1:9093/-/ready") -eq 200 -and
        $null -ne $MailpitMessages
    )
    if ($null -ne $MailpitMessages -and $null -ne $MailpitMessages.messages) {
        foreach ($Message in $MailpitMessages.messages) {
            if (-not [string]::IsNullOrWhiteSpace([string]$Message.ID)) {
                $KnownMailMessageIds += [string]$Message.ID
            }
        }
    }
    if ($AlertDeliveryEnabled) {
        Write-Host "Alert delivery is enabled. New firing and resolved notifications will be checked in Mailpit."
    }
    else {
        Write-Host "Monitoring email delivery is not running. The application outage/recovery demo will continue without waiting for email alerts."
    }

    Write-Host ""
    Write-Host "=== 1. Baseline: verify all services before the incident ===" -ForegroundColor Cyan
    Invoke-Compose -Arguments @("ps")
    Assert-Http200 -Url "$BaseUrl/health" -Label "Main website"
    Assert-Http200 -Url "$BaseUrl/api/health" -Label "API readiness"
    Assert-Http200 -Url "$BaseUrl/second/health" -Label "Second website"

    Write-Host ""
    Write-Host "=== 2. Resource snapshot ===" -ForegroundColor Cyan
    & docker stats --no-stream
    if ($LASTEXITCODE -ne 0) { throw "docker stats failed." }

    Write-Host ""
    Write-Host "=== 3. Simulate an API outage ===" -ForegroundColor Cyan
    Invoke-Compose -Arguments @("stop", "api")
    $ApiStopped = $true

    $FailureStatus = Get-HttpStatus -Url "$BaseUrl/api/health"
    Write-Host ("API readiness while the API container is stopped: HTTP {0}" -f $FailureStatus)
    if ($FailureStatus -lt 500 -or $FailureStatus -ge 600) {
        throw "Expected an HTTP 5xx response from the API route during the controlled outage; received HTTP $FailureStatus."
    }
    Write-Host "PASS: the API outage is visible through the reverse proxy." -ForegroundColor Green
    if ($AlertDeliveryEnabled) {
        Write-Host "Waiting for Prometheus evaluation and Alertmanager email delivery..."
        $FiringMessageId = Wait-MailpitNotification -State Firing -KnownMessageIds $KnownMailMessageIds -TimeoutSeconds $AlertTimeoutSeconds
        if (-not [string]::IsNullOrWhiteSpace([string]$FiringMessageId)) {
            $KnownMailMessageIds += [string]$FiringMessageId
        }
    }

    Assert-Http200 -Url "$BaseUrl/health" -Label "Main Nginx website remains available"
    Assert-Http200 -Url "$BaseUrl/second/health" -Label "Second website remains available"

    Write-Host ""
    Write-Host "API logs during the outage window:"
    & docker compose logs --no-color --tail 80 web api
    if ($LASTEXITCODE -ne 0) { throw "Could not collect application logs." }

    Write-Host ""
    Write-Host "=== 4. Recover the API ===" -ForegroundColor Cyan
    Invoke-Compose -Arguments @("start", "api")
    $ApiStopped = $false

    $Recovered = $false
    $Attempts = [Math]::Ceiling($RecoveryTimeoutSeconds / 5)
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        Start-Sleep -Seconds 5
        $Status = Get-HttpStatus -Url "$BaseUrl/api/health"
        Write-Host ("Recovery check {0}/{1}: API HTTP {2}" -f $Attempt, $Attempts, $Status)
        if ($Status -eq 200) {
            $Recovered = $true
            break
        }
    }
    if (-not $Recovered) {
        throw "API did not recover within $RecoveryTimeoutSeconds seconds."
    }

    Assert-Http200 -Url "$BaseUrl/health" -Label "Main website after recovery"
    Assert-Http200 -Url "$BaseUrl/second/health" -Label "Second website after recovery"
    if ($AlertDeliveryEnabled) {
        Write-Host "Waiting for the resolved-alert email..."
        $null = Wait-MailpitNotification -State Resolved -KnownMessageIds $KnownMailMessageIds -TimeoutSeconds 60
        Write-Host "Captured firing and resolved alert emails: http://127.0.0.1:8025" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "=== 5. Final service and resource snapshot ===" -ForegroundColor Cyan
    Invoke-Compose -Arguments @("ps")
    & docker stats --no-stream
    if ($LASTEXITCODE -ne 0) { throw "docker stats failed." }

    Write-Host ""
    Write-Host "DEMO RESULT: PASS - API outage detected and API recovered; both websites stayed available." -ForegroundColor Green
}
catch {
    $ExitCode = 1
    Write-Host ("DEMO RESULT: FAILED - {0}" -f $_.Exception.Message) -ForegroundColor Red
}
finally {
    if ($ApiStopped) {
        Write-Warning "The script is attempting to restart the API during cleanup."
        & docker compose start api
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: automatic API restart failed. Run: docker compose start api" -ForegroundColor Red
            $ExitCode = 1
        }
        else {
            Write-Host "Cleanup started the API container. Verify it with .\ops\windows-lab.ps1 -Action Health."
        }
    }
    if ($TranscriptStarted) {
        Write-Host ("Evidence transcript: {0}" -f $TranscriptPath)
        Stop-Transcript | Out-Null
    }
}

if ($ExitCode -ne 0) { exit 1 }
exit 0
