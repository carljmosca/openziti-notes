#!/usr/bin/env bash
set -euo pipefail

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
echo "▶ Fixing certificate permissions..."
chown -R ziti:ziti /etc/letsencrypt
chmod -R 750 /etc/letsencrypt

###
# Install renewal hook
###
HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
HOOK_FILE="$HOOK_DIR/ziti-reload.sh"

mkdir -p "$HOOK_DIR"

cat > "$HOOK_FILE" <<'EOF'
#!/usr/bin/env bash
systemctl restart ziti-controller
systemctl restart ziti-router
EOF

chmod +x "$HOOK_FILE"

###
# Start Ziti again
###
echo "▶ Starting Ziti services..."
systemctl start ziti-controller
systemctl start ziti-router

###
# Dry-run renewal test
###
echo "▶ Testing renewal..."
certbot renew --dry-run

echo "✅ Let's Encrypt setup complete"
echo "   Controller domain: $CTRL_DOMAIN"
echo "   Router domain:     $ROUTER_DOMAIN"

sudo chown root:root /opt/openziti/ziti.env
sudo chmod 600 /opt/openziti/ziti.env
