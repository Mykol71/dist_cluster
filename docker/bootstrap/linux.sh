#!/usr/bin/env bash
# docker/bootstrap/linux.sh
#
# Prerequisites installer for Linux host nodes (Debian/Ubuntu, RHEL/Fedora,
# Alpine).  Run this on every Linux machine that will participate in the
# dist_cluster — whether as a master or a worker.
#
# What this script installs / configures:
#   1. Docker Engine (if not already present)
#   2. Tailscale (if not already present) — used as the VPN mesh
#   3. SSH key-based auth check
#   4. Pulls / builds the appropriate dist_cluster Docker image
#
# Usage (as root or with sudo):
#   bash docker/bootstrap/linux.sh [--role master|worker]
#
# Flags:
#   --role master   Pull/build the master image (default)
#   --role worker   Pull/build the worker image and start the container

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

# ── 1. Detect package manager ─────────────────────────────────────────────────

detect_pkg_manager() {
    if   command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf     &>/dev/null; then echo "dnf"
    elif command -v yum     &>/dev/null; then echo "yum"
    elif command -v apk     &>/dev/null; then echo "apk"
    else fail "Unsupported Linux distribution — install Docker manually."
    fi
}

PKG_MGR=$(detect_pkg_manager)

pkg_install() {
    case "$PKG_MGR" in
        apt) apt-get install -y "$@" ;;
        dnf) dnf install -y "$@" ;;
        yum) yum install -y "$@" ;;
        apk) apk add --no-cache "$@" ;;
    esac
}

pkg_update() {
    case "$PKG_MGR" in
        apt) apt-get update -qq ;;
        dnf|yum) : ;;  # repos refresh automatically
        apk) apk update -q ;;
    esac
}

# ── 2. Docker Engine ──────────────────────────────────────────────────────────

install_docker_linux() {
    log "Installing Docker Engine..."
    case "$PKG_MGR" in
        apt)
            pkg_update
            pkg_install ca-certificates curl gnupg lsb-release
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
                | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
                $(lsb_release -cs) stable" \
                | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update -qq
            pkg_install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        dnf|yum)
            pkg_install yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            pkg_install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        apk)
            pkg_update
            pkg_install docker docker-compose
            ;;
    esac
    systemctl enable --now docker 2>/dev/null || rc-update add docker && service docker start 2>/dev/null || true
    ok "Docker Engine installed."
}

if command -v docker &>/dev/null; then
    ok "Docker already installed: $(docker --version)"
else
    install_docker_linux
fi

# ── 3. Tailscale ─────────────────────────────────────────────────────────────

install_tailscale_linux() {
    log "Installing Tailscale..."
    case "$PKG_MGR" in
        apt|dnf|yum)
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
        apk)
            pkg_install tailscale
            ;;
    esac
    ok "Tailscale installed."
}

if command -v tailscale &>/dev/null; then
    ok "Tailscale already installed: $(tailscale version | head -1)"
else
    install_tailscale_linux
fi

if tailscale status &>/dev/null; then
    ok "Tailscale is connected."
else
    warn "Tailscale is not authenticated. Run: sudo tailscale up"
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
        docker run -d \
            --name dist_worker \
            --restart unless-stopped \
            -p 2222:22 \
            -e SSH_PUBLIC_KEY="$PUB_KEY" \
            dist_cluster_worker
        ok "Worker container started on port 2222."
        echo ""
        echo "Add this node to the master's WORKER_NODES using its Tailscale IP:"
        echo "  tailscale ip -4"
        echo "  (and SSH via port 2222 if not using default port)"
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
echo "✅ Linux node bootstrap complete for role: $ROLE"
echo "=================================================="
