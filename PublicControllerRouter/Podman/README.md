# OpenZiti Rootless Podman Deployment

This stack deploys a production-ready OpenZiti network backbone using Podman. It includes a Controller, an Edge Router, and a Caddy reverse-proxy for automated Let's Encrypt SSL.



## Components
- **Controller**: Manages the Ziti fabric and identity.
- **Edge Router**: Provides ingress/egress to the Ziti mesh.
- **Caddy**: Handles ACME (Let's Encrypt) challenges and secures the Edge API.

## Installation
1. Ensure your VM's public IP is mapped to your FQDN (DNS A Record).
2. Set environment variables:
   ```bash
   cp .env.example .env
   nano .env
   ```
3. Run the deployment script:
   ```bash
   chmod +x deploy-ziti.sh
   ./deploy-ziti.sh
   ```

## Backup

```bash
podman-compose down
tar -cvzf ziti-backup-$(date +%F).tar.gz ~/ziti-stack/
podman-compose up -d
```