#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_ENV="$ZITI_HOME/etc/controller/bootstrap.env"

if [[ ! -f "$BOOTSTRAP_ENV" ]]; then
  echo "❌ bootstrap.env not found: $BOOTSTRAP_ENV"
  exit 1
fi

# shellcheck disable=SC1090
source "$BOOTSTRAP_ENV"

# Username is always admin
ZITI_ADMIN_USERNAME="admin"

if [[ -n "${ZITI_BOOTSTRAP_EDGE_ADMIN_PASSWORD:-}" ]]; then
  ZITI_ADMIN_PASSWORD="$ZITI_BOOTSTRAP_EDGE_ADMIN_PASSWORD"
elif [[ -n "${ZITI_BOOTSTRAP_ADMIN_PASSWORD:-}" ]]; then
  ZITI_ADMIN_PASSWORD="$ZITI_BOOTSTRAP_ADMIN_PASSWORD"
else
  echo "❌ No admin password found in bootstrap.env"
  exit 1
fi

export ZITI_ADMIN_USERNAME
export ZITI_ADMIN_PASSWORD
