#!/usr/bin/env bash
set -euo pipefail

source /opt/openziti/load-env.sh

ZITI_CTRL_HOME=/opt/openziti/etc/controller
ZITI_PKI_HOME=/opt/openziti/etc/pki

sudo mkdir -p $ZITI_CTRL_HOME
sudo chown -R $USER:$USER /opt/openziti

# Set required environment variables
export ZITI_CTRL_ADVERTISED_ADDRESS="$(hostname -f)"
export ZITI_CTRL_ADVERTISED_PORT=8440

# Bootstrap controller
/opt/openziti/etc/controller/bootstrap.bash

# Enable + start controller
sudo systemctl enable ziti-controller
sudo systemctl start ziti-controller

echo "✅ Controller bootstrapped and running"
echo "Admin creds saved in: $ZITI_CTRL_HOME"
