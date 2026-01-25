# OpenZiti Public Deployment (Podman with Let's Encrypt)

This directory contains a "Conventional" deployment of OpenZiti where the Controller is publicly accessible on **Port 443** (HTTPS), secured automatically by **Let's Encrypt** certificates via Caddy.

This setup is ideal for standard deployments where you want easy, public API access to the controller but still enforce Zero Trust principles (MFA) for access.

## Architecture

The deployment uses a **Podman Pod** (`ziti-pod`) to enable shared networking between components.

1.  **Caddy (Frontend)**:
    *   Listens on Public Ports `80` and `443`.
    *   Handles ACME (Let's Encrypt) challenges automatically.
    *   Proxies `https://<domain>/` to the Ziti Controller.
2.  **Ziti Controller**:
    *   Listens natively on `6262` (Internal Level).
    *   Advertises itself as `<domain>:443` (Public Level).
3.  **Ziti Edge Router**:
    *   Listens on Public Port `3022`.
    *   Handles data plane traffic.

## MFA Requirement
This deployment script creates a **Ziti Posture Check (MFA)**. To secure access to the Ziti Admin Console (ZAC), you must enroll MFA on your admin identity after setup.

## Prerequisites

1.  **Public DNS**: You MUST have a public DNS record (A Record) pointing to this host (e.g., `zt.example.com`). This is required for Let's Encrypt validation.
2.  **Ports**: Ensure Firewall allows `80/tcp`, `443/tcp`, and `3022/tcp`.
3.  **Rootless Podman Ports**:
    By default, rootless users cannot bind ports < 1024. To allow binding 80/443, run:
    ```bash
    sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
    ```
    (Or create the file `/etc/sysctl.d/ports.conf` with `net.ipv4.ip_unprivileged_port_start=80`).

### Alternative: DNS Validation (No Port 80)
If you cannot open Port 80 or prefer **DNS-01 Validation**:
1.  You must build a custom Caddy image including your DNS provider's plugin (e.g., `github.com/caddy-dns/cloudflare`).
2.  Update `deploy-ziti.sh` to use your custom image.
3.  Add necessary API Key environment variables (e.g., `CLOUDFLARE_API_TOKEN`) to the Caddy `run` command.
4.  Update `Caddyfile` to specify `tls { dns cloudflare ... }`.

## Deployment

1.  **Configure Environment**:
    ```bash
    cp .env.example .env
    nano .env
    # Set ZITI_CTRL_ADVERTISED_ADDRESS to your Public FQDN (e.g. zt.example.com)
    # Set ZITI_PWD
    ```

2.  **Run Deploy Script**:
    ```bash
    ./deploy-ziti.sh
    ```
    *Note: This will perform a fresh install, wiping `controller-data` and `router-data` in this directory.*

3.  **Enroll & Secure**:
    *   Retrieve the enrollment token: `ls -l admin-client.jwt`.
    *   Enroll using the **Ziti Desktop Edge** (ZDE).
    *   **ENABLE MFA**: In the ZDE, go to the identity settings and "Enroll MFA".
    *   Open `https://<your-domain>/zac/` in a browser.

## Maintenance

*   **Logs**: `deploy-ziti-public-*.log`.
*   **Teardown**: `./teardown.sh`.