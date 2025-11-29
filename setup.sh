#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Infrastructure bootstrapper for Docker Swarm.
# Handles interactive configuration and deployment for Traefik + Portainer.
# -----------------------------------------------------------------------------

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/helpers/common.sh"

DEFAULT_DOMAIN="vagifgozalov.com"
DEFAULT_CF_EMAIL="webmaster@avvaagency.com"

# Cache domain within a run so we only ask once unless user overrides.
MAIN_DOMAIN=""

usage() {
  cat <<'EOF'
Usage: ./setup.sh <component> <action>

Components
  infra        Traefik + Portainer together
  traefik      Only the Traefik stack
  portainer    Only the Portainer stack

Actions
  up           Configure (prompts) and deploy the stack(s)
  down         Remove the stack(s)

Utility commands
  ./setup.sh status
  ./setup.sh list
  ./setup.sh remove <stack_name>
  ./setup.sh networks
  ./setup.sh menu
  ./setup.sh logs <service_name>

Examples
  ./setup.sh infra up
  ./setup.sh traefik up
  ./setup.sh portainer down
  ./setup.sh logs traefik_traefik
  ./setup.sh                 # interactive menu
EOF
}

#------------------------------------------------------------------------------
# Shared helpers
#------------------------------------------------------------------------------

ensure_domain_selected() {
  if [[ -z "${MAIN_DOMAIN}" ]]; then
    prompt_with_default "Enter your main domain" "${DEFAULT_DOMAIN}" MAIN_DOMAIN
  fi
}

deploy_stack_with_env() {
  local stack_dir="$1"
  local stack_name="$2"
  local compose_file="${3:-docker-compose.yml}"
  local env_file="${stack_dir}/.env"

  if [[ ! -f "${env_file}" ]]; then
    log_error "Environment file not found for stack '${stack_name}' (${env_file}). Run configuration first."
    exit 1
  fi

  (
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
    docker stack deploy -c "${compose_file}" "${stack_name}"
  )
}

configure_traefik() {
  ensure_domain_selected
  log_info "Configuring Traefik for domain: ${MAIN_DOMAIN}"

  local cf_email cf_token dashboard_user dashboard_pass env_file="${STACKS_DIR}/traefik/.env"

  prompt_with_default "Cloudflare email" "${DEFAULT_CF_EMAIL}" cf_email
  prompt_with_default "Cloudflare DNS API token" "" cf_token
  prompt_with_default "Traefik dashboard username" "admin" dashboard_user
  prompt_secret "Traefik dashboard password" dashboard_pass

  if [[ -z "${cf_token}" ]]; then
    log_warn "Cloudflare token was left blank; DNS challenge will fail."
  fi
  if [[ -z "${dashboard_pass}" ]]; then
    log_error "Password cannot be empty."
    exit 1
  fi

  local basic_auth
  basic_auth="$(generate_htpasswd "${dashboard_user}" "${dashboard_pass}")"

  cat > "${env_file}" <<EOF
# Auto-generated on $(date -u)
DOMAIN=$(printf '%q' "${MAIN_DOMAIN}")
TRAEFIK_DOMAIN=$(printf '%q' "traefik.${MAIN_DOMAIN}")
TRAEFIK_DASHBOARD_PORT=$(printf '%q' "8080")
CF_EMAIL=$(printf '%q' "${cf_email}")
CF_DNS_API_TOKEN=$(printf '%q' "${cf_token}")
TRAEFIK_BASIC_AUTH=$(printf '%q' "${basic_auth}")
EOF

  local acme="${STACKS_DIR}/traefik/acme.json"
  if [[ ! -f "${acme}" ]]; then
    touch "${acme}"
  fi
  chmod 600 "${acme}"

  log_success "Traefik configuration written to ${env_file}"
}

deploy_traefik() {
  ensure_networks
  pushd "${STACKS_DIR}/traefik" >/dev/null
  log_info "Deploying Traefik stack..."
  deploy_stack_with_env "${STACKS_DIR}/traefik" "traefik"
  popd >/dev/null
  wait_for_service "traefik_traefik" || true
}

remove_traefik() {
  log_info "Removing Traefik stack..."
  docker stack rm traefik >/dev/null 2>&1 || log_warn "Traefik stack not found."
}

configure_portainer() {
  ensure_domain_selected
  log_info "Configuring Portainer for domain: ${MAIN_DOMAIN}"

  local http_port edge_port env_file="${STACKS_DIR}/portainer/.env"

  prompt_with_default "Portainer web UI port" "9000" http_port
  prompt_with_default "Portainer Edge agent port" "8000" edge_port

  cat > "${env_file}" <<EOF
# Auto-generated on $(date -u)
DOMAIN=$(printf '%q' "${MAIN_DOMAIN}")
PORTAINER_DOMAIN=$(printf '%q' "portainer.${MAIN_DOMAIN}")
PORTAINER_PORT=$(printf '%q' "${http_port}")
PORTAINER_EDGE_PORT=$(printf '%q' "${edge_port}")
NETWORK_NAME=$(printf '%q' "${WEB_NETWORK_NAME}")
EOF

  mkdir -p "${STACKS_DIR}/portainer/data"
  log_success "Portainer configuration written to ${env_file}"
}

