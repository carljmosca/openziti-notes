#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

source /opt/openziti/load-env.sh

if [[ -f "$ZITI_HOME/etc/controller/bootstrap.env" ]]; then
  echo "ℹ Controller already bootstrapped"
  exit 0
fi

ziti controller edge init "$ZITI_HOME/etc/controller" \
    --ctrl-advertised-address "$CTRL_DOMAIN" \
    --ctrl-advertised-port "$ZITI_CTRL_API_PORT" \
    --edge-advertised-address "$CTRL_DOMAIN" \
    --edge-advertised-port "$ZITI_CTRL_EDGE_PORT"

systemctl enable ziti-controller
systemctl start ziti-controller

echo "✅ Controller bootstrapped"
