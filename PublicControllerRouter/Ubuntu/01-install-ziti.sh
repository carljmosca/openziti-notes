#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR


ENV_SRC="$(pwd)/ziti.env"
ENV_DST="/opt/openziti/ziti.env"

if [[ ! -f "$ENV_SRC" ]]; then
  echo "❌ ziti.env not found in current directory"
  echo "   Copy ziti.env.example to ziti.env and edit it first"
  exit 1
fi

mkdir -p /opt/openziti
cp "$ENV_SRC" "$ENV_DST"
chown root:root "$ENV_DST"
chmod 600 "$ENV_DST"

source /opt/openziti/load-env.sh

if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root"
  exit 1
fi

useradd -r -s /sbin/nologin "$ZITI_USER" 2>/dev/null || true

curl -sSL https://get.openziti.io | bash

mkdir -p "$ZITI_HOME"
chown -R "$ZITI_USER:$ZITI_USER" "$ZITI_HOME"

echo "✅ OpenZiti installed"
