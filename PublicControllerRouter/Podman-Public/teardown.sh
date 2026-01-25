#!/bin/bash
ZITI_DIR="$HOME/ziti-stack"
read -p "DELETE all Ziti data? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl --user stop container-ziti-controller container-ziti-router container-caddy 2>/dev/null || true
    podman pod rm -f ziti-pod 2>/dev/null || true
    podman rm -f ziti-controller ziti-router caddy 2>/dev/null || true
    podman unshare rm -rf "$ZITI_DIR/controller-data" "$ZITI_DIR/router-data" "$ZITI_DIR/caddy_data"
    rm -f ~/.config/systemd/user/container-ziti-*.service ~/.config/systemd/user/container-caddy.service
    systemctl --user daemon-reload
    echo "Done."
fi