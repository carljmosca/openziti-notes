#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

###
# Load operator configuration
###
source /opt/openziti/load-env.sh

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (sudo)"
  exit 1
fi

###
# Paths
###
BOOTSTRAP_ENV="$ZITI_HOME/etc/controller/bootstrap.env"
ROUTER_DIR="$ZITI_HOME/etc/router"
JWT_FILE="/tmp/${ZITI_ROUTER_NAME}.jwt"

###
# Validate controller bootstrap
###
if [[ ! -f "$BOOTSTRAP_ENV" ]]; then
  echo "❌ bootstrap.env not found at:"
  echo "   $BOOTSTRAP_ENV"
  echo "   Has the controller been bootstrapped?"
  exit 1
fi

# shellcheck disable=SC1090
source "$BOOTSTRAP_ENV"

###
# Login to controller (idempotent)
###
echo "▶ Logging into controller..."

ziti edge login "$CTRL_DOMAIN:$ZITI_CTRL_API_PORT" \
  -u "$ZITI_BOOTSTRAP_ADMIN_USERNAME" \
  -p "$ZITI_BOOTSTRAP_ADMIN_PASSWORD" \
  --yes

###
# Create edge router if it does not exist
###
if ziti edge list edge-routers -j | jq -e \
  ".data[].name == \"$ZITI_ROUTER_NAME\"" >/dev/null; then
  echo "ℹ Edge router '$ZITI_ROUTER_NAME' already exists"
else
  echo "▶ Creating edge router '$ZITI_ROUTER_NAME'..."
  ziti edge create edge-router "$ZITI_ROUTER_NAME" \
    --role-attributes public \
    --tunneler-enabled
fi

###
# Enroll router only if not already enrolled
###
if [[ -d "$ROUTER_DIR" && -f "$ROUTER_DIR/router.yaml" ]]; then
  echo "ℹ Router already enrolled — skipping enrollment"
else
  echo "▶ Enrolling edge router..."

  ziti edge enroll edge-router "$ZITI_ROUTER_NAME" \
    --jwt-output-file "$JWT_FILE"

  mkdir -p "$ROUTER_DIR"
  chown -R ziti:ziti "$ROUTER_DIR"

  ziti-router enroll "$JWT_FILE" \
    --router-name "$ZITI_ROUTER_NAME" \
    --listen-address "0.0.0.0:$ZITI_ROUTER_PORT"

  rm -f "$JWT_FILE"
fi

###
# Enable and start router service
###
echo "▶ Enabling and starting ziti-router..."

systemctl enable ziti-router
systemctl restart ziti-
