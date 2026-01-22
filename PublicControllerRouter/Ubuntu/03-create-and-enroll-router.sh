#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

source /opt/openziti/load-env.sh
source /opt/openziti/lib/ziti-admin.sh
source /opt/openziti/lib/ziti-login.sh

JWT_FILE="/tmp/${ZITI_ROUTER_NAME}.jwt"
ROUTER_DIR="$ZITI_HOME/etc/router"

echo "▶ Logging into controller..."
ziti-login

if ! ziti edge list edge-routers -j | jq -e \
  ".data[].name == \"$ZITI_ROUTER_NAME\"" >/dev/null; then
  echo "▶ Creating router..."
  ziti edge create edge-router "$ZITI_ROUTER_NAME" \
    --role-attributes public \
    --tunneler-enabled
else
  echo "ℹ Router already exists"
fi

if [[ ! -f "$ROUTER_DIR/router.yaml" ]]; then
  echo "▶ Enrolling router..."
  ziti edge enroll edge-router "$ZITI_ROUTER_NAME" \
    --jwt-output-file "$JWT_FILE"

  mkdir -p "$ROUTER_DIR"
  chown -R "$ZITI_USER:$ZITI_USER" "$ROUTER_DIR"

  ziti-router enroll "$JWT_FILE" \
    --router-name "$ZITI_ROUTER_NAME" \
    --listen-address "0.0.0.0:$ZITI_ROUTER_PORT"

  rm -f "$JWT_FILE"
else
  echo "ℹ Router already enrolled"
fi

systemctl enable ziti-router
systemctl restart ziti-router

echo "✅ Router ready"
