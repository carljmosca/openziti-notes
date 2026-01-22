#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root"
  exit 1
fi

# Create system user
id ziti &>/dev/null || useradd -r -s /sbin/nologin ziti

# Create directories
mkdir -p /opt/openziti/lib
chown -R ziti:ziti /opt/openziti

# Download OpenZiti binaries
OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
ZITI_TAR="openziti-$OS-$ARCH.tar.gz"
DOWNLOAD_URL="https://github.com/openziti/ziti/releases/latest/download/$ZITI_TAR"

echo "▶ Downloading $DOWNLOAD_URL ..."
curl -LO "$DOWNLOAD_URL"

echo "▶ Extracting to /opt/openziti ..."
tar -xzf "$ZITI_TAR" -C /opt/openziti --strip-components=1

rm -f "$ZITI_TAR"

echo "✅ OpenZiti installed"
echo "Next: copy your ziti.env into /opt/openziti/ziti.env and continue with 02-bootstrap-controller.sh"
