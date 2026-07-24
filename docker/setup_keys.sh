#!/usr/bin/env bash
# docker/setup_keys.sh
#
# Generates a dedicated SSH keypair used by the master container to
# authenticate against worker containers.
#
# Keys are written to docker/keys/ which is git-ignored.
# Run this once before the first `docker compose up`.
#
# Usage:
#   bash docker/setup_keys.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="$SCRIPT_DIR/keys"

if [ -f "$KEYS_DIR/id_rsa" ] && [ -f "$KEYS_DIR/id_rsa.pub" ]; then
    echo "✅ SSH keypair already exists at $KEYS_DIR — skipping generation."
    echo "   Delete $KEYS_DIR and re-run to regenerate."
    exit 0
fi

echo "🔑 Generating dedicated SSH keypair for dist_cluster..."
mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

ssh-keygen -t rsa -b 4096 -C "dist_cluster@local" -N "" -f "$KEYS_DIR/id_rsa"
chmod 600 "$KEYS_DIR/id_rsa"
chmod 644 "$KEYS_DIR/id_rsa.pub"

echo ""
echo "✅ Keypair created:"
echo "   Private key : $KEYS_DIR/id_rsa"
echo "   Public key  : $KEYS_DIR/id_rsa.pub"
echo ""
echo "Next step — start the cluster:"
echo "  docker compose -f docker/docker-compose.yml up --build -d"
