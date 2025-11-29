#!/bin/bash

##############################################################################
# Docker Swarm Stack Deployment Manager
# 
# This script manages the deployment of Docker stacks to a Docker Swarm cluster.
# Currently supports: Traefik, Portainer
##############################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${SCRIPT_DIR}/stacks"

##############################################################################
# Utility Functions
##############################################################################

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Function to read user input with default value
read_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local is_password="${4:-false}"
    
    if [ "$is_password" = true ]; then
        read -sp "${prompt} [${default}]: " input
        echo ""  # New line after password input
    else
        read -p "${prompt} [${default}]: " input
    fi
    
    eval "$var_name=\"${input:-$default}\""
}

# Function to check if Docker Swarm is initialized
check_swarm() {
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        print_error "Docker Swarm is not initialized!"
        print_info "Please run: docker swarm init"
        exit 1
    fi
    print_success "Docker Swarm is active"
}

# Function to create Docker network if it doesn't exist
create_network() {
    local network_name="$1"
    
    if ! docker network ls | grep -q "$network_name"; then
        print_info "Creating Docker network: $network_name"
        docker network create --driver=overlay --attachable "$network_name"
        print_success "Network $network_name created"
    else
        print_success "Network $network_name already exists"
    fi
}

# Function to generate htpasswd hash for basic auth
generate_htpasswd() {
    local username="$1"
    local password="$2"
    
    # Check if htpasswd is available
    if command -v htpasswd &> /dev/null; then
        # Use htpasswd command
        htpasswd -nb "$username" "$password" | sed -e 's/\$/\$\$/g'
    else
        # Fallback to openssl if htpasswd is not available
        print_warning "htpasswd not found, using openssl (less secure)"
        echo "${username}:$(openssl passwd -apr1 "$password" | sed -e 's/\$/\$\$/g')"
    fi
}

##############################################################################
# Traefik Configuration
##############################################################################

configure_traefik() {
    print_header "Configuring Traefik"
    
    local stack_dir="${STACKS_DIR}/traefik"
    local env_file="${stack_dir}/.env"
    
    print_info "Traefik will be deployed at: traefik.${MAIN_DOMAIN}"
    echo ""
    
    # Ask for Cloudflare configuration
    read_input "Enter Cloudflare Email" "webmaster@avvaagency.com" CF_EMAIL
    read_input "Enter Cloudflare DNS API Token" "" CF_DNS_API_TOKEN false
    echo ""
    
    # Ask for Traefik dashboard credentials
    read_input "Enter Traefik Dashboard Username" "admin" TRAEFIK_USERNAME
    read_input "Enter Traefik Dashboard Password" "" TRAEFIK_PASSWORD true
    echo ""
    
    # Generate basic auth hash
    print_info "Generating authentication hash..."
    TRAEFIK_BASIC_AUTH=$(generate_htpasswd "$TRAEFIK_USERNAME" "$TRAEFIK_PASSWORD")
    
    # Create .env file
    print_info "Creating .env file for Traefik..."
    cat > "$env_file" <<EOF
# Traefik Configuration
DOMAIN=${MAIN_DOMAIN}
TRAEFIK_DOMAIN=traefik.${MAIN_DOMAIN}
TRAEFIK_DASHBOARD_PORT=8080

# Cloudflare DNS Challenge Configuration
CF_EMAIL=${CF_EMAIL}
CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}

# Basic Auth for Traefik Dashboard
# Generated for user: ${TRAEFIK_USERNAME}
TRAEFIK_BASIC_AUTH=${TRAEFIK_BASIC_AUTH}
EOF
    
    # Ensure acme.json exists with correct permissions
    local acme_file="${stack_dir}/acme.json"
    if [ ! -f "$acme_file" ]; then
        print_info "Creating acme.json file..."
        touch "$acme_file"
    fi
    chmod 600 "$acme_file"
    
    print_success "Traefik configuration completed"
    print_info "Dashboard URL: https://traefik.${MAIN_DOMAIN}"
    print_info "Username: ${TRAEFIK_USERNAME}"
}

deploy_traefik() {
    print_header "Deploying Traefik"
    
    local stack_dir="${STACKS_DIR}/traefik"
    local env_file="${stack_dir}/.env"
    
    if [ ! -f "$env_file" ]; then
        print_error "Traefik .env file not found. Please configure first."
        return 1
    fi
    
    # Create network
    create_network "web"
    
    # Deploy stack
    print_info "Deploying Traefik stack..."
    cd "$stack_dir"
    docker stack deploy -c docker-compose.yml traefik
    
    print_success "Traefik deployment initiated"
    print_info "Waiting for services to be ready..."
    sleep 10
    
    # Check service status
    docker service ls | grep traefik
    
    print_success "Traefik deployed successfully!"
}

