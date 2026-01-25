#!/bin/bash
set -e

# Setup Logging
LOG_FILE="deploy-ziti.log"
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
CADDY_IMAGE="docker.io/carljmosca/ziti-caddy:latest"

# 1. Clean up old runs
echo "--- Cleaning up previous runs ---"

echo "========================================================="
echo " Deploying zitified OpenZiti (port 6262 only)"
echo " Any firewalls must allow: TCP 6262 and 3022"
echo "========================================================="

# Phase 1: Reset
podman rm -f ziti-controller ziti-router caddy 2>/dev/null || true
podman network rm -f ziti-stack_ziti-net 2>/dev/null || true
rm -rf ./controller-data ./router-data caddy-identity.json *.jwt *.json Caddyfile
mkdir -p ./controller-data ./router-data
podman network create ziti-stack_ziti-net

# Phase 2: Caddyfile (Simplified for Binding)
cat <<EOF > ./Caddyfile
{
    debug
    servers {
        protocols h1 h2
    }
}
:80 {
    bind ziti/zac-service@/etc/caddy/caddy-identity.json
    reverse_proxy https://ziti-controller:${ZITI_CTRL_ADVERTISED_PORT} {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF

# Phase 3: Controller
podman run --name ziti-controller -d --replace \
    --net ziti-stack_ziti-net --network-alias ziti-controller \
    --add-host "${ZITI_CTRL_ADVERTISED_ADDRESS}:127.0.0.1" \
    -e ZITI_PWD="${ZITI_PWD}" \
    -e ZITI_CTRL_ADVERTISED_ADDRESS="${ZITI_CTRL_ADVERTISED_ADDRESS}" \
    -e ZITI_CTRL_ADVERTISED_PORT="${ZITI_CTRL_ADVERTISED_PORT}" \
    -e ZITI_CTRL_EDGE_ADVERTISED_PORT="${ZITI_CTRL_ADVERTISED_PORT}" \
    -v $(pwd)/controller-data:/persistent:Z \
    -p "${ZITI_CTRL_ADVERTISED_PORT}:${ZITI_CTRL_ADVERTISED_PORT}" \
    docker.io/openziti/ziti-controller:${ZITI_VERSION}

echo "Waiting for Controller..."
until podman exec ziti-controller ziti edge login localhost:"${ZITI_CTRL_ADVERTISED_PORT}" -u admin -p "${ZITI_PWD}" -y > /dev/null 2>&1; do
    echo -n "." ; sleep 3
done

# Phase 4: Identities
podman exec -i ziti-controller ziti edge create identity "caddy-server" -a "admin-users" -o /tmp/caddy.jwt
podman exec -i ziti-controller ziti edge enroll /tmp/caddy.jwt -o /tmp/caddy.json
podman cp ziti-controller:/tmp/caddy.json ./caddy-identity.json
podman exec -i ziti-controller ziti edge create identity "mac-m4-gold" -a "admin-users" -o /tmp/mac-m4-gold.jwt
podman cp ziti-controller:/tmp/mac-m4-gold.jwt ./mac-m4-gold.jwt

# Phase 5: Policies
podman exec -i ziti-controller ziti edge create config "zac-host" host.v1 "{\"protocol\":\"tcp\", \"address\":\"ziti-controller\", \"port\":$ZITI_CTRL_ADVERTISED_PORT}"
podman exec -i ziti-controller ziti edge create config "zac-dns" intercept.v1 "{\"protocols\":[\"tcp\"],\"addresses\":[\"100.64.0.10\"],\"portRanges\":[{\"low\":80, \"high\":80}]}"
podman exec -i ziti-controller ziti edge create service "zac-service" --configs "zac-host","zac-dns"
podman exec -i ziti-controller ziti edge create service-policy "all-dial" Dial --identity-roles "#all" --service-roles "#all"
podman exec -i ziti-controller ziti edge create service-policy "all-bind" Bind --identity-roles "#all" --service-roles "#all"
podman exec -i ziti-controller ziti edge create edge-router-policy "all-routers" --edge-router-roles "#all" --identity-roles "#all"
podman exec -i ziti-controller ziti edge create service-edge-router-policy "all-services" --edge-router-roles "#all" --service-roles "#all"

# Phase 6: Router
# Phase 6: Router
podman exec -i ziti-controller ziti edge create edge-router "ziti-router" -t -a "${ZITI_CTRL_ADVERTISED_ADDRESS}:${ZITI_ROUTER_ADVERTISED_PORT}" -o /tmp/router.jwt
podman cp ziti-controller:/tmp/router.jwt ./router-data/router.jwt
ROUTER_JWT=$(cat ./router-data/router.jwt | tr -d '\n\r ')

# Hack: Patch the generated config to bind 0.0.0.0 instead of the domain
echo "Patching Router Config binding..."

# 1. Remove previous container to clear name
podman rm -f ziti-router 2>/dev/null || true

# 2. Init Config (internal run) - Generates config file
# Ensure router-data is writable by the container user
chmod 777 ./router-data

# We start the router briefly. The entrypoint script will generate the config file.
# We then stop it so we can patch the config.
podman run --name ziti-router-init --rm \
    -v $(pwd)/router-data:/persistent:Z \
    -e ZITI_ENROLL_TOKEN="${ROUTER_JWT}" \
    -e ZITI_CTRL_ADVERTISED_ADDRESS="ziti-controller" \
    -e ZITI_CTRL_ADVERTISED_PORT="${ZITI_CTRL_ADVERTISED_PORT}" \
    -e ZITI_ROUTER_NAME="ziti-router" \
    -e ZITI_ROUTER_ADVERTISED_HOST="${ZITI_CTRL_ADVERTISED_ADDRESS}" \
    -e ZITI_ROUTER_CSR_SANS_DNS="${ZITI_CTRL_ADVERTISED_ADDRESS}" \
    -e ZITI_HOME="/persistent" \
    docker.io/openziti/ziti-router:${ZITI_VERSION} run &

PID=$!
echo "Waiting 5 seconds for config generation..."
sleep 5
podman stop -t 0 ziti-router-init 2>/dev/null || true
# If we used --rm, it should be gone. If not, rm it.
podman rm -f ziti-router-init 2>/dev/null || true

# 3. Patch Config
CONFIG_FILE=$(find ./router-data -name "config.yml" -o -name "ziti-router.yaml" | head -n 1)
if [ -n "$CONFIG_FILE" ]; then
    echo "Found config file: $CONFIG_FILE"
    echo "--- Config BEFORE Patch ---"
    cat "$CONFIG_FILE"
    echo "---------------------------"
    
    # Replace bind/address ports from 3022 to 10080 (Container Port)
    # Handle multiple spaces after key
    sed -i -E 's/(bind|address): +tls:.*:3022/\1: tls:0.0.0.0:10080/g' "$CONFIG_FILE"

    # Fix ADVERTISE address.
    # explicit match to avoid CSR
    sed -i "s|advertise: *tls:localhost:3022|advertise: tls:${ZITI_CTRL_ADVERTISED_ADDRESS}:3022|g" "$CONFIG_FILE"
    sed -i "s|advertise: *localhost:3022|advertise: ${ZITI_CTRL_ADVERTISED_ADDRESS}:3022|g" "$CONFIG_FILE"
    
    # Fix relative cert path just in case
    sed -i 's|cert: *"ziti-router.cert"|cert: "/persistent/ziti-router.cert"|g' "$CONFIG_FILE"
    
    echo "--- Config AFTER Patch ---"
    grep -E "(bind|address|advertise|cert:)" "$CONFIG_FILE"
    echo "--------------------------"
    echo "Config patched to bind 0.0.0.0:10080"
else
    echo "WARNING: Config not found in ./router-data (Checked config.yml and ziti-router.yaml). Patch skipped."
    ls -R ./router-data
fi

echo "--- Router Data Directory Contents ---"
ls -R ./router-data
echo "--------------------------------------"

# Find where the ziti binary is
# We check common locations because 'which' might be missing in minimal images
ZITI_BIN=$(podman run --rm --entrypoint /bin/sh docker.io/openziti/ziti-router:${ZITI_VERSION} -c "ls /usr/local/bin/ziti /var/openziti/ziti-bin/ziti /openziti/ziti 2>/dev/null | head -n 1")

if [ -z "$ZITI_BIN" ]; then
    echo "WARNING: Could not find 'ziti' binary in common locations. Defaulting to 'ziti' (PATH lookup)."
    ZITI_BIN="ziti"
else
    # Config patch might have messed up newlines? Clean it.
    ZITI_BIN=$(echo "$ZITI_BIN" | tr -d '[:space:]')
    echo "Found ziti binary at: $ZITI_BIN"
fi

# 4. Run for real
podman run --name ziti-router -d --replace --net ziti-stack_ziti-net \
    --add-host "${ZITI_CTRL_ADVERTISED_ADDRESS}:$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ziti-controller)" \
    -v $(pwd)/router-data:/persistent:Z -p "${ZITI_ROUTER_ADVERTISED_PORT}:10080" \
    -e ZITI_HOME="/persistent" \
    -w /persistent \
    --entrypoint "${ZITI_BIN}" \
    docker.io/openziti/ziti-router:${ZITI_VERSION} router run /persistent/config.yml

echo "Waiting 10 seconds for Router to initialize..."
sleep 10

# Phase 7: Caddy
# Attempt to get the gateway IP of the ziti-net bridge
NETWORK_GATEWAY=$(podman network inspect ziti-stack_ziti-net -f '{{(index .Subnets 0).Gateway}}' 2>/dev/null || echo "")

# Fallback: If empty (json parsing failed), assume standard Podman gateway or try another method
if [ -z "$NETWORK_GATEWAY" ]; then
    echo "WARNING: Could not detect gateway automatically. Defaulting to 10.89.0.1"
    NETWORK_GATEWAY="10.89.0.1"
fi
echo "Using Network Gateway: $NETWORK_GATEWAY for zt.moscaville.com mapping"

podman run --name caddy -d --replace --net ziti-stack_ziti-net \
    --add-host "${ZITI_CTRL_ADVERTISED_ADDRESS}:$NETWORK_GATEWAY" \
    -v $(pwd)/Caddyfile:/etc/caddy/Caddyfile:Z \
    -v $(pwd)/caddy-identity.json:/etc/caddy/caddy-identity.json:Z \
    ${CADDY_IMAGE} caddy run --config /etc/caddy/Caddyfile

echo "--- Verifying Caddy Connectivity ---"
podman exec caddy cat /etc/hosts | grep "${ZITI_CTRL_ADVERTISED_ADDRESS}"
echo "------------------------------------"
if podman exec caddy nc -z -w 3 "$ZITI_CTRL_ADVERTISED_ADDRESS" 6262; then
    echo "SUCCESS: Caddy can reach Controller (6262)"
else
    echo "FAILURE: Caddy CANNOT reach Controller (6262)"
fi

if podman exec caddy nc -z -w 3 "$ZITI_CTRL_ADVERTISED_ADDRESS" 3022; then
    echo "SUCCESS: Caddy can reach Router (3022)"
else
    echo "FAILURE: Caddy CANNOT reach Router (3022)"
    echo "Troubleshooting: Check Host Firewall (UFW/Firewalld) allowing access from ${NETWORK_GATEWAY}"
    echo "--- Debug Info ---"
    echo "Caddy thinks zt.moscaville.com is:"
    podman exec caddy cat /etc/hosts | grep "${ZITI_CTRL_ADVERTISED_ADDRESS}"
    echo "Router Container Status:"
    podman ps -a --filter name=ziti-router
    echo "Router Port Mapping (Host):"
    podman port ziti-router
    echo "Router IP (Internal):"
    podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ziti-router
    echo "--- Router Logs ---"
    podman logs --tail 20 ziti-router
fi

echo "DONE. Access: http://100.64.0.10/zac/"