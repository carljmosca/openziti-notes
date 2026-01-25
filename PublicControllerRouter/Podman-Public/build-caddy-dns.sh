#!/bin/bash
set -e

REPO="docker.io/carljmosca/caddy-dns"
TAG="1.0.0"

echo "--- Building Caddy DNS Image (AMD64 & ARM64) ---"

# 1. Clean
podman manifest rm $REPO:$TAG 2>/dev/null || true

# 2. Create Manifest
podman manifest create $REPO:$TAG

# 3. Build AMD64
echo "Building AMD64..."
podman build --platform linux/amd64 --manifest $REPO:$TAG -f Dockerfile.caddy-dns .

# 4. Build ARM64
echo "Building ARM64..."
podman build --platform linux/arm64 --manifest $REPO:$TAG -f Dockerfile.caddy-dns .

# 5. Push
echo "Pushing..."
podman manifest push --all $REPO:$TAG docker://$REPO:$TAG

echo "Done. Image: $REPO:$TAG"