##############################################################################
# Portainer Configuration
##############################################################################

configure_portainer() {
    print_header "Configuring Portainer"
    
    local stack_dir="${STACKS_DIR}/portainer"
    local env_file="${stack_dir}/.env"
    
    print_info "Portainer will be deployed at: portainer.${MAIN_DOMAIN}"
    echo ""
    
    # Ask for Portainer ports (with defaults)
    read_input "Enter Portainer Web UI Port" "9000" PORTAINER_PORT
    read_input "Enter Portainer Edge Agent Port" "8000" PORTAINER_EDGE_PORT
    echo ""
    
    # Create .env file
    print_info "Creating .env file for Portainer..."
    cat > "$env_file" <<EOF
# Portainer Configuration
DOMAIN=${MAIN_DOMAIN}
PORTAINER_DOMAIN=portainer.${MAIN_DOMAIN}
PORTAINER_PORT=${PORTAINER_PORT}
PORTAINER_EDGE_PORT=${PORTAINER_EDGE_PORT}

# Network Configuration
NETWORK_NAME=web
EOF
    
    # Ensure data directory exists
    local data_dir="${stack_dir}/data"
    if [ ! -d "$data_dir" ]; then
        print_info "Creating data directory..."
        mkdir -p "$data_dir"
    fi
    
    print_success "Portainer configuration completed"
    print_info "Web UI URL: https://portainer.${MAIN_DOMAIN}"
    print_info "You will set up admin credentials on first login"
}

deploy_portainer() {
    print_header "Deploying Portainer"
    
    local stack_dir="${STACKS_DIR}/portainer"
    local env_file="${stack_dir}/.env"
    
    if [ ! -f "$env_file" ]; then
        print_error "Portainer .env file not found. Please configure first."
        return 1
    fi
    
    # Ensure network exists
    create_network "web"
    
    # Deploy stack
    print_info "Deploying Portainer stack..."
    cd "$stack_dir"
    docker stack deploy -c docker-compose.yml portainer
    
    print_success "Portainer deployment initiated"
    print_info "Waiting for services to be ready..."
    sleep 10
    
    # Check service status
    docker service ls | grep portainer
    
    print_success "Portainer deployed successfully!"
    print_warning "Remember to set up your admin credentials within 5 minutes of first access"
}

##############################################################################
# Stack Management Functions
##############################################################################

list_stacks() {
    print_header "Deployed Stacks"
    docker stack ls
}

remove_stack() {
    local stack_name="$1"
    
    if [ -z "$stack_name" ]; then
        print_error "Stack name required"
        echo "Usage: $0 remove <stack_name>"
        return 1
    fi
    
    print_warning "Removing stack: $stack_name"
    read -p "Are you sure? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        docker stack rm "$stack_name"
        print_success "Stack $stack_name removed"
    else
        print_info "Removal cancelled"
    fi
}

remove_all_infrastructure() {
    print_header "Remove All Infrastructure"
    
    print_warning "This will remove BOTH Traefik and Portainer stacks"
    print_warning "All other stacks should be removed first!"
    echo ""
    read -p "Are you absolutely sure? Type 'yes' to confirm: " confirm
    
    if [ "$confirm" = "yes" ]; then
        print_info "Removing Portainer..."
        docker stack rm portainer 2>/dev/null || print_warning "Portainer stack not found"
        
        print_info "Removing Traefik..."
        docker stack rm traefik 2>/dev/null || print_warning "Traefik stack not found"
        
        print_info "Waiting for cleanup..."
        sleep 5
        
        print_success "Infrastructure stacks removed"
        print_info "You can redeploy with: ./deploy.sh all"
    else
        print_info "Removal cancelled"
    fi
}

show_logs() {
    local service_name="$1"
    
    if [ -z "$service_name" ]; then
        print_error "Service name required"
        echo "Usage: $0 logs <service_name>"
        return 1
    fi
    
    docker service logs -f "$service_name"
}

show_status() {
    print_header "Stack Status"
    
    echo ""
    print_info "Stacks:"
    docker stack ls
    
    echo ""
    print_info "Services:"
    docker service ls
    
    echo ""
    print_info "Networks:"
    docker network ls | grep -E "overlay|web"
}

##############################################################################
# Main Menu
##############################################################################

show_menu() {
    echo ""
    print_header "Docker Swarm Stack Deployment Manager"
    echo "Infrastructure:"
    echo "  1. Deploy Traefik"
    echo "  2. Deploy Portainer"
    echo "  3. Deploy All Infrastructure (Traefik + Portainer)"
    echo ""
    echo "Management:"
    echo "  4. List Stacks"
    echo "  5. Show Status"
    echo "  6. Remove Stack"
    echo "  7. Remove All Infrastructure"
    echo "  8. View Service Logs"
    echo "  9. Exit"
    echo ""
}

