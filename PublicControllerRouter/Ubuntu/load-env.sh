#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$ZITI_HOME/ziti.env"
[[ ! -f "$ENV_FILE" ]] && echo "❌ Missing $ENV_FILE" && exit 1

source "$ENV_FILE"

REQUIRED_VARS=(ZITI_HOME CTRL_DOMAIN ZITI_CTRL_API_PORT ZITI_CTRL_EDGE_PORT \
               ZITI_ROUTER_NAME ZITI_ROUTER_PORT ROUTER_DOMAIN LETSENCRYPT_EMAIL ZITI_USER)

for v in "${REQUIRED_VARS[@]}"; do
    [[ -z "${!v:-}" ]] && echo "❌ Required variable '$v' not set in $ENV_FILE" && exit 1
done
