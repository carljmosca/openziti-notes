#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

source /opt/openziti/load-env.sh

# Ensure certbot is installed
command -v certbot >/dev/null || { echo "❌ certbot not found"; exit 1; }

for DOMAIN in "$CTRL_DOMAIN" "$ROUTER_DOMAIN"; do
    echo "▶ Checking Let's Encrypt certificate for $DOMAIN..."
    if [[ ! -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "$LETSENCRYPT_EMAIL" \
            -d "$DOMAIN"
    else
        echo "ℹ Certificate for $DOMAIN already exists, skipping"
    fi
done

echo "✅ Let's Encrypt provisioning complete"
