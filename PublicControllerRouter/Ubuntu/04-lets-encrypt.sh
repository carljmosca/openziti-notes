#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

###
# Load environment
###
source /opt/openziti/load-env.sh

# Ensure required env variables are set
REQUIRED_VARS=(CTRL_DOMAIN ROUTER_DOMAIN LETSENCRYPT_EMAIL)
for v in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!v:-}" ]]; then
        echo "❌ Required variable '$v' is not set in ziti.env"
        exit 1
    fi
done

###
# Request certificates
###
echo "▶ Requesting TLS certificates using Let's Encrypt..."

# Controller
echo "🔹 Controller domain: $CTRL_DOMAIN"
if [[ ! -d "/etc/letsencrypt/live/$CTRL_DOMAIN" ]]; then
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$LETSENCRYPT_EMAIL" \
        -d "$CTRL_DOMAIN"
else
    echo "ℹ Certificate for $CTRL_DOMAIN already exists, skipping"
fi

# Router
echo "🔹 Router domain: $ROUTER_DOMAIN"
if [[ ! -d "/etc/letsencrypt/live/$ROUTER_DOMAIN" ]]; then
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$LETSENCRYPT_EMAIL" \
        -d "$ROUTER_DOMAIN"
else
    echo "ℹ Certificate for $ROUTER_DOMAIN already exists, skipping"
fi

echo
echo "✅ Let's Encrypt certificate provisioning complete"
