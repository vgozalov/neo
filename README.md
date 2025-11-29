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
./setup.sh infra up          # Traefik + Portainer
./setup.sh secondary up      # n8n, Audiobookshelf, Odoo, TradeTally
```

What happens:
1. Prompts for main domain, Cloudflare credentials, dashboard/login info, database passwords, etc.
2. Writes `.env` files for every stack (values are shell-escaped, so secrets stay intact when sourced)
3. Ensures the shared overlay networks (`web`, `backend`, `monitoring`) exist or are recreated if corrupted
4. Deploys the selected stacks through `docker stack deploy`

### Useful Commands

| Command | Description |
| --- | --- |
| `./setup.sh infra up` | Configure + deploy Traefik and Portainer |
| `./setup.sh infra down` | Remove both stacks |
| `./setup.sh traefik up` | Configure + deploy Traefik only |
| `./setup.sh traefik down` | Remove Traefik |
| `./setup.sh portainer up` | Configure + deploy Portainer only |
| `./setup.sh portainer down` | Remove Portainer |
| `./setup.sh secondary up` | Configure + deploy all secondary stacks (n8n, Audiobookshelf, Odoo, TradeTally) |
| `./setup.sh secondary single` | Interactive picker to deploy any one stack |
| `./setup.sh status` | Show stacks, services, networks |
| `./setup.sh logs <service>` | Follow Swarm service logs |
| `./setup.sh networks` | Ensure overlay networks exist (create any missing) |
| `./setup.sh networks reset` | Delete and recreate overlay networks |
| `./setup.sh` | Launch interactive 1-9 menu |

### Interactive Menu

Running `./setup.sh` with no arguments opens the classic numbered menu:

| Option | Action |
| --- | --- |
| 1 | Deploy Traefik |
| 2 | Deploy Portainer |
| 3 | Deploy all infrastructure |
| 4 | Deploy all secondary stacks (n8n, Audiobookshelf, Odoo, TradeTally) |
| 5 | Deploy a single stack (picker lists everything in `stacks/`) |
| 6 | List stacks |
| 7 | Show status (stacks, services, networks) |
| 8 | Remove a specific stack |
| 9 | Remove all infrastructure (Portainer + Traefik) |
| 10 | View service logs |
| 11 | Ensure overlay networks exist (create missing ones) |
| 12 | Reset overlay networks (delete + recreate) |
| 13 | Exit |

Each deployment option prompts for configuration (domain, Cloudflare token, etc.) with defaults already filled in.

> `setup.sh` automatically ensures the shared overlay networks (web/backend/monitoring) exist before running any commands.

## Supported Stacks

| Stack | Purpose |
| --- | --- |
| Traefik | Reverse proxy, TLS termination, dashboard with basic auth |
| Portainer | Docker Swarm UI / management |
| n8n | Workflow automation + Postgres |
| Audiobookshelf | Audiobook & podcast server |
| Odoo AVVA | Odoo ERP + dedicated Postgres |
| TradeTally | Trade management app + Postgres + Redis |

All secondary stacks share the `web` overlay for public routing (Traefik) and also create an internal overlay for their databases/services. Each configure prompt collects the required secrets (DB passwords, basic auth credentials, secret keys, etc.) and writes `.env` files in their stack directories.

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

## Network Topology

Three overlay networks are managed automatically and reused by every stack:

| Name | Subnet | Gateway | Flags |
| --- | --- | --- | --- |
| `web` | `10.0.0.0/24` | `10.0.0.1` | overlay, attachable, encrypted |
| `backend` | `10.1.0.0/24` | `10.1.0.1` | overlay, internal, encrypted |
| `monitoring` | `10.2.0.0/24` | `10.2.0.1` | overlay, attachable, encrypted |

Use `./setup.sh networks` to create any missing networks, or `./setup.sh networks reset` to drop and recreate them. Existing networks with these names are reused by default; set `RECREATE_NETWORKS=true ./setup.sh networks` to force a rebuild without using the reset command.  
The command also recreates Docker's ingress network if it was removed.

**Important:** do not delete the built-in `bridge`, `host`, `none`, `docker_gwbridge`, or `ingress` networks manually. If `ingress` is missing, run `./setup.sh networks` to bring it back.

## Directory Layout

```
neo/
├── helpers/
│   └── common.sh         # shared shell helpers + network creation
├── setup.sh              # single entry point / interactive menu
└── stacks/
    ├── audiobookshelf/
    │   ├── docker-compose.yml
    │   └── environment.example
    ├── n8n/
    │   ├── docker-compose.yml
    │   └── environment.example
    ├── odoo_avva/
    │   ├── docker-compose.yml
    │   ├── environment.example
    │   └── config/odoo.conf.example
    ├── tradetally/
    │   ├── docker-compose.yml
    │   └── environment.example
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
- Error `service needs ingress network` → run `./setup.sh networks` (recreates Docker's ingress overlay)
- Network definitions stale → run `./setup.sh networks reset` (or `RECREATE_NETWORKS=true ./setup.sh networks`) to drop and rebuild the shared overlays

## Notes

- Traefik dashboard is protected with HTTP Basic Auth generated during setup.
- Portainer admin password is created inside the web UI after initial deployment.
- Re-run `./setup.sh infra up` anytime to regenerate configs and redeploy.

