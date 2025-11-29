#!/bin/bash

##############################################################################
# Diagnose and Fix Traefik/Portainer Not Starting (0/1 replicas)
##############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_header "Diagnosing Services Not Starting (0/1 replicas)"

# Check current service status
print_info "Current service status:"
docker service ls
echo ""

# Get detailed task information for Traefik
print_header "Traefik Service Tasks (Detailed)"
docker service ps traefik_traefik --no-trunc
echo ""

# Check for error messages
print_info "Checking for error messages..."
TRAEFIK_ERRORS=$(docker service ps traefik_traefik --no-trunc --format "{{.Error}}" | grep -v "^$" | head -1)

if [ -n "$TRAEFIK_ERRORS" ]; then
    print_error "Traefik has errors:"
    echo "$TRAEFIK_ERRORS"
else
    print_warning "No error messages found (might be stuck in starting state)"
fi
echo ""

# Get Traefik container logs if available
print_header "Traefik Container Logs"
TRAEFIK_TASK_ID=$(docker service ps traefik_traefik -q --filter "desired-state=running" | head -1)
if [ -n "$TRAEFIK_TASK_ID" ]; then
    CONTAINER_ID=$(docker ps -q --filter "label=com.docker.swarm.task.id=$TRAEFIK_TASK_ID")
    if [ -n "$CONTAINER_ID" ]; then
        print_info "Found container: $CONTAINER_ID"
        docker logs $CONTAINER_ID 2>&1 | tail -30
    else
        print_warning "Container not found or not running yet"
        docker service logs traefik_traefik --tail 30 2>&1 || echo "No logs available"
    fi
else
    print_warning "No running tasks found"
fi
echo ""

# Check Portainer status
print_header "Portainer Service Tasks (Detailed)"
docker service ps portainer_portainer --no-trunc
echo ""

# Common issues and fixes
print_header "Common Issues and Fixes"

echo "Issue 1: Volume mount problems"
print_info "Checking if /var/run/docker.sock is accessible..."
if [ -S /var/run/docker.sock ]; then
    print_success "/var/run/docker.sock exists"
else
    print_error "/var/run/docker.sock not found or not a socket"
fi
echo ""

echo "Issue 2: Port conflicts"
print_info "Checking if ports 80/443 are already in use..."
if command -v ss &> /dev/null; then
    PORT_80=$(ss -tulpn | grep ":80 " || true)
    PORT_443=$(ss -tulpn | grep ":443 " || true)
    
    if [ -n "$PORT_80" ]; then
        print_warning "Port 80 is in use:"
        echo "$PORT_80"
    else
        print_success "Port 80 is available"
    fi
    
    if [ -n "$PORT_443" ]; then
        print_warning "Port 443 is in use:"
        echo "$PORT_443"
    else
        print_success "Port 443 is available"
    fi
else
    print_warning "ss command not found, install with: apt install iproute2"
fi
echo ""

echo "Issue 3: Docker Swarm constraints"
print_info "Checking node status..."
docker node ls
echo ""

print_info "Checking if this node is a manager..."
NODE_ROLE=$(docker node inspect self --format '{{.Spec.Role}}')
if [ "$NODE_ROLE" = "manager" ]; then
    print_success "This node is a manager (required for Traefik/Portainer)"
else
    print_error "This node is NOT a manager!"
    print_info "Services require manager node. Promote with: docker node promote <node-id>"
fi
echo ""

echo "Issue 4: Network"
print_info "Checking 'web' network..."
if docker network inspect web &>/dev/null; then
    print_success "'web' network exists"
    docker network inspect web --format '{{.Driver}}' | grep overlay || print_warning "Network is not overlay type"
else
    print_error "'web' network does not exist"
fi
echo ""

# Automated Fix
print_header "Automated Fix Attempt"

read -p "Do you want to attempt an automated fix? (y/N): " confirm

if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    print_info "Step 1: Ensuring 'web' network exists..."
    if ! docker network inspect web &>/dev/null; then
        docker network create --driver=overlay --attachable web
        print_success "Created 'web' network"
    else
        print_success "'web' network already exists"
    fi
    
    print_info "Step 2: Removing failed services..."
    docker service rm traefik_traefik portainer_portainer 2>/dev/null || true
    sleep 5
    
    print_info "Step 3: Removing stacks..."
    docker stack rm traefik portainer 2>/dev/null || true
    sleep 10
    
    print_info "Step 4: Checking for remaining containers..."
    docker ps -a --filter "label=com.docker.stack.namespace=traefik" -q | xargs -r docker rm -f
    docker ps -a --filter "label=com.docker.stack.namespace=portainer" -q | xargs -r docker rm -f
    
    print_success "Cleanup complete!"
    echo ""
    print_info "Now redeploy with:"
    echo "  cd $(dirname "$0")"
    echo "  ./deploy.sh all"
    echo ""
    print_warning "Make sure ports 80 and 443 are not being used by other processes"
    
    # Check for port conflicts one more time
    if command -v ss &> /dev/null; then
        echo ""
        print_info "Checking ports again..."
        PORT_CHECK=$(ss -tulpn | grep -E ":80 |:443 " || true)
        if [ -n "$PORT_CHECK" ]; then
            print_warning "Ports still in use:"
            echo "$PORT_CHECK"
            echo ""
            print_info "You may need to stop these services first"
        else
            print_success "Ports 80 and 443 are now free!"
        fi
    fi
else
    print_info "Fix cancelled"
    echo ""
    print_info "Manual fix steps:"
    echo "  1. Remove stacks: docker stack rm traefik portainer"
    echo "  2. Wait 10 seconds: sleep 10"
    echo "  3. Redeploy: ./deploy.sh all"
fi

echo ""
print_header "Diagnostic Complete"

