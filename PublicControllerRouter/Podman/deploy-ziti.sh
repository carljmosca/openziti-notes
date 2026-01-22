#!/bin/bash
set -e

# 1. Environment Refresh
[ -f .env ] && export $(grep -v '^#' .env | xargs) || { echo "No .env file found"; exit 1; }
ZITI_DIR="$HOME/$PROJECT_NAME"

echo "--- Phase 1: Total Wipe & Reclaim ---"
# Force-remove existing containers to free up names
podman-compose down 2>/dev/null || true
podman rm -f ziti-controller ziti-router caddy 2>/dev/null || true

# Reclaim folder ownership before wiping
sudo chown -R $USER:$USER "$ZITI_DIR" 2>/dev/null || true
rm -rf "$ZITI_DIR/controller-data" "$ZITI_DIR/router-data" "$ZITI_DIR/caddy_data"

echo "--- Phase 2: Host-Owned Directory Prep ---"
# Create dirs as host user (e.g.; ubuntu) so we can write the JWT via pipe later
mkdir -p "$ZITI_DIR"/{controller-data,router-data,caddy_data}
sudo chown -R $USER:$USER "$ZITI_DIR"
cp compose.yaml Caddyfile "$ZITI_DIR/" && cd "$ZITI_DIR"

# 3. Kernel Tuning
[ $(sysctl -n net.ipv4.ip_unprivileged_port_start) -gt 80 ] && \
    sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80

echo "--- Phase 3: Booting Infrastructure ---"
# --force-recreate ensures we never hit "name already in use" errors
podman-compose up -d --force-recreate ziti-controller caddy

echo "Waiting for Edge API..."
until $(curl -k -s -f -o /dev/null https://$ZITI_DOMAIN/edge/management/v1/version); do
    printf '.' && sleep 5
done

# 4. Phase 4: Identity Management (Host Context)
echo -e "\nLogging in..."
MAX_RETRIES=10
COUNT=0
# Using 127.0.0.1 to match the default certificate SANs
until podman exec ziti-controller ziti edge login 127.0.0.1:1280 -u "$ZITI_USER" -p "$ZITI_PWD" -y > /dev/null 2>&1; do
    printf '🔑' && sleep 5
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then echo "Login timeout"; exit 1; fi
done

echo "Capturing JWT via Pipe (Host Ownership)..."
podman exec ziti-controller ziti edge delete edge-router "client-router" 2>/dev/null || true

# Capture the token while the directory is still host-writable
podman exec ziti-controller ziti edge create edge-router "client-router" -t -o /dev/stdout | grep -v "New edge router" | tr -d '\r' > "$ZITI_DIR/router-data/client-router.jwt"

echo "Handing off ownership to Container UID 1001..."
# Final flip: Containers now have full ownership of their data volumes
podman unshare chown -R 1001:1001 "$ZITI_DIR/controller-data" "$ZITI_DIR/router-data"

# 5. Phase 5: Enrollment
echo "Starting Router..."
podman-compose up -d --force-recreate ziti-router

# 6. Phase 6: Persistence (Systemd & Linger)
echo "--- Finalizing Persistence ---"
# Ensure the user systemd directory exists
mkdir -p ~/.config/systemd/user/

for svc in ziti-controller ziti-router caddy; do
    # Generate systemd files and move to the user config dir
    podman generate systemd --name $svc --files --new > /dev/null
    mv container-$svc.service ~/.config/systemd/user/
    systemctl --user enable --now container-$svc.service
done

systemctl --user daemon-reload
sudo loginctl enable-linger $USER

echo "--- Final Fabric Status ---"
sleep 10
podman exec -it ziti-controller ziti edge list edge-routers

echo "--- Phase 7: Automating Dark Management (Zitification) ---"

# 1. Create the Service
podman exec ziti-controller ziti edge create service "ziti-console" --encryption required >/dev/null 2>&1 || true

# 2. Create Intercept Config (for your Mac/Laptop)
podman exec ziti-controller ziti edge create config "ziti-console-intercept" intercept.v1 \
    "{\"protocols\":[\"tcp\"],\"addresses\":[\"$ZITI_DOMAIN\"],\"portRanges\":[{\"low\":443, \"high\":443}]}" >/dev/null 2>&1 || true

# 3. Create Host Config (for the Router offload)
podman exec ziti-controller ziti edge create config "ziti-console-host" host.v1 \
    "{\"protocol\":\"tcp\", \"address\":\"ziti-controller\", \"port\":1280}" >/dev/null 2>&1 || true

# 4. Link Configs to Service
podman exec ziti-controller ziti edge update service "ziti-console" --configs "ziti-console-intercept","ziti-console-host"

# 5. Create Policies
# Bind: Allows the router to host the API
podman exec ziti-controller ziti edge create service-policy "ziti-console-bind" Bind \
    --service-roles "@ziti-console" --identity-roles "#all" >/dev/null 2>&1 || true

# Dial: Allows ALL identities (or a specific admin role) to dial the API
podman exec ziti-controller ziti edge create service-policy "ziti-console-dial" Dial \
    --service-roles "@ziti-console" --identity-roles "#all" >/dev/null 2>&1 || true

echo "--- Phase 8: Persistence ---"
# ... [Systemd/Linger logic] ...

echo "--- DEPLOYMENT COMPLETE & ZITIFIED ---"
echo "Public Port 443 can now be closed. Access ZAC via Ziti Desktop Edge."
echo "Access ZAC via: https://$ZITI_DOMAIN"