#!/bin/bash

##############################################################################
# Traefik/Cloudflare Connection Troubleshooting Script
##############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

print_header "Cloudflare 523 Error Troubleshooting"

# Check 1: Docker Swarm Services
print_header "1. Checking Docker Swarm Services"
echo "Services status:"
docker service ls
echo ""

echo "Traefik service details:"
docker service ps traefik_traefik --no-trunc
echo ""

# Check if Traefik is actually running
TRAEFIK_RUNNING=$(docker service ps traefik_traefik --filter "desired-state=running" -q 2>/dev/null | wc -l)
if [ "$TRAEFIK_RUNNING" -gt 0 ]; then
    print_success "Traefik service is running"
else
    print_error "Traefik service is NOT running"
    echo ""
    print_info "Try redeploying: ./deploy.sh remove traefik && ./deploy.sh traefik"
fi

# Check 2: Port Binding
print_header "2. Checking Port Bindings"
echo "Ports 80 and 443 status:"
sudo netstat -tulpn | grep -E ':80|:443' || echo "No processes found on ports 80/443"
echo ""

# Check 3: Firewall Status
print_header "3. Checking Firewall"
if command -v ufw &> /dev/null; then
    echo "UFW Status:"
    sudo ufw status
    echo ""
    
    UFW_80=$(sudo ufw status | grep -E "80.*ALLOW" | wc -l)
    UFW_443=$(sudo ufw status | grep -E "443.*ALLOW" | wc -l)
    
    if [ "$UFW_80" -eq 0 ] || [ "$UFW_443" -eq 0 ]; then
        print_warning "Ports 80/443 may not be allowed in UFW"
        echo ""
        print_info "To fix, run:"
        echo "  sudo ufw allow 80/tcp"
        echo "  sudo ufw allow 443/tcp"
    else
        print_success "Ports 80/443 are allowed in UFW"
    fi
else
    print_info "UFW not found, checking iptables..."
    sudo iptables -L -n | grep -E "80|443" || echo "No specific rules found"
fi
echo ""

# Check 4: Server IP
print_header "4. Checking Server IP"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "Unable to detect")
echo "Your server's public IP: $SERVER_IP"
echo ""
print_info "Make sure your DNS A record points to this IP"
echo ""

# Check 5: DNS Resolution
print_header "5. Checking DNS"
if command -v dig &> /dev/null; then
    echo "DNS for traefik.vagifgozalov.com:"
    dig +short traefik.vagifgozalov.com
    echo ""
    
    echo "DNS for portainer.vagifgozalov.com:"
    dig +short portainer.vagifgozalov.com
    echo ""
else
    print_warning "dig not installed. Install with: sudo apt install dnsutils"
fi

# Check 6: Traefik Logs
print_header "6. Recent Traefik Logs"
echo "Last 30 lines of Traefik logs:"
docker service logs traefik_traefik --tail 30 2>/dev/null || print_error "Could not get logs"
echo ""

# Check 7: Network
print_header "7. Checking Docker Networks"
echo "Docker networks:"
docker network ls | grep web
echo ""

if docker network inspect web &>/dev/null; then
    print_success "Web network exists"
else
    print_error "Web network does NOT exist"
    print_info "Create it with: docker network create --driver=overlay --attachable web"
fi
echo ""

# Check 8: Traefik Configuration
print_header "8. Checking Traefik Configuration Files"
TRAEFIK_DIR="/Users/gozalov/Code/run/iac/neo/stacks/traefik"

if [ -f "$TRAEFIK_DIR/.env" ]; then
    print_success ".env file exists"
    echo ""
    echo "Environment variables (sanitized):"
    grep -v "TOKEN\|PASSWORD\|AUTH" "$TRAEFIK_DIR/.env" || cat "$TRAEFIK_DIR/.env"
else
    print_error ".env file NOT found at $TRAEFIK_DIR/.env"
fi
echo ""

if [ -f "$TRAEFIK_DIR/acme.json" ]; then
    print_success "acme.json exists"
    ACME_PERMS=$(stat -f "%OLp" "$TRAEFIK_DIR/acme.json" 2>/dev/null || stat -c "%a" "$TRAEFIK_DIR/acme.json" 2>/dev/null)
    if [ "$ACME_PERMS" = "600" ]; then
        print_success "acme.json has correct permissions (600)"
    else
        print_warning "acme.json has wrong permissions: $ACME_PERMS (should be 600)"
        print_info "Fix with: chmod 600 $TRAEFIK_DIR/acme.json"
    fi
else
    print_error "acme.json NOT found"
fi
echo ""

# Summary and Recommendations
print_header "Summary & Recommendations"

echo "Common causes of Cloudflare 523 error:"
echo ""
echo "1. ⚠️  Firewall blocking ports 80/443"
echo "   Fix: sudo ufw allow 80/tcp && sudo ufw allow 443/tcp"
echo ""
echo "2. ⚠️  Traefik not listening on ports"
echo "   Check: docker service ps traefik_traefik"
echo "   Fix: ./deploy.sh remove traefik && ./deploy.sh traefik"
echo ""
echo "3. ⚠️  DNS not pointing to correct IP"
echo "   Your IP: $SERVER_IP"
echo "   Check DNS in Cloudflare dashboard"
echo ""
echo "4. ⚠️  Cloudflare proxy is ON but server IP is not accessible"
echo "   Option A: Turn OFF Cloudflare proxy (grey cloud) temporarily to test"
echo "   Option B: Ensure your server IP is publicly accessible"
echo ""
echo "5. ⚠️  Cloud/VPS provider firewall blocking traffic"
echo "   Check your cloud provider's security groups/firewall rules"
echo ""

print_info "Quick Fixes to Try:"
echo ""
echo "# Fix 1: Ensure firewall allows traffic"
echo "sudo ufw allow 80/tcp"
echo "sudo ufw allow 443/tcp"
echo ""
echo "# Fix 2: Test if Traefik is responding locally"
echo "curl -I http://localhost:80"
echo ""
echo "# Fix 3: Restart Traefik"
echo "./deploy.sh remove traefik"
echo "sleep 5"
echo "./deploy.sh traefik"
echo ""
echo "# Fix 4: Check if port 80/443 are accessible from outside"
echo "# (Run from another machine or use online tools)"
echo "telnet $SERVER_IP 80"
echo "telnet $SERVER_IP 443"
echo ""

