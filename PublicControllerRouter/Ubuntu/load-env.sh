#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/openziti/ziti.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing environment file: $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

REQUIRED_VARS=(
  CTRL_DOMAIN
  ROUTER_DOMAIN
  LE_EMAIL
  ZITI_HOME
  LE_BASE
  ZITI_CTRL_ADVERTISED_PORT
  ZITI_CTRL_API_PORT
  ZITI_ROUTER_PORT
  ZITI_ROUTER_NAME
)

MISSING=()

for VAR in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!VAR:-}" ]]; then
    MISSING+=("$VAR")
  fi
done

if (( ${#MISSING[@]} > 0 )); then
  echo "❌ Missing required environment variables:"
  for V in "${MISSING[@]}"; do
    echo "   - $V"
  done
  exit 1
fi
