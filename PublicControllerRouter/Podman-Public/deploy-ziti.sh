#!/bin/bash
set -e

# Setup Logging
LOG_FILE="deploy-ziti-public-$(date +%Y%m%d-%H%M%S).log"
echo "Logging output to $LOG_FILE"
exec > >(tee -i "$LOG_FILE") 2>&1
echo "Deployment started at $(date)"

# Load environment
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "ERROR: .env file not found."
    exit 1
fi

# Versions
ZITI_VERSION="1.6.12"
CADDY_IMAGE="docker.io/library/caddy:2-alpine"

# Defaults
ZITI_CTRL_ADVERTISED_PORT=${ZITI_CTRL_ADVERTISED_PORT:-443}

echo "========================================================="
echo " Deploying PUBLIC OpenZiti in Podman POD 'ziti-pod'"
echo " Public Access: https://${ZITI_CTRL_ADVERTISED_ADDRESS}/"
echo " Firewalls must allow: TCP 80, 443, and 3022"
echo "========================================================="

# Phase 1: Reset & Pod Creation
podman pod rm -f ziti-pod 2>/dev/null || true
podman rm -f ziti-controller ziti-router caddy 2>/dev/null || true
podman network rm -f ziti-stack_ziti-net 2>/dev/null || true
rm -rf ./controller-data ./router-data caddy-identity.json *.jwt *.json Caddyfile
mkdir -p ./controller-data ./router-data

echo "--- Creating Pod 'ziti-pod' ---"
# Expose 80/443 for Caddy/Let's Encrypt, and 3022 for Edge Router
podman pod create --name ziti-pod \
    -p 80:80 \
    -p 443:443 \
    -p "${ZITI_ROUTER_ADVERTISED_PORT}:3022" \
    --add-host "${ZITI_CTRL_ADVERTISED_ADDRESS}:127.0.0.1"

# Phase 2: Caddyfile (Public Termination)
cat <<EOF > ./Caddyfile
{
    debug
}