deploy_portainer() {
  ensure_networks
  pushd "${STACKS_DIR}/portainer" >/dev/null
  log_info "Deploying Portainer stack..."
  deploy_stack_with_env "${STACKS_DIR}/portainer" "portainer"
  popd >/dev/null
  wait_for_service "portainer_portainer" || true
}

remove_portainer() {
  log_info "Removing Portainer stack..."
  docker stack rm portainer >/dev/null 2>&1 || log_warn "Portainer stack not found."
}

infra_up() {
  configure_traefik
  deploy_traefik
  log_info "Waiting 10 seconds before deploying Portainer..."
  sleep 10
  configure_portainer
  deploy_portainer
  log_success "Infrastructure deployed."
}

infra_down() {
  remove_portainer
  remove_traefik
  log_success "Infrastructure removed."
}

show_status() {
  log_info "Stacks:"
  docker stack ls || true
  echo ""
  log_info "Services:"
  docker service ls || true
  echo ""
  log_info "Relevant networks:"
  for net in "${WEB_NETWORK_NAME}" "${BACKEND_NETWORK_NAME}" "${MONITORING_NETWORK_NAME}"; do
    if docker network inspect "${net}" >/dev/null 2>&1; then
      log_success "Network '${net}' exists."
    else
      log_warn "Network '${net}' not found."
    fi
  done
}

show_logs() {
  local service="$1"
  if [[ -z "${service}" ]]; then
    log_error "Service name required. Example: ./setup.sh logs traefik_traefik"
    exit 1
  fi
  docker service logs -f "${service}"
}

list_stacks() {
  log_info "Stacks:"
  docker stack ls
}

remove_stack() {
  local stack="$1"
  if [[ -z "${stack}" ]]; then
    log_error "Stack name required."
    return 1
  fi
  if docker stack rm "${stack}" >/dev/null 2>&1; then
    log_success "Stack '${stack}' removal initiated."
  else
    log_warn "Stack '${stack}' not found."
  fi
}

reset_networks() {
  log_warn "This will remove overlay networks '${WEB_NETWORK_NAME}', '${BACKEND_NETWORK_NAME}', '${MONITORING_NETWORK_NAME}'."
  read -rp "Type 'reset' to continue: " confirm
  if [[ "${confirm}" != "reset" ]]; then
    log_info "Network reset cancelled."
    return
  fi

  for net in "${WEB_NETWORK_NAME}" "${BACKEND_NETWORK_NAME}" "${MONITORING_NETWORK_NAME}"; do
    if docker network inspect "${net}" >/dev/null 2>&1; then
      if docker network rm "${net}" >/dev/null 2>&1; then
        log_success "Removed network '${net}'."
      else
        log_warn "Failed to remove network '${net}' (in use)."
      fi
    else
      log_info "Network '${net}' does not exist; skipping."
    fi
  done

  ensure_networks
}

interactive_menu() {
  while true; do
    cat <<'MENU'

========================================
Docker Swarm Stack Deployment Manager
========================================
1. Deploy Traefik
2. Deploy Portainer
3. Deploy All Infrastructure
4. List Stacks
5. Show Status
6. Remove Stack
7. Remove All Infrastructure
8. View Service Logs
9. Ensure Networks
10. Reset Networks
11. Exit
MENU

    read -rp "Select an option (1-11): " choice
    case "${choice}" in
      1)
        ensure_domain_selected
        configure_traefik
        deploy_traefik
        ;;
      2)
        ensure_domain_selected
        configure_portainer
        deploy_portainer
        ;;
      3)
        infra_up
        ;;
      4)
        list_stacks
        ;;
      5)
        show_status
        ;;
      6)
        read -rp "Enter stack name to remove: " stack_name
        remove_stack "${stack_name}"
        ;;
      7)
        infra_down
        ;;
      8)
        read -rp "Enter service name (e.g., traefik_traefik): " service_name
        show_logs "${service_name}"
        ;;
      9)
        ensure_networks
        ;;
      10)
        reset_networks
        ;;
      11)
        log_info "Exiting..."
        exit 0
        ;;
      *)
        log_warn "Invalid option."
        ;;
    esac

    read -rp "Press Enter to continue..." _
  done
}

#------------------------------------------------------------------------------
# Entry point
#------------------------------------------------------------------------------

main() {
  require_docker
  ensure_swarm
  ensure_networks

  if [[ $# -eq 0 ]]; then
    interactive_menu
    exit 0
  fi

  local component="${1:-}"
  local action="${2:-}"

  case "${component}" in
    infra)
      case "${action}" in
        up) infra_up ;;
        down) infra_down ;;
        *) usage ;;
      esac
      ;;
    traefik)
      case "${action}" in
        up) configure_traefik; deploy_traefik ;;
        down) remove_traefik ;;
        *) usage ;;
      esac
      ;;
    portainer)
      case "${action}" in
        up) configure_portainer; deploy_portainer ;;
        down) remove_portainer ;;
        *) usage ;;
      esac
      ;;
    up)
      infra_up
      ;;
    down)
      infra_down
      ;;
    list|ls)
      list_stacks
      ;;
    status)
      show_status
      ;;
    remove)
      remove_stack "${action}"
      ;;
    remove-all)
      infra_down
      ;;
    networks)
      if [[ "${action}" == "reset" ]]; then
        reset_networks
      else
        ensure_networks
      fi
      ;;
    logs)
      show_logs "${action}"
      ;;
    menu)
      interactive_menu
      ;;
    ""|help|-h|--help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

