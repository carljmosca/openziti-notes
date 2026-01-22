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
source ./ziti.env

ARCH=$(uname -m)
[[ "$ARCH" != "x86_64" ]] && echo "❌ Unsupported arch: $ARCH" && exit 1

DOWNLOAD_URL="https://github.com/openziti/ziti/releases/download/$ZITI_VERSION/openziti-linux-$ARCH.tar.gz"

echo "▶ Downloading $DOWNLOAD_URL ..."
curl -LO "$DOWNLOAD_URL"

echo "▶ Extracting to /opt/openziti ..."
tar -xzf openziti-linux-$ARCH.tar.gz -C /opt/openziti --strip-components=1
rm -f openziti-linux-$ARCH.tar.gz

# Create symlink to match docs
ln -sf /opt/openziti/ziti-router /usr/local/bin/ziti-router-auto-enroll

echo "✅ OpenZiti installed"
echo "Next: copy your ziti.env into /opt/openziti/ziti.env and continue with 02-bootstrap-controller.sh"
