#!/bin/bash
set -e

# 1. Environment & Path Setup
[ -f .env ] && export $(grep -v '^#' .env | xargs) || { echo "❌ No .env file found"; exit 1; }
: "${PROJECT_NAME:=ziti-stack}"
ZITI_DIR="$HOME/$PROJECT_NAME"

# Safety Check for ZITI_DIR
if [[ -z "$ZITI_DIR" || "$ZITI_DIR" == "/" ]]; then
    echo "❌ Error: ZITI_DIR is invalid. Check your .env file."
    exit 1
fi

echo "--- Phase 1: Nuclear Infrastructure Wipe ---"

# 1. Stop any active systemd units
systemctl --user stop ${PROJECT_NAME}.container 2>/dev/null || true

# 2. Aggressively remove containers by name and ID
# This specifically targets the "be518bf..." ID style error
for container in ziti-controller ziti-router caddy; do
    echo "Nuking $container..."
    podman stop -t 1 "$container" >/dev/null 2>&1 || true
    podman rm -f "$container" >/dev/null 2>&1 || true
done

# 3. Clean up lingering Podman volumes/networks associated with the project
podman volume rm $(podman volume ls -q --filter name=${PROJECT_NAME}) >/dev/null 2>&1 || true
podman network rm ${PROJECT_NAME}_default >/dev/null 2>&1 || true

# 4. Final check: if the name is STILL in use, we tell Podman to prune everything
# (This is a safety net for "Zombie" containers)
podman container prune -f >/dev/null 2>&1

echo "Phase 1 Complete: Storage is cleared."

echo "--- Phase 2: Host-Owned Directory Prep ---"
mkdir -p "$ZITI_DIR"/{controller-data,router-data,caddy_data}
sudo chown -R $USER:$USER "$ZITI_DIR"

echo "--- Phase 3: Generating Integrated Caddyfile ---"
cat <<EOF > "$ZITI_DIR/Caddyfile"
{
    email ${LE_EMAIL}
}

${ZITI_DOMAIN} {
    # Rewrite root to /zac/ for a seamless dashboard experience
    rewrite / /zac/
    
    reverse_proxy ziti-controller:1280 {
        header_up Host {upstream_hostport}
        transport http {
            tls_insecure_skip_verify
            tls_server_name ${ZITI_DOMAIN}
        }
    }
}
EOF

# Ensure the kernel allows rootless Podman to use low ports (80/443)
if [ $(sysctl -n net.ipv4.ip_unprivileged_port_start) -gt 80 ]; then
    echo "Tuning kernel for low ports..."
    sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
fi

cp compose.yaml "$ZITI_DIR/" && cd "$ZITI_DIR"

echo "--- Phase 4: Infrastructure Boot ---"
podman-compose up -d --force-recreate ziti-controller caddy

echo "Waiting for Edge API (SSL Handshake)..."
until $(curl -k -s -f -o /dev/null https://$ZITI_DOMAIN/edge/management/v1/version); do
    printf '.' && sleep 5
done

echo -e "\nLogging in locally..."
MAX_RETRIES=10
COUNT=0
until podman exec ziti-controller ziti edge login 127.0.0.1:1280 -u "$ZITI_USER" -p "$ZITI_PWD" -y > /dev/null 2>&1; do
    printf '🔑' && sleep 5
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then echo "Login timeout"; exit 1; fi
done

echo "--- Phase 5: Automating Dark Management (Zitification) ---"
podman exec ziti-controller ziti edge create service "ziti-console" --encryption ON >/dev/null 2>&1 || true
sleep 2 
podman exec ziti-controller ziti edge create config "ziti-console-intercept" intercept.v1 \
    "{\"protocols\":[\"tcp\"],\"addresses\":[\"$ZITI_DOMAIN\"],\"portRanges\":[{\"low\":443, \"high\":443}]}" >/dev/null 2>&1 || true
podman exec ziti-controller ziti edge create config "ziti-console-host" host.v1 \
    "{\"protocol\":\"tcp\", \"address\":\"ziti-controller\", \"port\":1280}" >/dev/null 2>&1 || true
podman exec ziti-controller ziti edge update service "ziti-console" --configs "ziti-console-intercept","ziti-console-host"
podman exec ziti-controller ziti edge create service-policy "ziti-console-bind" Bind --service-roles "@ziti-console" --identity-roles "#all" >/dev/null 2>&1 || true
podman exec ziti-controller ziti edge create service-policy "ziti-console-dial" Dial --service-roles "@ziti-console" --identity-roles "#all" >/dev/null 2>&1 || true

echo "--- Phase 6: Identity Capture & Permission Pivot ---"
podman exec ziti-controller ziti edge delete edge-router "client-router" >/dev/null 2>&1 || true
podman exec ziti-controller ziti edge create edge-router "client-router" -t -o /dev/stdout | grep -v "New edge router" | tr -d '\r' > "$ZITI_DIR/router-data/client-router.jwt"

# Permission Pivot: Controller/Router containers expect UID 1001
podman unshare chown -R 1001:1001 "$ZITI_DIR/controller-data" "$ZITI_DIR/router-data"

echo "--- Phase 7: Final Router Enrollment ---"
podman-compose up -d --no-recreate ziti-router

echo "--- Phase 8: Persistence via Quadlets ---"
mkdir -p ~/.config/containers/systemd/
cat <<EOF > ~/.config/containers/systemd/${PROJECT_NAME}.container
[Unit]
Description=OpenZiti Stack Managed by Quadlet
After=network-online.target

[Container]
Image=podman-compose
Exec=podman-compose -f $ZITI_DIR/compose.yaml up -d
ExecStop=podman-compose -f $ZITI_DIR/compose.yaml stop

[Install]
WantedBy=default.target
EOF

# Reload systemd to recognize the new Quadlet
systemctl --user daemon-reload
# Enable linger so services run even when you aren't SSH'd in
sudo loginctl enable-linger $USER

echo "--- 🚀 DEPLOYMENT COMPLETE ---"
echo "1. Access ZAC: https://$ZITI_DOMAIN (Auto-rewritten to /zac/)"
echo "2. OCI Action: Disable Port 443 in the Oracle Console to finalize 'Dark' mode."
