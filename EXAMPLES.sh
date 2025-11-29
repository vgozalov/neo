#!/bin/bash

##############################################################################
# Example Usage Script
# This script shows different ways to use the deployment manager
##############################################################################

# Scenario 1: First time deployment - Deploy everything
echo "=== Scenario 1: First Time Deployment ==="
echo "Command: ./deploy.sh all"
echo ""
echo "This will:"
echo "  1. Ask for your domain (e.g., example.com)"
echo "  2. Configure Traefik with:"
echo "     - Cloudflare email and API token"
echo "     - Dashboard username/password"
echo "  3. Configure Portainer with:"
echo "     - Ports (defaults: 9000, 8000)"
echo "  4. Deploy both stacks"
echo "  5. Show access URLs and next steps"
echo ""
echo "---"
echo ""

# Scenario 2: Deploy individual stacks
echo "=== Scenario 2: Deploy Individual Stacks ==="
echo "Deploy only Traefik:"
echo "  ./deploy.sh traefik"
echo ""
echo "Deploy only Portainer:"
echo "  ./deploy.sh portainer"
echo ""
echo "---"
echo ""

# Scenario 3: Check status
echo "=== Scenario 3: Check Status ==="
echo "List all deployed stacks:"
echo "  ./deploy.sh list"
echo ""
echo "Show detailed status (stacks, services, networks):"
echo "  ./deploy.sh status"
echo ""
echo "---"
echo ""

# Scenario 4: View logs
echo "=== Scenario 4: View Service Logs ==="
echo "View Traefik logs:"
echo "  ./deploy.sh logs traefik_traefik"
echo ""
echo "View Portainer logs:"
echo "  ./deploy.sh logs portainer_portainer"
echo ""
echo "---"
echo ""

# Scenario 5: Remove and redeploy
echo "=== Scenario 5: Update/Redeploy a Stack ==="
echo "Remove Traefik:"
echo "  ./deploy.sh remove traefik"
echo ""
echo "Wait a few seconds, then redeploy:"
echo "  ./deploy.sh traefik"
echo ""
echo "The script will reuse your existing .env configuration"
echo ""
echo "---"
echo ""

# Scenario 6: Interactive mode
echo "=== Scenario 6: Interactive Menu ==="
echo "Run without arguments to get an interactive menu:"
echo "  ./deploy.sh"
echo ""
echo "This shows a menu with all options:"
echo "  1. Deploy Traefik"
echo "  2. Deploy Portainer"
echo "  3. Deploy All (Traefik + Portainer)"
echo "  4. List Stacks"
echo "  5. Show Status"
echo "  6. Remove Stack"
echo "  7. View Service Logs"
echo "  8. Exit"
echo ""
echo "---"
echo ""

# Common Commands Cheatsheet
echo "=== Common Commands Cheatsheet ==="
cat <<'EOF'

# Deployment
./deploy.sh all                    # Deploy everything
./deploy.sh traefik                # Deploy only Traefik
./deploy.sh portainer              # Deploy only Portainer

# Monitoring
./deploy.sh status                 # Show detailed status
./deploy.sh list                   # List deployed stacks
./deploy.sh logs traefik_traefik   # View Traefik logs
./deploy.sh logs portainer_portainer  # View Portainer logs

# Management
./deploy.sh remove traefik         # Remove Traefik
./deploy.sh remove portainer       # Remove Portainer

# Docker Commands (direct)
docker stack ls                    # List stacks
docker service ls                  # List all services
docker service ps traefik_traefik  # Show service tasks
docker service logs -f portainer_portainer  # Follow logs

# Network
docker network ls                  # List networks
docker network inspect web         # Inspect web network

# Help
./deploy.sh help                   # Show help message
./deploy.sh                        # Interactive menu

EOF

echo ""
echo "=== Tips ==="
echo ""
echo "1. Always deploy Traefik first (it's the reverse proxy)"
echo "2. Ensure DNS records point to your server before deployment"
echo "3. Wait a few minutes after deployment for SSL certificates"
echo "4. Set up Portainer admin credentials within 5 minutes"
echo "5. Keep your .env files secure and never commit them"
echo ""
echo "For more details, see README.md or QUICKSTART.md"

