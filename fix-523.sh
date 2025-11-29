#!/bin/bash

##############################################################################
# Quick Fix for Cloudflare 523 Error
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

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Quick Fix for Cloudflare 523 Error${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Open firewall ports
print_info "Step 1: Opening firewall ports 80 and 443..."
if command -v ufw &> /dev/null; then
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        print_success "Firewall ports opened"
    else
        print_warning "UFW is not active"
    fi
else
    print_warning "UFW not found, skipping firewall configuration"
fi
echo ""

# Step 2: Check if Traefik is running
print_info "Step 2: Checking Traefik status..."
if docker service ps traefik_traefik --filter "desired-state=running" -q 2>/dev/null | grep -q .; then
    print_success "Traefik is running"
    
    # Show Traefik logs
    print_info "Recent Traefik logs:"
    docker service logs traefik_traefik --tail 20
else
    print_error "Traefik is NOT running properly"
    
    # Try to restart Traefik
    print_info "Attempting to restart Traefik..."
    docker service update --force traefik_traefik
    print_success "Traefik restart initiated"
fi
echo ""

# Step 3: Test local connectivity
print_info "Step 3: Testing local connectivity..."
if curl -Is http://localhost:80 2>/dev/null | head -1 | grep -q "HTTP"; then
    print_success "Traefik is responding on port 80"
else
    print_error "Traefik is NOT responding on port 80"
    print_warning "This is likely the issue!"
fi

if curl -Isk https://localhost:443 2>/dev/null | head -1 | grep -q "HTTP"; then
    print_success "Traefik is responding on port 443"
else
    print_warning "Traefik is NOT responding on port 443 (may be normal if no SSL yet)"
fi
echo ""

# Step 4: Check Docker network
print_info "Step 4: Checking Docker network..."
if docker network inspect web &>/dev/null; then
    print_success "Docker 'web' network exists"
else
    print_error "Docker 'web' network is missing"
    print_info "Creating network..."
    docker network create --driver=overlay --attachable web
    print_success "Network created"
fi
echo ""

# Step 5: Show server IP
print_info "Step 5: Server IP Address"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to detect")
echo "Your server public IP: ${GREEN}$SERVER_IP${NC}"
echo ""

# Step 6: DNS Check
print_info "Step 6: DNS Configuration Check"
if command -v dig &> /dev/null; then
    DNS_IP=$(dig +short traefik.vagifgozalov.com | tail -1)
    echo "DNS resolves traefik.vagifgozalov.com to: ${GREEN}$DNS_IP${NC}"
    
    if [ "$DNS_IP" != "$SERVER_IP" ]; then
        print_warning "DNS IP ($DNS_IP) doesn't match server IP ($SERVER_IP)"
        print_info "This might be OK if using Cloudflare proxy (orange cloud)"
    fi
else
    print_warning "dig not installed. Install with: sudo apt install dnsutils"
fi
echo ""

# Recommendations
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Next Steps${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

print_info "1. Verify Cloudflare DNS Settings:"
echo "   - Go to cloudflare.com → DNS → Records"
echo "   - Ensure you have A records:"
echo "     Name: traefik → Points to: $SERVER_IP"
echo "     Name: portainer → Points to: $SERVER_IP"
echo ""

print_info "2. Check Cloudflare Proxy Status:"
echo "   - Temporarily turn OFF the proxy (grey cloud icon) for testing"
echo "   - If it works with proxy OFF, the issue is with SSL/TLS settings"
echo ""

print_info "3. Cloudflare SSL/TLS Settings:"
echo "   - Go to cloudflare.com → SSL/TLS → Overview"
echo "   - Set to: 'Full' or 'Full (strict)'"
echo "   - NOT 'Flexible'"
echo ""

print_info "4. Test external connectivity:"
echo "   - From another computer/network, try:"
echo "     telnet $SERVER_IP 80"
echo "     telnet $SERVER_IP 443"
echo ""

print_info "5. If still not working, check your cloud provider:"
echo "   - AWS: Check Security Groups"
echo "   - DigitalOcean: Check Firewall rules"
echo "   - Hetzner: Check Cloud Firewall"
echo "   - Ensure ports 80 and 443 are open to 0.0.0.0/0"
echo ""

print_info "6. View full diagnostics:"
echo "   ./troubleshoot.sh"
echo ""

print_success "Quick fix applied!"
print_warning "Wait 1-2 minutes, then try accessing your domain again"

