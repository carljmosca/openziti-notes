#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/openziti/ziti.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

REQUIRED_VARS=(
  ZITI_HOME
  CTRL_DOMAIN
  ZITI_CTRL_API_PORT
  ZITI_ROUTER_NAME
  ZITI_ROUTER_PORT
)

for v in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "❌ Required variable '$v' is not set"
    exit 1
  fi
done
