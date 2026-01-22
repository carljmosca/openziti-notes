#!/bin/bash

# ==============================================================================
# OpenZiti Podman Automator (Consultant Edition - Env-Driven)
# ==============================================================================

set -e

# Load Environment Variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "ERROR: .env file not found. Copy .env.example to .env and fill it out."
    exit 1
fi

ZITI_DIR="$HOME/$PROJECT_NAME"

echo "--- Initializing OpenZiti Stack for $ZITI_DOMAIN ---"

# 1. Prep Environment
sudo apt update && sudo apt install -y podman podman-compose curl
mkdir -p "$ZITI_DIR/controller-data" "$ZITI_DIR/router-data" "$ZITI_DIR/caddy_data"
cd "$ZITI_DIR"

# 2. Create Caddyfile
cat <<EOF > Caddyfile
{
    email $LE_EMAIL
}

$ZITI_DOMAIN {
    reverse_proxy ziti-controller:1280 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF

# 3. Create Integrated Compose File
cat <<EOF > compose.yaml
services:
  ziti-controller:
    image: openziti/ziti-controller:latest
    container_name: ziti-controller
    restart: always
    ports:
      - "6262:6262"
    volumes:
      - ./controller-data:/persistent:Z
    environment:
      - ZITI_USER=$ZITI_USER
      - ZITI_PWD=$ZITI_PWD
      - ZITI_CTRL_ADVERTISED_ADDRESS=$ZITI_DOMAIN

  ziti-router:
    image: openziti/ziti-router:latest
    container_name: ziti-router
    restart: always
    depends_on:
      - ziti-controller
    environment:
      - ZITI_ENROLL_TOKEN=/persistent/client-router.jwt
      - ZITI_ROUTER_NAME=client-router
      - ZITI_ROUTER_ADVERTISED_ADDRESS=$ZITI_DOMAIN
    volumes:
      - ./router-data:/persistent:Z

  caddy:
    image: caddy:latest
    container_name: caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:Z
      - ./caddy_data:/data:Z
EOF

# 4. Launch Controller & Caddy
echo "Starting Controller and Proxy..."
podman-compose up -d ziti-controller caddy

# 5. Health Check
echo "Waiting for Edge API (SSL via Caddy) to respond..."
MAX_RETRIES=40
COUNT=0
until $(curl -s -f -o /dev/null https://$ZITI_DOMAIN/edge/management/v1/version); do
    printf '.'
    sleep 5
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Timeout reached. Check logs."
        exit 1
    fi
done

# 6. Generate Router Token
echo "Generating Edge Router token..."
podman exec -it ziti-controller /openziti/ziti edge create edge-router "client-router" -t -o /persistent/client-router.jwt
cp "$ZITI_DIR/controller-data/client-router.jwt" "$ZITI_DIR/router-data/"

# 7. Launch Router
podman-compose up -d ziti-router

# 8. Persistence
mkdir -p ~/.config/systemd/user/
podman generate systemd --name ziti-controller --files --new
podman generate systemd --name ziti-router --files --new
podman generate systemd --name caddy --files --new
mv *.service ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now container-ziti-controller.service container-ziti-router.service container-caddy.service
sudo loginctl enable-linger $USER

echo "--- Deployment Complete ---"
echo "Console: https://$ZITI_DOMAIN/zac"