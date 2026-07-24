#!/usr/bin/env bash
# docker/bootstrap/macos.sh
#
# Prerequisites installer for macOS host nodes.
# Run this on every Mac that will participate in the dist_cluster —
# whether as a master or a worker.
#
# What this script installs / configures:
#   1. Homebrew (if not already present)
#   2. Docker Desktop via Homebrew Cask (if not already present)
#   3. Tailscale via Homebrew Cask (if not already present)
#   4. SSH key-based auth check
#   5. Builds the appropriate dist_cluster Docker image
#
# Usage:
#   bash docker/bootstrap/macos.sh [--role master|worker]
#
# Flags:
#   --role master   Build/run the master image (default)
#   --role worker   Build/run the worker image and start the container

set -euo pipefail

ROLE="worker"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --role) ROLE="$2"; shift 2 ;;
        *)      echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log()  { echo "▶  $*"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*" >&2; }
fail() { echo "❌ $*" >&2; exit 1; }

# Guard: macOS only
if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "This script must be run on macOS."
fi

# ── 1. Homebrew ───────────────────────────────────────────────────────────────

if command -v brew &>/dev/null; then
    ok "Homebrew already installed: $(brew --version | head -1)"
else
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon Macs
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ok "Homebrew installed."
fi

# ── 2. Docker Desktop ─────────────────────────────────────────────────────────

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    ok "Docker Desktop already running: $(docker --version)"
else
    if brew list --cask docker &>/dev/null 2>&1; then
        log "Docker Desktop is installed but not running. Starting it..."
        open -a Docker
    else
        log "Installing Docker Desktop via Homebrew..."
        brew install --cask docker
        log "Launching Docker Desktop (may take a minute on first run)..."
        open -a Docker
    fi
    log "Waiting for Docker daemon to become ready..."
    for i in $(seq 1 30); do
        if docker info &>/dev/null 2>&1; then
            ok "Docker Desktop is running."
            break
        fi
        sleep 2
        if [ "$i" -eq 30 ]; then
            warn "Docker Desktop did not start within 60 seconds."
            warn "Please open Docker Desktop manually and re-run this script."
            exit 1
        fi
    done
fi

# ── 3. Tailscale ─────────────────────────────────────────────────────────────

if command -v tailscale &>/dev/null; then
    ok "Tailscale already installed: $(tailscale version | head -1)"
else
    log "Installing Tailscale via Homebrew..."
    brew install --cask tailscale
    ok "Tailscale installed."
    log "Opening Tailscale — complete sign-in in the menu bar app."
    open -a Tailscale
fi

if tailscale status &>/dev/null 2>&1; then
    ok "Tailscale is connected."
else
    warn "Tailscale is not authenticated. Open the Tailscale menu-bar app and sign in."
    warn "All cluster nodes must be on the same Tailscale tailnet before running the cluster."
fi

# ── 4. SSH key check ──────────────────────────────────────────────────────────

if [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ed25519" ]; then
    ok "SSH keypair found in $HOME/.ssh/"
else
    log "No SSH keypair found. Generating one..."
    ssh-keygen -t ed25519 -C "dist_cluster" -N "" -f "$HOME/.ssh/id_ed25519"
    ok "SSH keypair generated at $HOME/.ssh/id_ed25519"
fi

# ── 5. Build Docker image ─────────────────────────────────────────────────────

if [ "$ROLE" = "worker" ]; then
    log "Building dist_cluster_worker image..."
    docker build -f "$REPO_ROOT/docker/Dockerfile.worker" -t dist_cluster_worker "$REPO_ROOT"
    ok "dist_cluster_worker image built."

    log "Starting worker container (SSH on host port 2222)..."
    PUB_KEY="${SSH_PUBLIC_KEY:-$(cat "$HOME/.ssh/id_rsa.pub" 2>/dev/null || cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || echo '')}"
    if [ -z "$PUB_KEY" ]; then
        warn "Could not read a public key. Set SSH_PUBLIC_KEY env var or generate a keypair first."
    else
        # Stop any previously running worker container
        docker rm -f dist_worker 2>/dev/null || true
        docker run -d \
            --name dist_worker \
            --restart unless-stopped \
            -p 2222:22 \
            -e SSH_PUBLIC_KEY="$PUB_KEY" \
            dist_cluster_worker
        ok "Worker container started on port 2222."
        echo ""
        echo "Add this Mac to the master's WORKER_NODES using its Tailscale IP:"
        echo "  tailscale ip -4"
        echo "  (configure SSH to use port 2222 in ~/.ssh/config on the master)"
    fi

elif [ "$ROLE" = "master" ]; then
    log "Building dist_cluster_master image..."
    docker build -f "$REPO_ROOT/docker/Dockerfile.master" -t dist_cluster_master "$REPO_ROOT"
    ok "dist_cluster_master image built."
    echo ""
    echo "Run the master container:"
    echo "  docker run -it --rm \\"
    echo "    -v \$HOME/.ssh/id_rsa:/root/.ssh/id_rsa:ro \\"
    echo "    -v \$HOME/.ssh/id_rsa.pub:/root/.ssh/id_rsa.pub:ro \\"
    echo "    dist_cluster_master bash"
fi

echo ""
echo "=================================================="
echo "✅ macOS node bootstrap complete for role: $ROLE"
echo "=================================================="
