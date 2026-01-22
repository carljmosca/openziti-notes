#!/usr/bin/env bash
set -euo pipefail

source /opt/openziti/load-env.sh

ZITI_HOME=/opt/openziti
ROUTER_NAME=public-edge-router
ROUTER_PORT=3022

# Load admin credentials
source $ZITI_HOME/etc/controller/admin.env

# Login
ziti edge login localhost:8440 -u $ZITI_ADMIN_USERNAME -p $ZITI_ADMIN_PASSWORD --yes

# Create edge router
ziti edge create edge-router $ROUTER_NAME \
  --role-attributes public \
  --tunneler-enabled

# Enroll router
ziti edge enroll edge-router $ROUTER_NAME \
  --jwt-output-file /tmp/${ROUTER_NAME}.jwt

sudo mkdir -p $ZITI_HOME/etc/router
sudo chown -R $USER:$USER $ZITI_HOME/etc/router

ziti-router enroll /tmp/${ROUTER_NAME}.jwt \
  --router-name $ROUTER_NAME \
  --listen-address 0.0.0.0:$ROUTER_PORT

# Enable + start router
sudo systemctl enable ziti-router
sudo systemctl start ziti-router

echo "✅ Public edge router enrolled and running on port $ROUTER_PORT"
