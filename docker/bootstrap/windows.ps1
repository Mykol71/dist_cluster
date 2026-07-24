# docker/bootstrap/windows.ps1
#
# Prerequisites installer for Windows host nodes (Windows 10/11, Server 2019+).
# Run this in an elevated PowerShell session on every Windows machine that
# will participate in the dist_cluster — whether as a master or a worker.
#
# What this script installs / configures:
#   1. Winget (checks availability — built-in on Windows 11 / updated Win 10)
#   2. Docker Desktop with WSL 2 backend
#   3. Tailscale
#   4. OpenSSH client (for the master role)
#   5. SSH keypair check
#   6. Builds the appropriate dist_cluster Docker image
#
# Usage (in an elevated PowerShell):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\docker\bootstrap\windows.ps1 [-Role master|worker]
#
# Parameters:
#   -Role   master   Build/run the master image
#           worker   Build/run the worker image and start the container (default)

param(
    [ValidateSet("master", "worker")]
    [string]$Role = "worker"
)

$ErrorActionPreference = "Stop"

function Log  { Write-Host "▶  $args" }
function Ok   { Write-Host "✅ $args" -ForegroundColor Green }
function Warn { Write-Warning "⚠️  $args" }
function Fail { Write-Error "❌ $args"; exit 1 }

# Resolve repository root (two levels up from this script's location)
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Resolve-Path (Join-Path $ScriptDir "..\..") | Select-Object -ExpandProperty Path

# ── Guard: Windows only ────────────────────────────────────────────────────────
if (-not $IsWindows -and $env:OS -ne "Windows_NT") {
    Fail "This script must be run on Windows."
}

# ── 1. Winget availability ─────────────────────────────────────────────────────
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Warn "winget is not available. Install 'App Installer' from the Microsoft Store and re-run."
    Warn "Alternatively, install Docker Desktop and Tailscale manually from their websites."
    Warn "Continuing without winget — manual installation required."
    $NoWinget = $true
} else {
    $NoWinget = $false
    Ok "winget found: $(winget --version)"
}

# ── 2. Docker Desktop ──────────────────────────────────────────────────────────
$DockerPath = Get-Command docker -ErrorAction SilentlyContinue

if ($DockerPath) {
    Ok "Docker already installed: $(docker --version)"
} elseif (-not $NoWinget) {
    Log "Installing Docker Desktop via winget..."
    winget install --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements -e
    Ok "Docker Desktop installed."
    Warn "Please start Docker Desktop and enable 'WSL 2 based engine' in Settings > General, then re-run this script."
    exit 0
} else {
    Warn "Please download and install Docker Desktop from: https://www.docker.com/products/docker-desktop/"
    Warn "Ensure WSL 2 is enabled and re-run this script after installation."
    exit 1
}

# Verify Docker daemon is reachable
try {
    docker info 2>&1 | Out-Null
    Ok "Docker daemon is running."
} catch {
    Warn "Docker daemon is not running. Please start Docker Desktop and re-run."
    exit 1
}

# ── 3. Tailscale ───────────────────────────────────────────────────────────────
$TailscalePath = Get-Command tailscale -ErrorAction SilentlyContinue

if ($TailscalePath) {
    Ok "Tailscale already installed: $(tailscale version | Select-Object -First 1)"
} elseif (-not $NoWinget) {
    Log "Installing Tailscale via winget..."
    winget install --id Tailscale.Tailscale --accept-package-agreements --accept-source-agreements -e
    Ok "Tailscale installed."
} else {
    Warn "Please download and install Tailscale from: https://tailscale.com/download/windows"
}

# Check Tailscale connectivity
try {
    $TsStatus = tailscale status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Ok "Tailscale is connected."
    } else {
        Warn "Tailscale is not authenticated. Run: tailscale up"
        Warn "All cluster nodes must be on the same Tailscale tailnet before running the cluster."
    }
} catch {
    Warn "Could not check Tailscale status. Ensure Tailscale is running and authenticated."
}

# ── 4. OpenSSH client (master role) ───────────────────────────────────────────
if ($Role -eq "master") {
    $SshClient = Get-WindowsCapability -Online -Name OpenSSH.Client* -ErrorAction SilentlyContinue
    if ($SshClient -and $SshClient.State -eq "Installed") {
        Ok "OpenSSH client is already installed."
    } else {
        Log "Installing OpenSSH client (Windows Optional Feature)..."
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 | Out-Null
        Ok "OpenSSH client installed."
    }
}

# ── 5. SSH keypair check ───────────────────────────────────────────────────────
$SshDir     = Join-Path $env:USERPROFILE ".ssh"
$KeyRsa     = Join-Path $SshDir "id_rsa"
$KeyEd25519 = Join-Path $SshDir "id_ed25519"

if ((Test-Path $KeyRsa) -or (Test-Path $KeyEd25519)) {
    Ok "SSH keypair found in $SshDir"
} else {
    Log "No SSH keypair found. Generating one..."
    if (-not (Test-Path $SshDir)) { New-Item -ItemType Directory -Path $SshDir | Out-Null }
    ssh-keygen -t ed25519 -C "dist_cluster" -N '""' -f $KeyEd25519
    Ok "SSH keypair generated at $KeyEd25519"
}

# ── 6. Build Docker image ──────────────────────────────────────────────────────
if ($Role -eq "worker") {
    Log "Building dist_cluster_worker image..."
    docker build -f "$RepoRoot\docker\Dockerfile.worker" -t dist_cluster_worker $RepoRoot
    Ok "dist_cluster_worker image built."

    # Read the public key
    $PubKeyPath = if (Test-Path $KeyRsa) { "$KeyRsa.pub" } else { "$KeyEd25519.pub" }
    if ($env:SSH_PUBLIC_KEY) {
        $PubKey = $env:SSH_PUBLIC_KEY
    } elseif (Test-Path $PubKeyPath) {
        $PubKey = Get-Content $PubKeyPath -Raw
    } else {
        Warn "Could not read a public key. Set the SSH_PUBLIC_KEY environment variable or generate a keypair."
        $PubKey = ""
    }

    if ($PubKey) {
        Log "Starting worker container (SSH on host port 2222)..."
        # Remove any previously running worker container
        docker rm -f dist_worker 2>$null | Out-Null
        docker run -d `
            --name dist_worker `
            --restart unless-stopped `
            -p 2222:22 `
            -e "SSH_PUBLIC_KEY=$PubKey" `
            dist_cluster_worker
        Ok "Worker container started on port 2222."
        Write-Host ""
        Write-Host "Add this Windows node to the master's WORKER_NODES using its Tailscale IP:"
        Write-Host "  tailscale ip"
        Write-Host "  (configure SSH to use port 2222 in ~/.ssh/config on the master)"
    }

} elseif ($Role -eq "master") {
    Log "Building dist_cluster_master image..."
    docker build -f "$RepoRoot\docker\Dockerfile.master" -t dist_cluster_master $RepoRoot
    Ok "dist_cluster_master image built."
    Write-Host ""
    Write-Host "Run the master container:"
    Write-Host "  docker run -it --rm ``"
    Write-Host "    -v `$env:USERPROFILE\.ssh\id_rsa:/root/.ssh/id_rsa:ro ``"
    Write-Host "    -v `$env:USERPROFILE\.ssh\id_rsa.pub:/root/.ssh/id_rsa.pub:ro ``"
    Write-Host "    dist_cluster_master bash"
}

Write-Host ""
Write-Host "=================================================="
Ok "Windows node bootstrap complete for role: $Role"
Write-Host "=================================================="
