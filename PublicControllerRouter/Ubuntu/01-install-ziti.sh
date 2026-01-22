#!/usr/bin/env bash
set -e

sudo apt update
sudo apt install -y curl jq unzip

# Install both controller and router binaries
curl -sS https://get.openziti.io/install.bash | sudo bash -s openziti-controller openziti-router

echo "✅ OpenZiti binaries installed"

sudo mkdir -p /opt/openziti
sudo cp ziti.env /opt/openziti/ziti.env

sudo cp load-env.sh /opt/openziti
sudo chmod +x /opt/openziti/load-env.sh
