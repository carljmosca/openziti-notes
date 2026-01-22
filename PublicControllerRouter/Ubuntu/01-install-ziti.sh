#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root"
  exit 1
fi

# Install OpenZiti binaries
curl -sSL https://get.openziti.io | bash

# Create system user if missing
id ziti &>/dev/null || useradd -r -s /sbin/nologin ziti

# Create base directories
mkdir -p /opt/openziti/lib
chown -R ziti:ziti /opt/openziti

echo "✅ OpenZiti installed"
echo "Next: copy your ziti.env into /opt/openziti/ziti.env"
