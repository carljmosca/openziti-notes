#!/bin/bash
set -e

# Setup Logging
LOG_FILE="deploy-ziti-$(date +%Y%m%d-%H%M%S).log"
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
CADDY_IMAGE="docker.io/carljmosca/ziti-caddy:1.0.0"

# 1. Clean up old runs
echo "--- Cleaning up previous runs ---"

echo "========================================================="
echo " Deploying zitified OpenZiti in Podman POD 'ziti-pod'"
echo " Any firewalls must allow: TCP 6262 and 3022"
echo "========================================================="

# Phase 1: Reset & Pod Creation
podman pod rm -f ziti-pod 2>/dev/null || true
podman rm -f ziti-controller ziti-router caddy 2>/dev/null || true
podman network rm -f ziti-stack_ziti-net 2>/dev/null || true
rm -rf ./controller-data ./router-data caddy-identity.json *.jwt *.json Caddyfile
mkdir -p ./controller-data ./router-data

echo "--- Creating Pod 'ziti-pod' ---"
# We map the ports at the POD level, so all containers share localhost and these ports.
# We also map zt.moscaville.com to 127.0.0.1 for the whole pod, so Caddy (and Router) resolve own address to localhost.
podman pod create --name ziti-pod \
    -p "${ZITI_CTRL_ADVERTISED_PORT}:${ZITI_CTRL_ADVERTISED_PORT}" \
    -p "${ZITI_ROUTER_ADVERTISED_PORT}:3022" \
    --add-host "${ZITI_CTRL_ADVERTISED_ADDRESS}:127.0.0.1"

# Phase 2: Caddyfile
cat <<EOF > ./Caddyfile
{
    debug
    servers {
        protocols h1 h2
    }
}
:80 {
    bind ziti/zac-service@/etc/caddy/caddy-identity.json
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
until podman exec ziti-controller ziti edge login localhost:"${ZITI_CTRL_ADVERTISED_PORT}" -u admin -p "${ZITI_PWD}" -y > /dev/null 2>&1; do
    echo -n "." ; sleep 3
done
echo " Controller Online!"

# Phase 4: Identities
podman exec -i ziti-controller ziti edge create identity "caddy-server" -a "admin-users" -o /tmp/caddy.jwt
podman exec -i ziti-controller ziti edge enroll /tmp/caddy.jwt -o /tmp/caddy.json
podman cp ziti-controller:/tmp/caddy.json ./caddy-identity.json

podman exec -i ziti-controller ziti edge create identity "admin-gold" -a "admin-users" -o /tmp/admin-gold.jwt
podman cp ziti-controller:/tmp/admin-gold.jwt ./admin-gold.jwt

# Patch caddy-identity.json to use localhost for management (inside Pod)
echo "Patching caddy-identity.json to use https://localhost:6262..."
sed -i "s|${ZITI_CTRL_ADVERTISED_ADDRESS}|localhost|g" ./caddy-identity.json

# Phase 5: Policies
podman exec -i ziti-controller ziti edge create config "zac-host" host.v1 "{\"protocol\":\"tcp\", \"address\":\"localhost\", \"port\":6262}"
podman exec -i ziti-controller ziti edge create config "zac-dns" intercept.v1 "{\"protocols\":[\"tcp\"],\"addresses\":[\"100.64.0.10\", \"zac.internal\"],\"portRanges\":[{\"low\":80, \"high\":80}]}"
podman exec -i ziti-controller ziti edge create service "zac-service" --configs "zac-host","zac-dns"
podman exec -i ziti-controller ziti edge create service-policy "all-dial" Dial --identity-roles "#all" --service-roles "#all"
podman exec -i ziti-controller ziti edge create service-policy "all-bind" Bind --identity-roles "#all" --service-roles "#all"
podman exec -i ziti-controller ziti edge create edge-router-policy "all-routers" --edge-router-roles "#all" --identity-roles "#all"
podman exec -i ziti-controller ziti edge create service-edge-router-policy "all-services" --edge-router-roles "#all" --service-roles "#all"

# Phase 6: Router
podman exec -i ziti-controller ziti edge create edge-router "ziti-router" -t -a "${ZITI_CTRL_ADVERTISED_ADDRESS}:${ZITI_ROUTER_ADVERTISED_PORT}" -o /tmp/router.jwt
podman cp ziti-controller:/tmp/router.jwt ./router-data/router.jwt
ROUTER_JWT=$(cat ./router-data/router.jwt | tr -d '\n\r ')

# Router Config Generation (using temp container in pod? No, just run it)
chmod 777 ./router-data

echo "Generating Router Config..."
podman run --name ziti-router-init --rm \
    --pod ziti-pod \
    -v $(pwd)/router-data:/persistent:Z \
    -e ZITI_ENROLL_TOKEN="${ROUTER_JWT}" \
    -e ZITI_CTRL_ADVERTISED_ADDRESS="localhost" \
    -e ZITI_CTRL_ADVERTISED_PORT="${ZITI_CTRL_ADVERTISED_PORT}" \
    -e ZITI_ROUTER_NAME="ziti-router" \
    -e ZITI_ROUTER_ADVERTISED_HOST="${ZITI_CTRL_ADVERTISED_ADDRESS}" \
    -e ZITI_ROUTER_CSR_SANS_DNS="${ZITI_CTRL_ADVERTISED_ADDRESS}" \
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
    
    # Fix paths
    sed -i 's|cert: *"ziti-router.cert"|cert: "/persistent/ziti-router.cert"|g' "$CONFIG_FILE"
    sed -i 's|key: *"ziti-router.key"|key: "/persistent/ziti-router.key"|g' "$CONFIG_FILE"
else
    echo "ERROR: Config not generated!"
    exit 1
fi

# Run Router
echo "--- Starting Router ---"
ZITI_BIN="ziti" # Simplify, we know the image
podman run --name ziti-router -d --replace \
    --pod ziti-pod \
    -v $(pwd)/router-data:/persistent:Z \
    -e ZITI_HOME="/persistent" \
    -w /persistent \
    --entrypoint "${ZITI_BIN}" \
    docker.io/openziti/ziti-router:${ZITI_VERSION} router run /persistent/config.yml

echo "Waiting for Router..."
sleep 10

# Phase 7: Caddy
echo "--- Starting Caddy ---"
# Map external domain to 127.0.0.1 (Inside Pod, same as Router)
podman run --name caddy -d --replace \
    --pod ziti-pod \
    -v $(pwd)/Caddyfile:/etc/caddy/Caddyfile:Z \
    -v $(pwd)/caddy-identity.json:/etc/caddy/caddy-identity.json:Z \
    ${CADDY_IMAGE} caddy run --config /etc/caddy/Caddyfile

echo "--- verifying Connectivity ---"
if podman exec caddy nc -z -w 3 localhost 6262; then
    echo "SUCCESS: Caddy -> Controller (Localhost:6262)"
else
    echo "FAILURE: Caddy -> Controller (Localhost:6262)"
fi

if podman exec caddy nc -z -w 3 localhost 3022; then
    echo "SUCCESS: Caddy -> Router (Localhost:3022)"
else
    echo "FAILURE: Caddy -> Router (Localhost:3022)"
fi

echo "Enroll using admin-gold.jwt on your system."
echo "DONE. Access: http://100.64.0.10/zac/"