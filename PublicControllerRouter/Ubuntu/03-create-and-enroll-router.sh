#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

source /opt/openziti/load-env.sh

ROUTER_DIR="$ZITI_HOME/etc/router"
mkdir -p "$ROUTER_DIR"
chown -R "$ZITI_USER:$ZITI_USER" "$ROUTER_DIR"

echo "▶ Starting auto-enroll router..."

# This is now identical to docs: symlink allows `ziti-router-auto-enroll run ...`
ziti-router-auto-enroll run \
    --name "$ZITI_ROUTER_NAME" \
    --edge-listen "0.0.0.0:$ZITI_ROUTER_PORT" \
    --controller "$CTRL_DOMAIN:$ZITI_CTRL_API_PORT" \
    --auto-enroll

# Optional: enable systemd
# systemctl enable ziti-router
# systemctl restart ziti-router

echo "✅ Auto-enroll router started"
