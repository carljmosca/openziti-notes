#!/usr/bin/env bash
set -euo pipefail

source /opt/openziti/load-env.sh

###
# CONFIG — CHANGE THESE
###
CTRL_DOMAIN="ziti.example.com"
ROUTER_DOMAIN="edge.example.com"
EMAIL="you@example.com"

###
# Sanity checks
###
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run this script as root (sudo)"
  exit 1
fi

echo "▶ Installing certbot..."
apt update
apt install -y certbot

###
# Stop Ziti temporarily in case ports are in use
###
echo "▶ Stopping Ziti services (temporary)..."
systemctl stop ziti-controller || true
systemctl stop ziti-router || true

###
# Request certificates (HTTP-01 standalone)
###
echo "▶ Requesting Let's Encrypt certificates..."
certbot certonly --standalone \
  -d "$CTRL_DOMAIN" \
  -d "$ROUTER_DOMAIN" \
  --agree-tos \
  --email "$EMAIL" \
  --non-interactive

###
# Permissions so Ziti can read certs
###
echo "▶ Fixing certificate p
