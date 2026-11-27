[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TemplatePath = Join-Path $RepoRoot ".env.example"
$EnvPath = Join-Path $RepoRoot ".env"

if (-not (Test-Path $TemplatePath)) {
    throw "The .env.example template was not found in the repository root."
}
if (Test-Path $EnvPath) {
    throw ".env already exists. It was not changed. Edit it manually if you need to rotate credentials."
}

function New-CryptographicHexSecret {
    param([ValidateRange(32, 128)][int]$ByteCount = 32)

    $Bytes = New-Object byte[] $ByteCount
    $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $Generator.GetBytes($Bytes)
    }
    finally {
        $Generator.Dispose()
    }
    return ([System.BitConverter]::ToString($Bytes)).Replace("-", "").ToLowerInvariant()
}

$Template = [System.IO.File]::ReadAllText($TemplatePath)
$PostgresPlaceholder = "REPLACE_WITH_A_LONG_RANDOM_PASSWORD"
$GrafanaPlaceholder = "REPLACE_WITH_A_DIFFERENT_LONG_RANDOM_PASSWORD"

if (-not $Template.Contains($PostgresPlaceholder) -or -not $Template.Contains($GrafanaPlaceholder)) {
    throw "The .env.example template does not contain the expected password placeholders. No file was created."
}

$PostgresSecret = New-CryptographicHexSecret -ByteCount 32
$GrafanaSecret = New-CryptographicHexSecret -ByteCount 32
if ($PostgresSecret -eq $GrafanaSecret) {
    throw "The secure random generator returned duplicate values. Rerun the setup script."
}

$Configured = $Template.Replace($PostgresPlaceholder, $PostgresSecret)
$Configured = $Configured.Replace($GrafanaPlaceholder, $GrafanaSecret)
$Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText($EnvPath, $Configured, $Utf8WithoutBom)

# Do not print the generated credentials. The .env file is ignored by Git.
Write-Host "Created .env with two different cryptographically generated local passwords." -ForegroundColor Green
Write-Host "Credentials were not printed. Keep this file on your machine and never commit or share it."

$DockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if ($null -ne $DockerCommand) {
    Write-Host "Validating Docker Compose configuration without starting containers..."
    & docker compose --project-directory $RepoRoot config --quiet
    $ComposeExitCode = $LASTEXITCODE
    if ($ComposeExitCode -ne 0) {
        throw "The .env file was created, but Docker Compose configuration validation failed with exit code $ComposeExitCode. Keep the file and inspect the Compose configuration."
    }
    Write-Host "Docker Compose configuration validation passed. No containers were started." -ForegroundColor Green
}
else {
    Write-Host "Docker CLI is not installed. Configuration validation was skipped; you can validate it after installing Docker Desktop."
}

Write-Host "Next: start Docker Desktop, wait until its engine is Running, then run .\ops\windows-preflight.ps1."
