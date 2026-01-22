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

# Explicit release URL (replace v1.13.3 with your desired release)
ZITI_VERSION="v1.13.3"
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH="x86_64"
else
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
fi

DOWNLOAD_URL="https://github.com/openziti/ziti/releases/download/$ZITI_VERSION/openziti-linux-$ARCH.tar.gz"

echo "▶ Downloading $DOWNLOAD_URL ..."
curl -LO "$DOWNLOAD_URL"

# Verify small download
if [[ ! -s openziti-linux-$ARCH.tar.gz ]]; then
    echo "❌ Download failed or empty file"
    exit 1
fi

echo "▶ Extracting to /opt/openziti ..."
tar -xzf openziti-linux-$ARCH.tar.gz -C /opt/openziti --strip-components=1

rm -f openziti-linux-$ARCH.tar.gz

echo "✅ OpenZiti installed"
echo "Next: copy your ziti.env into /opt/openziti/ziti.env and continue with 02-bootstrap-controller.sh"
