#!/usr/bin/env bash
set -euo pipefail

ziti edge login "$CTRL_DOMAIN:$ZITI_CTRL_API_PORT" \
  -u "$ZITI_ADMIN_USERNAME" \
  -p "$ZITI_ADMIN_PASSWORD" \
  --yes
