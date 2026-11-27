[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[A-Za-z0-9][A-Za-z0-9-]{0,62}$")]
    [string]$VMName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$EvidenceDir = Join-Path $RepoRoot "evidence"
if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
}
$Stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$TranscriptPath = Join-Path $EvidenceDir "ssh-lab-$Stamp.txt"
$SshTemporaryPath = "/tmp/devops-lab-authorized-key.pub"
$SshTemporaryTransferred = $false
$ExitCode = 0

function Invoke-Multipass {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $Output = & multipass @Arguments 2>&1
    $CommandExitCode = $LASTEXITCODE
    if ($CommandExitCode -ne 0) {
        $Message = ($Output | Out-String).Trim()
        throw ("Multipass command failed ({0}). {1}" -f ($Arguments -join " "), $Message)
    }
    return $Output
}

try {
    Start-Transcript -Path $TranscriptPath -Force | Out-Null

    Set-Location $RepoRoot
    Write-Host "=== MULTIPASS UBUNTU SSH LAB ===" -ForegroundColor Cyan
    Write-Host ("UTC start: {0}" -f (Get-Date).ToUniversalTime().ToString("o"))
    Write-Host ("Target VM: {0}" -f $VMName)
    Write-Host "This helper configures one public key for your current Multipass VM user only."
    Write-Host "It does not change sshd configuration, firewall rules, passwords or other users."

    if ($null -eq (Get-Command multipass -ErrorAction SilentlyContinue)) {
        throw "Multipass CLI was not found. Install/start Multipass and check: multipass list"
    }
    if ($null -eq (Get-Command ssh -ErrorAction SilentlyContinue)) {
        throw "OpenSSH Client (ssh.exe) is missing. Enable the Windows OpenSSH Client optional feature."
    }
    if ($null -eq (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        throw "ssh-keygen.exe is missing. Enable the Windows OpenSSH Client optional feature."
    }

    Write-Host ""
    Write-Host "=== 1. Verify Multipass VM ===" -ForegroundColor Cyan
    $InfoOutput = Invoke-Multipass -Arguments @("info", "--format", "json", $VMName)
    $Info = ($InfoOutput -join [Environment]::NewLine) | ConvertFrom-Json
    $VmProperty = $Info.PSObject.Properties[$VMName]
    if ($null -eq $VmProperty) {
        throw "Multipass did not return information for '$VMName'. Check the VM name with: multipass list"
    }
    $VmDetails = @($VmProperty.Value)[0]
    if ([string]$VmDetails.state -ne "Running") {
        throw ("VM '$VMName' is not Running (state: {0}). Start it with: multipass start {1}" -f $VmDetails.state, $VMName)
    }

    $IPv4 = @($VmDetails.ipv4 | Where-Object { $_ -match "^\d{1,3}(\.\d{1,3}){3}$" } | Select-Object -First 1)
    if ($IPv4.Count -eq 0) {
        throw "The Multipass VM has no usable IPv4 address. Inspect it with: multipass info $VMName"
    }
    $IPv4 = [string]$IPv4[0]
    Write-Host ("VM state: {0}" -f $VmDetails.state)
    Write-Host ("VM IPv4: {0}" -f $IPv4)

    $GuestUserOutput = Invoke-Multipass -Arguments @("exec", $VMName, "--", "id", "-un")
    $GuestUser = ($GuestUserOutput | Select-Object -Last 1).ToString().Trim()
    if ($GuestUser -notmatch "^[a-z_][a-z0-9_-]*$") {
        throw "Could not safely determine the default Linux account for the Multipass VM."
    }
    Write-Host ("Guest account: {0}" -f $GuestUser)

    Write-Host ""
    Write-Host "=== 2. Verify SSH reachability ===" -ForegroundColor Cyan
    $PortCheck = Test-NetConnection -ComputerName $IPv4 -Port 22 -WarningAction SilentlyContinue
    if (-not $PortCheck.TcpTestSucceeded) {
        throw ("TCP port 22 is not reachable at {0}. Check VM state and its SSH service; this script will not open firewall ports." -f $IPv4)
    }
    Write-Host "PASS: TCP port 22 is reachable from Windows." -ForegroundColor Green

    Write-Host ""
    Write-Host "=== 3. Create or reuse a local Ed25519 key ===" -ForegroundColor Cyan
    $SshDirectory = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path $SshDirectory)) {
        New-Item -ItemType Directory -Force -Path $SshDirectory | Out-Null
    }

    $KeyPath = Join-Path $SshDirectory "devops-server-operations-lab"
    $PublicKeyPath = "$KeyPath.pub"
    $PrivateKeyExists = Test-Path $KeyPath
    $PublicKeyExists = Test-Path $PublicKeyPath

    if ($PrivateKeyExists -and -not $PublicKeyExists) {
        throw "The private key exists but its .pub file is missing. Do not overwrite it automatically; restore its public key or choose another key path."
    }
    if (-not $PrivateKeyExists -and $PublicKeyExists) {
        throw "A public key exists without its private key. Move/rename that incomplete pair before rerunning."
    }
    if (-not $PrivateKeyExists) {
        Write-Host "Creating a new Ed25519 key. ssh-keygen will ask you to set a passphrase."
        & ssh-keygen -t ed25519 -a 64 -f $KeyPath -C ("devops-lab-" + $VMName)
        if ($LASTEXITCODE -ne 0) {
            throw "ssh-keygen did not complete successfully."
        }
    }
    else {
        Write-Host "Reusing the existing lab key. The private-key file will not be overwritten."
    }

    if (-not (Test-Path $PublicKeyPath)) {
        throw "The public key file was not created: $PublicKeyPath"
    }
    $PublicKeyText = (Get-Content -Path $PublicKeyPath -Raw).Trim()
    if ($PublicKeyText -notmatch "^ssh-ed25519\s+[A-Za-z0-9+/=]+\s+.+$") {
        throw "The public key file is not a valid Ed25519 public key."
    }
    Write-Host "PASS: a valid public key is available. The private key is not displayed or copied."

    Write-Host ""
    Write-Host "=== 4. Install only the public key in the selected VM account ===" -ForegroundColor Cyan
    Invoke-Multipass -Arguments @("transfer", $PublicKeyPath, ($VMName + ":" + $SshTemporaryPath)) | Out-Null
    $SshTemporaryTransferred = $true

    $RemoteInstallScript = 'set -eu; install -d -m 700 ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; grep -Fqx -f ' + $SshTemporaryPath + ' ~/.ssh/authorized_keys || cat ' + $SshTemporaryPath + ' >> ~/.ssh/authorized_keys; rm -f ' + $SshTemporaryPath + '; echo PUBLIC_KEY_INSTALLED'
    $InstallOutput = Invoke-Multipass -Arguments @("exec", $VMName, "--", "bash", "-lc", $RemoteInstallScript)
    $SshTemporaryTransferred = $false
    if (($InstallOutput -join " ") -notmatch "PUBLIC_KEY_INSTALLED") {
        throw "The VM did not confirm public-key installation."
    }
    Write-Host "PASS: public key installed for the selected VM user. Existing authorized keys were preserved." -ForegroundColor Green

    Write-Host ""
    Write-Host "=== 5. Verify key-based SSH login ===" -ForegroundColor Cyan
    Write-Host ("Connecting to {0}@{1}. If your private key has a passphrase, enter it when prompted." -f $GuestUser, $IPv4)
    & ssh -i $KeyPath -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=accept-new" -o "ConnectTimeout=10" ($GuestUser + "@" + $IPv4) "hostname && id && uptime && df -h /"
    if ($LASTEXITCODE -ne 0) {
        throw "SSH verification failed. Confirm the key passphrase, account and guest SSH logs before trying again."
    }

    Write-Host ""
    Write-Host "DEMO RESULT: PASS - Windows connected to the Ubuntu VM using an Ed25519 SSH key." -ForegroundColor Green
    Write-Host "Next practice: inspect journalctl, systemctl, ss -tulpn, df -h, free -h and top over this SSH connection."
    Write-Host ("Evidence saved to: {0}" -f $TranscriptPath)
}
catch {
    $ExitCode = 1
    Write-Host ("SSH LAB RESULT: FAILED - {0}" -f $_.Exception.Message) -ForegroundColor Red
}
finally {
    if ($SshTemporaryTransferred) {
        & multipass exec $VMName -- rm -f $SshTemporaryPath 2>$null | Out-Null
    }
    if ($TranscriptStarted) {
        Stop-Transcript | Out-Null
    }
}

if ($ExitCode -ne 0) { exit 1 }
exit 0
