#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

###
# Load environment
###
source /opt/openziti/load-env.sh

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (sudo)"
  exit 1
fi

echo "⚠ WARNING: This will REMOVE OpenZiti from this machine"
echo
echo "The following will be deleted:"
echo "  - OpenZiti controller and router services"
echo "  - $ZITI_HOME"
echo "  - Systemd units (ziti-controller, ziti-router)"
echo "  - Let's Encrypt certs for:"
echo "      * $CTRL_DOMAIN"
echo "      * $ROUTER_DOMAIN"
echo
read -rp "Type 'yes' to continue: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "❌ Aborted"
  exit 1
fi

echo "▶ Stopping services..."
systemctl stop ziti-controller || true
systemctl stop ziti-router || true

echo "▶ Disabling services..."
systemctl disable ziti-controller || true
systemctl disable ziti-router || true

echo "▶ Removing systemd units..."
rm -f /etc/systemd/system/ziti-controller.service
rm -f /etc/systemd/system/ziti-router.service
systemctl daemon-reload

echo "▶ Removing OpenZiti binaries..."
rm -f /usr/local/bin/ziti
rm -f /usr/local/bin/ziti-controller
rm -f /usr/local/bin/ziti-router

echo "▶ Removing OpenZiti data and config..."
rm -rf "$ZITI_HOME"

###
# Remove Let's Encrypt certs (domain-scoped only)
###
echo "▶ Removing Let's Encrypt certificates..."

certbot delete --cert-name "$CTRL_DOMAIN" --non-interactive || true
certbot delete --cert-name "$ROUTER_DOMAIN" --non-interactive || true

rm -rf "/etc/letsencrypt/live/$CTRL_DOMAIN"
rm -rf "/etc/letsencrypt/live/$ROUTER_DOMAIN"
rm -rf "/etc/letsencrypt/archive/$CTRL_DOMAIN"
rm -rf "/etc/letsencrypt/archive/$ROUTER_DOMAIN"
rm -f  "/etc/letsencrypt/renewal/$CTRL_DOMAIN.conf"
rm -f  "/etc/letsencrypt/renewal/$ROUTER_DOMAIN.conf"

###
# Optional: remove certbot itself
###
read -rp "Remove certbot package as well? (yes/no): " REMOVE_CERTBOT
if [[ "$REMOVE_CERTBOT" == "yes" ]]; then
  echo "▶ Removing certbot..."
  apt purge -y certbot
  apt autoremove -y
fi

###
# Optional: remove env + loader
###
read -rp "Remove Ziti env and loader files? (yes/no): " REMOVE_ENV
if [[ "$REMOVE_ENV" == "yes" ]]; then
  rm -f /opt/openziti/ziti.env
  rm -f /opt/openziti/load-env.sh
fi

echo
echo "✅ OpenZiti uninstall complete"
echo "ℹ A reboot is NOT required"
