#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$ZITI_HOME/ziti.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing $ENV_FILE. Copy ziti.env.example and edit it first."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# Required variables
REQUIRED_VARS=(ZITI_HOME CTRL_DOMAIN ZITI_CTRL_API_PORT ZITI_CTRL_EDGE_PORT \
               ZITI_ROUTER_NAME ZITI_ROUTER_PORT ROUTER_DOMAIN LETSENCRYPT_EMAIL ZITI_USER)

for v in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!v:-}" ]]; then
        echo "❌ Required variable '$v' is not set in $ENV_FILE"
        exit 1
    fi
done