deploy_all() {
    print_header "Deploying All Stacks"
    
    # Ask for main domain once
    read_input "Enter your main domain" "vagifgozalov.com" MAIN_DOMAIN
    export MAIN_DOMAIN
    
    # Configure and deploy Traefik first (required for routing)
    configure_traefik
    deploy_traefik
    
    echo ""
    print_info "Waiting 10 seconds for Traefik to stabilize..."
    sleep 10
    
    # Configure and deploy Portainer
    configure_portainer
    deploy_portainer
    
    echo ""
    print_header "Deployment Summary"
    print_success "All stacks deployed successfully!"
    echo ""
    print_info "Access URLs:"
    echo "  • Traefik Dashboard: https://traefik.${MAIN_DOMAIN}"
    echo "  • Portainer: https://portainer.${MAIN_DOMAIN}"
    echo ""
    print_info "Next Steps:"
    echo "  1. Ensure your DNS records point to this server:"
    echo "     - traefik.${MAIN_DOMAIN} -> $(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
    echo "     - portainer.${MAIN_DOMAIN} -> $(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
    echo "  2. Set up Portainer admin credentials (within 5 minutes)"
    echo "  3. Check service status with: $0 status"
}

##############################################################################
# Main Script
##############################################################################

main() {
    # Check if running with sudo/root for Docker commands
    if ! docker ps &>/dev/null; then
        print_error "Cannot connect to Docker daemon"
        print_info "Make sure Docker is running and you have permissions"
        print_info "Add your user to docker group: sudo usermod -aG docker \$USER"
        exit 1
    fi
    
    # Check Docker Swarm
    check_swarm
    
    # Handle command line arguments
    if [ $# -gt 0 ]; then
        case "$1" in
            traefik)
                read_input "Enter your main domain" "vagifgozalov.com" MAIN_DOMAIN
                export MAIN_DOMAIN
                configure_traefik
                deploy_traefik
                ;;
            portainer)
                read_input "Enter your main domain" "vagifgozalov.com" MAIN_DOMAIN
                export MAIN_DOMAIN
                configure_portainer
                deploy_portainer
                ;;
            all)
                deploy_all
                ;;
            list|ls)
                list_stacks
                ;;
            status)
                show_status
                ;;
            remove|rm)
                remove_stack "$2"
                ;;
            remove-all)
                remove_all_infrastructure
                ;;
            logs)
                show_logs "$2"
                ;;
            help|--help|-h)
                echo "Usage: $0 [command] [arguments]"
                echo ""
                echo "Commands:"
                echo "  traefik          Deploy Traefik"
                echo "  portainer        Deploy Portainer"
                echo "  all              Deploy all stacks"
                echo "  list, ls         List deployed stacks"
                echo "  status           Show status of all services"
                echo "  remove, rm       Remove a stack"
                echo "  remove-all       Remove all infrastructure (Traefik + Portainer)"
                echo "  logs             View service logs"
                echo "  help             Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 all                    # Deploy everything"
                echo "  $0 traefik                # Deploy only Traefik"
                echo "  $0 remove traefik         # Remove Traefik stack"
                echo "  $0 remove-all             # Remove all infrastructure"
                echo "  $0 logs traefik_traefik   # View Traefik logs"
                ;;
            *)
                print_error "Unknown command: $1"
                echo "Use '$0 help' for usage information"
                exit 1
                ;;
        esac
    else
        # Interactive mode
        while true; do
            show_menu
            read -p "Select an option (1-9): " choice
            
            case $choice in
                1)
                    read_input "Enter your main domain" "vagifgozalov.com" MAIN_DOMAIN
                    export MAIN_DOMAIN
                    configure_traefik
                    deploy_traefik
                    ;;
                2)
                    read_input "Enter your main domain" "vagifgozalov.com" MAIN_DOMAIN
                    export MAIN_DOMAIN
                    configure_portainer
                    deploy_portainer
                    ;;
                3)
                    deploy_all
                    ;;
                4)
                    list_stacks
                    ;;
                5)
                    show_status
                    ;;
                6)
                    read -p "Enter stack name to remove: " stack_name
                    remove_stack "$stack_name"
                    ;;
                7)
                    remove_all_infrastructure
                    ;;
                8)
                    read -p "Enter service name: " service_name
                    show_logs "$service_name"
                    ;;
                9)
                    print_info "Exiting..."
                    exit 0
                    ;;
                *)
                    print_error "Invalid option. Please select 1-9."
                    ;;
            esac
            
            echo ""
            read -p "Press Enter to continue..."
        done
    fi
}

# Run main function
main "$@"

