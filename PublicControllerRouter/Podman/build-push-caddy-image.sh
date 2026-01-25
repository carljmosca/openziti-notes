#!/bin/bash
set -e

REPO="docker.io/carljmosca/ziti-caddy"
TAG="1.0.0"

# 1. Clean slate
echo "--- Cleaning up old manifests ---"
podman manifest rm $REPO:$TAG 2>/dev/null || true
podman rmi -f $REPO:$TAG 2>/dev/null || true

# 2. Create the manifest
echo "--- Creating Manifest: $REPO:$TAG ---"
podman manifest create $REPO:$TAG

# 3. Build AMD64 (x86_64)
echo "--- Building linux/amd64 ---"
podman build --platform linux/amd64 --manifest $REPO:$TAG -f Dockerfile.caddy .

# 4. Build ARM64 (aarch64)
echo "--- Building linux/arm64 ---"
podman build --platform linux/arm64 --manifest $REPO:$TAG -f Dockerfile.caddy .

# 5. Push
echo "--- Pushing Multi-Arch Manifest ---"
podman manifest push --all $REPO:$TAG docker://$REPO:$TAG

echo "Done."