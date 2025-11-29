# Minimal Swarm Infrastructure

Single entry script (`setup.sh`) that configures and deploys **Traefik** and **Portainer** on Docker Swarm.  
Helper routines live in `helpers/common.sh`; everything else is stack configuration.

## Requirements

1. Ubuntu (or any Linux) host with Docker installed
2. Docker Swarm initialized (`docker swarm init`)
3. Public domain managed in Cloudflare
4. Cloudflare API token with DNS edit permissions
5. `htpasswd` package (optional, script falls back to `openssl`)

```bash
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
sudo usermod -aG docker $USER && newgrp docker
docker swarm init
sudo apt install -y apache2-utils   # for htpasswd
```

## Quick Start

```bash
cd neo
./setup.sh infra up
```

What happens:
1. Prompts for main domain, Cloudflare credentials, and Traefik dashboard login
2. Writes `.env` files for Traefik + Portainer
3. Ensures overlay network `web` exists
4. Deploys both stacks through `docker stack deploy`

### Useful Commands

| Command | Description |
| --- | --- |
| `./setup.sh infra up` | Configure + deploy Traefik and Portainer |
| `./setup.sh infra down` | Remove both stacks |
| `./setup.sh traefik up` | Configure + deploy Traefik only |
| `./setup.sh traefik down` | Remove Traefik |
| `./setup.sh portainer up` | Configure + deploy Portainer only |
| `./setup.sh portainer down` | Remove Portainer |
| `./setup.sh status` | Show stacks, services, networks |
| `./setup.sh logs <service>` | Follow Swarm service logs |

## Configuration Prompts

Every `up` action collects:

**Traefik**
- Main domain (default `vagifgozalov.com`)
- Cloudflare email (default `webmaster@avvaagency.com`)
- Cloudflare DNS API token
- Dashboard username (default `admin`)
- Dashboard password (hidden input, required)

**Portainer**
- Main domain (reuses last answer, editable)
- Web UI port (default `9000`)
- Edge Agent port (default `8000`)

Generated secrets are stored inside stack-specific `.env` files (ignored by git).  
Traefik SSL data (`acme.json`) is created automatically with `chmod 600`.

## DNS Checklist

Add the following A records in Cloudflare pointing to your server IP:

| Name | Value | Proxy |
| --- | --- | --- |
| `traefik` | `YOUR_SERVER_IP` | Orange cloud ✅ |
| `portainer` | `YOUR_SERVER_IP` | Orange cloud ✅ |

Cloudflare SSL/TLS mode should be **Full** (not Flexible).

## Directory Layout

```
neo/
├── helpers/
│   └── common.sh         # shared shell helpers
├── setup.sh              # single entry point
└── stacks/
    ├── portainer/
    │   ├── docker-compose.yml
    │   └── environment.example
    └── traefik/
        ├── docker-compose.yml
        ├── environment.example
        ├── dynamic/
        │   ├── certs.yml
        │   └── middlewares.yml
        └── traefik.yml
```

`.env` files and `acme.json` are generated during setup and ignored by git.

## Troubleshooting

- `docker service ls` shows `0/1` replicas → check logs with `./setup.sh logs <service>`
- `curl -I http://localhost:80` fails → ensure nothing else uses ports 80/443 (`sudo ss -tulpn | grep -E ':80|:443'`)
- Cloudflare 523 errors → confirm DNS points to server IP and that firewall allows ports 80/443
- Swarm inactive → run `docker swarm init`
- Permission denied on docker socket → add user to docker group (`sudo usermod -aG docker $USER`)

## Notes

- Traefik dashboard is protected with HTTP Basic Auth generated during setup.
- Portainer admin password is created inside the web UI after initial deployment.
- Re-run `./setup.sh infra up` anytime to regenerate configs and redeploy.

