#!/usr/bin/env bash
set -euo pipefail

systemctl stop ziti-router ziti-controller 2>/dev/null || true
systemctl disable ziti-router ziti-controller 2>/dev/null || true

rm -rf /opt/openziti
rm -rf /var/lib/ziti
rm -rf /etc/systemd/system/ziti-*

userdel ziti 2>/dev/null || true

echo "✅ OpenZiti fully removed"
