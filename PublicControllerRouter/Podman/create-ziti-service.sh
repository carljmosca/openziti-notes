#!/bin/bash
set -e

# 1. Configuration
SERVICE_NAME="wizard-service"
SERVER_IDENTITY="spring-boot-server"
CLIENT_ROLE="mobile-users"
ZITI_DIR="$HOME/$PROJECT_NAME"

echo "--- Phase 1: Creating Identities ---"
# Create the identity for the Spring Boot server
podman exec ziti-controller ziti edge create identity device "$SERVER_IDENTITY" -a "wizard-servers" -o "/persistent/$SERVER_IDENTITY.jwt"

echo "--- Phase 2: Creating the Service ---"
# Create the service that defines the 'wizard' application on the fabric
podman exec ziti-controller ziti edge create service "$SERVICE_NAME" --encryption required

echo "--- Phase 3: Creating Policies (The 'Bind' and 'Dial') ---"
# 1. Bind Policy: Allows the Spring Boot server to 'host' the service
podman exec ziti-controller ziti edge create service-policy "${SERVICE_NAME}-bind" Bind \
    --service-roles "@${SERVICE_NAME}" \
    --identity-roles "#wizard-servers"

# 2. Dial Policy: Allows mobile users to 'connect' to the service
podman exec ziti-controller ziti edge create service-policy "${SERVICE_NAME}-dial" Dial \
    --service-roles "@${SERVICE_NAME}" \
    --identity-roles "#${CLIENT_ROLE}"

# 3. Edge Router Policy: Ensures the identities can reach the router
podman exec ziti-controller ziti edge create edge-router-policy "${SERVICE_NAME}-router-policy" \
    --edge-router-roles "#all" \
    --identity-roles "#wizard-servers,#${CLIENT_ROLE}"

# 4. Service Router Policy: Connects the service to the router
podman exec ziti-controller ziti edge create service-edge-router-policy "${SERVICE_NAME}-serp" \
    --edge-router-roles "#all" \
    --service-roles "@${SERVICE_NAME}"

echo "--- Phase 4: Enrolling the Server Identity ---"
# We'll use the Ziti CLI to enroll the JWT into a JSON identity file for the SDK
# Note: This is done on the host for easy access during Java development
podman exec ziti-controller ziti edge enroll "/persistent/$SERVER_IDENTITY.jwt" -o "/persistent/$SERVER_IDENTITY.json"

echo "--- Success ---"
echo "Spring Boot Identity File: $ZITI_DIR/controller-data/$SERVER_IDENTITY.json"