#!/usr/bin/env bash
# docker/entrypoint-worker.sh
#
# Container entrypoint for the dist_cluster worker node.
#
# Behaviour:
#   1. Installs the SSH public key passed via SSH_PUBLIC_KEY env var
#      (or from /run/secrets/ssh_public_key if using Docker Secrets).
#   2. Generates host SSH keys if missing (first-time start).
#   3. Starts the OpenSSH daemon in the foreground.
#
# Environment variables:
#   SSH_PUBLIC_KEY   — Contents of the authorized public key (required unless
#                      /root/.ssh/authorized_keys is already populated via a
#                      bind-mount or volume).

set -euo pipefail

# ── 1. Authorized key setup ───────────────────────────────────────────────────

AUTH_KEYS="/root/.ssh/authorized_keys"

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    echo "$SSH_PUBLIC_KEY" >> "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    echo "✅ SSH public key installed from SSH_PUBLIC_KEY environment variable."
elif [ -f /run/secrets/ssh_public_key ]; then
    cat /run/secrets/ssh_public_key >> "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    echo "✅ SSH public key installed from Docker Secret."
elif [ -f "$AUTH_KEYS" ] && [ -s "$AUTH_KEYS" ]; then
    echo "✅ SSH authorized_keys already populated (bind-mount or pre-built image)."
else
    echo "⚠️  WARNING: No SSH public key provided." >&2
    echo "   Set SSH_PUBLIC_KEY env var, mount an authorized_keys file, or use" >&2
    echo "   Docker Secrets (secret name: ssh_public_key)." >&2
    echo "   The worker will start but SSH connections will fail authentication." >&2
fi

# ── 2. Host key generation ────────────────────────────────────────────────────

if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "🔑 Generating SSH host keys for the first time..."
    ssh-keygen -A
fi

# ── 3. Start OpenSSH daemon ───────────────────────────────────────────────────

echo "🚀 Starting OpenSSH server on port 22..."
exec /usr/sbin/sshd -D -e