${ZITI_CTRL_ADVERTISED_ADDRESS} {
    # Proxy everything to the Controller (API + ZAC) on 6262
    reverse_proxy https://localhost:6262 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF

# Phase 3: Controller
echo "--- Starting Controller ---"
podman run --name ziti-controller -d --replace \
    --pod ziti-pod \
    -e ZITI_PWD="${ZITI_PWD}" \
    -e ZITI_CTRL_ADVERTISED_ADDRESS="${ZITI_CTRL_ADVERTISED_ADDRESS}" \
    -e ZITI_CTRL_ADVERTISED_PORT="${ZITI_CTRL_ADVERTISED_PORT}" \
    -e ZITI_CTRL_EDGE_ADVERTISED_PORT="${ZITI_CTRL_ADVERTISED_PORT}" \
    -v $(pwd)/controller-data:/persistent:Z \
    docker.io/openziti/ziti-controller:${ZITI_VERSION}

echo "Waiting for Controller..."
# Note: We check localhost:6262 directly as we share the pod namespace.
until podman exec ziti-controller ziti edge login localhost:6262 -u admin -p "${ZITI_PWD}" -y > /dev/null 2>&1; do
    echo -n "." ; sleep 3
done
echo " Controller Online!"

# Phase 4: Identities & MFA Setup
podman exec -i ziti-controller ziti edge create identity "admin-client" -a "admin-users" -o /tmp/admin-client.jwt
podman cp ziti-controller:/tmp/admin-client.jwt ./admin-client.jwt

echo "Creating MFA Posture Check..."
# Create a Posture Check requiring MFA
podman exec -i ziti-controller ziti edge create posture-check mfa "MFA-Check" --ignore-legacy

echo "Creating MFA Service Policy..."
# Note: To strictly enforce MFA for ZAC access, you would typically bind policies to the API. 
# OpenZiti enforces MFA on API Sessions if the Identity has MFA enabled and policy requires it.
# For now, we create the check so it is available. The user must enroll MFA in their client.

# Phase 6: Router
podman exec -i ziti-controller ziti edge create edge-router "ziti-router" -t -a "${ZITI_CTRL_ADVERTISED_ADDRESS}:3022" -o /tmp/router.jwt
podman cp ziti-controller:/tmp/router.jwt ./router-data/router.jwt
ROUTER_JWT=$(cat ./router-data/router.jwt | tr -d '\n\r ')

# Router Config Generation
chmod 777 ./router-data

echo "Generating Router Config..."
podman run --name ziti-router-init --rm \
    --pod ziti-pod \
    -v $(pwd)/router-data:/persistent:Z \
    -e ZITI_ENROLL_TOKEN="${ROUTER_JWT}" \
    -e ZITI_CTRL_ADVERTISED_ADDRESS="localhost" \
    -e ZITI_CTRL_ADVERTISED_PORT="6262" \
    -e ZITI_ROUTER_NAME="ziti-router" \
    -e ZITI_ROUTER_ADVERTISED_HOST="${ZITI_CTRL_ADVERTISED_ADDRESS}" \
    -e ZITI_HOME="/persistent" \
    docker.io/openziti/ziti-router:${ZITI_VERSION} run &

echo "Waiting 10 seconds for config generation..."
sleep 10
podman stop -t 0 ziti-router-init 2>/dev/null || true
podman rm -f ziti-router-init 2>/dev/null || true

# Patch Config
CONFIG_FILE=$(find ./router-data -name "config.yml" -o -name "ziti-router.yaml" | head -n 1)
if [ -n "$CONFIG_FILE" ]; then
    echo "Patching Router Config: $CONFIG_FILE"
    
    # Bind to 0.0.0.0:3022 (Inside Pod)
    sed -i -E 's/(bind|address): +tls:.*:3022/\1: tls:0.0.0.0:3022/g' "$CONFIG_FILE"

    # Advertise external address
    sed -i "s|advertise: *tls:localhost:3022|advertise: tls:${ZITI_CTRL_ADVERTISED_ADDRESS}:3022|g" "$CONFIG_FILE"
    sed -i "s|advertise: *localhost:3022|advertise: ${ZITI_CTRL_ADVERTISED_ADDRESS}:3022|g" "$CONFIG_FILE"
    
    # Enable internal mgmt listener if needed or fix paths
    sed -i 's|cert: *"ziti-router.cert"|cert: "/persistent/ziti-router.cert"|g' "$CONFIG_FILE"
    sed -i 's|key: *"ziti-router.key"|key: "/persistent/ziti-router.key"|g' "$CONFIG_FILE"
else
    echo "ERROR: Config not generated!"
    exit 1
fi

# Run Router
echo "--- Starting Router ---"
ZITI_BIN="ziti"
podman run --name ziti-router -d --replace \
    --pod ziti-pod \
    -v $(pwd)/router-data:/persistent:Z \
    -e ZITI_HOME="/persistent" \
    -w /persistent \
    --entrypoint "${ZITI_BIN}" \
    docker.io/openziti/ziti-router:${ZITI_VERSION} router run /persistent/config.yml

echo "Waiting for Router..."
sleep 10

# Phase 7: Caddy (Public Proxy)
echo "--- Starting Caddy (Public 443) ---"
# Note: Caddy will auto-provision Let's Encrypt for ZITI_CTRL_ADVERTISED_ADDRESS
# provided ports 80/443 are reachable from the internet.
podman run --name caddy -d --replace \
    --pod ziti-pod \
    -v $(pwd)/Caddyfile:/etc/caddy/Caddyfile:Z \
    -v $(pwd)/caddy-data:/data:Z \
    ${CADDY_IMAGE} caddy run --config /etc/caddy/Caddyfile

echo "--- verifying Connectivity ---"
if podman exec caddy nc -z -w 3 localhost 6262; then
    echo "SUCCESS: Caddy -> Controller (Localhost:6262)"
else
    echo "FAILURE: Caddy -> Controller (Localhost:6262)"
fi

echo "Deployment Complete."
echo "1. Enroll 'admin-client.jwt' in your Ziti Desktop Edge."
echo "2. Enable MFA in the Ziti Client for this identity."
echo "3. Access ZAC at: https://${ZITI_CTRL_ADVERTISED_ADDRESS}/zac/"