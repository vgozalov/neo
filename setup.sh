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

SECONDARY_STACKS=("n8n" "audiobookshelf" "odoo_avva" "tradetally")
declare -A STACK_SERVICE_NAMES=(
  [traefik]="traefik_traefik"
  [portainer]="portainer_portainer"
  [n8n]="n8n_n8n"
  [audiobookshelf]="audiobookshelf_audiobookshelf"
  [odoo_avva]="odoo_avva_odoo"
  [tradetally]="tradetally_tradetally"
)

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

configure_n8n() {
  ensure_domain_selected
  log_info "Configuring n8n..."

  local n8n_domain n8n_port n8n_timezone db_name db_user db_pass basic_active basic_user basic_pass encryption_key env_file="${STACKS_DIR}/n8n/.env"

  prompt_with_default "n8n domain" "n8n.${MAIN_DOMAIN}" n8n_domain
  prompt_with_default "n8n public port" "5678" n8n_port
  prompt_with_default "n8n timezone" "America/Chicago" n8n_timezone
  prompt_with_default "Postgres database name" "n8n" db_name
  prompt_with_default "Postgres user" "n8n" db_user
  prompt_secret "Postgres password" db_pass
  if [[ -z "${db_pass}" ]]; then
    log_error "Database password cannot be empty."
    exit 1
  fi
  prompt_with_default "Enable Basic Auth (true/false)" "true" basic_active
  prompt_with_default "Basic auth username" "admin" basic_user
  prompt_secret "Basic auth password" basic_pass
  if [[ -z "${basic_pass}" ]]; then
    log_error "Basic auth password cannot be empty."
    exit 1
  fi
  prompt_with_default "Encryption key (leave blank to auto-generate)" "" encryption_key
  if [[ -z "${encryption_key}" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      encryption_key="$(openssl rand -hex 24)"
      log_info "Generated encryption key automatically."
    else
      log_error "OpenSSL not available. Please provide an encryption key."
      exit 1
    fi
  fi

  cat > "${env_file}" <<EOF
# Auto-generated on $(date -u)
DOMAIN=$(printf '%q' "${MAIN_DOMAIN}")
N8N_DOMAIN=$(printf '%q' "${n8n_domain}")
N8N_PORT=$(printf '%q' "${n8n_port}")
N8N_TIMEZONE=$(printf '%q' "${n8n_timezone}")
N8N_DB_NAME=$(printf '%q' "${db_name}")
N8N_DB_USER=$(printf '%q' "${db_user}")
N8N_DB_PASSWORD=$(printf '%q' "${db_pass}")
N8N_BASIC_AUTH_ACTIVE=$(printf '%q' "${basic_active}")
N8N_BASIC_AUTH_USER=$(printf '%q' "${basic_user}")
N8N_BASIC_AUTH_PASSWORD=$(printf '%q' "${basic_pass}")
N8N_ENCRYPTION_KEY=$(printf '%q' "${encryption_key}")
EOF

  mkdir -p "${STACKS_DIR}/n8n/.n8n" "${STACKS_DIR}/n8n/postgres/data"
  if ! chown -R 1000:1000 "${STACKS_DIR}/n8n/.n8n" >/dev/null 2>&1; then
    log_warn "Could not change ownership of ${STACKS_DIR}/n8n/.n8n to 1000:1000. Ensure permissions allow container writes."
  fi
  if ! chown -R 999:999 "${STACKS_DIR}/n8n/postgres/data" >/dev/null 2>&1; then
    log_warn "Could not change ownership of ${STACKS_DIR}/n8n/postgres/data to 999:999."
  fi
  log_success "n8n configuration written to ${env_file}"
}

configure_audiobookshelf() {
  ensure_domain_selected
  log_info "Configuring Audiobookshelf..."

  local abs_domain abs_port abs_uid abs_gid env_file="${STACKS_DIR}/audiobookshelf/.env"

  prompt_with_default "Audiobookshelf domain" "audiobookshelf.${MAIN_DOMAIN}" abs_domain
  prompt_with_default "Audiobookshelf public port" "13378" abs_port
  prompt_with_default "Container UID" "99" abs_uid
  prompt_with_default "Container GID" "100" abs_gid

  cat > "${env_file}" <<EOF
# Auto-generated on $(date -u)
DOMAIN=$(printf '%q' "${MAIN_DOMAIN}")
AUDIOBOOKSHELF_DOMAIN=$(printf '%q' "${abs_domain}")
AUDIOBOOKSHELF_PORT=$(printf '%q' "${abs_port}")
AUDIOBOOKSHELF_UID=$(printf '%q' "${abs_uid}")
AUDIOBOOKSHELF_GID=$(printf '%q' "${abs_gid}")
EOF

  mkdir -p "${STACKS_DIR}/audiobookshelf/audiobooks" \
           "${STACKS_DIR}/audiobookshelf/config" \
           "${STACKS_DIR}/audiobookshelf/metadata"
  log_success "Audiobookshelf configuration written to ${env_file}"
}

configure_odoo() {
  ensure_domain_selected
  log_info "Configuring Odoo..."

  local odoo_domain odoo_port db_name db_user db_pass admin_pass env_file="${STACKS_DIR}/odoo_avva/.env"

  prompt_with_default "Odoo domain" "odoo.${MAIN_DOMAIN}" odoo_domain
  prompt_with_default "Odoo public port" "8069" odoo_port
  prompt_with_default "Postgres database name" "postgres" db_name
  prompt_with_default "Postgres user" "odoo" db_user
  prompt_secret "Postgres password" db_pass
  if [[ -z "${db_pass}" ]]; then
    log_error "Database password cannot be empty."
    exit 1
  fi
  prompt_secret "Odoo admin (master) password" admin_pass
  if [[ -z "${admin_pass}" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      admin_pass="$(openssl rand -hex 16)"
      log_info "Generated random Odoo admin password."
    else
      log_error "Admin password cannot be empty."
      exit 1
    fi
  fi

  cat > "${env_file}" <<EOF
# Auto-generated on $(date -u)
DOMAIN=$(printf '%q' "${MAIN_DOMAIN}")
ODOO_DOMAIN=$(printf '%q' "${odoo_domain}")
ODOO_PORT=$(printf '%q' "${odoo_port}")
ODOO_DB_NAME=$(printf '%q' "${db_name}")
ODOO_DB_USER=$(printf '%q' "${db_user}")
ODOO_DB_PASSWORD=$(printf '%q' "${db_pass}")
ODOO_ADMIN_PASSWORD=$(printf '%q' "${admin_pass}")
EOF

  mkdir -p "${STACKS_DIR}/odoo_avva/postgres/data" \
           "${STACKS_DIR}/odoo_avva/config" \
           "${STACKS_DIR}/odoo_avva/addons"

  cat > "${STACKS_DIR}/odoo_avva/config/odoo.conf" <<EOF
[options]
admin_passwd = ${admin_pass}
db_host = odoo-postgres
db_port = 5432
db_user = ${db_user}
db_password = ${db_pass}
logfile = /var/log/odoo/odoo.log
EOF

  log_info "Wrote Odoo config to ${STACKS_DIR}/odoo_avva/config/odoo.conf"
  log_success "Odoo configuration written to ${env_file}"
}

configure_tradetally() {
  ensure_domain_selected
  log_info "Configuring TradeTally..."

  local tt_domain tt_port tt_image app_port node_env db_name db_user db_pass jwt_secret jwt_expires access_expire refresh_expire max_devices enable_device api_url frontend_url cors_origins email_host email_port email_user email_pass email_from registration_mode enable_swagger run_migrations billing_enabled stripe_secret stripe_pub stripe_webhook debug env_file="${STACKS_DIR}/tradetally/.env"

  prompt_with_default "TradeTally domain" "tt.${MAIN_DOMAIN}" tt_domain
  prompt_with_default "TradeTally public port" "8001" tt_port
  prompt_with_default "TradeTally image" "potentialmidas/tradetally:latest" tt_image
  prompt_with_default "TradeTally internal app port" "3000" app_port
  prompt_with_default "Node environment" "production" node_env
  prompt_with_default "Postgres database name" "tradetally" db_name
  prompt_with_default "Postgres user" "trader" db_user
  prompt_secret "Postgres password" db_pass
  if [[ -z "${db_pass}" ]]; then
    log_error "Database password cannot be empty."
    exit 1
  fi
  prompt_secret "JWT secret key" jwt_secret
  if [[ -z "${jwt_secret}" ]]; then
    log_error "JWT secret key cannot be empty."
    exit 1
  fi
  prompt_with_default "JWT expires in" "7d" jwt_expires
  prompt_with_default "Access token lifetime" "15m" access_expire
  prompt_with_default "Refresh token lifetime" "30d" refresh_expire
  prompt_with_default "Max devices per user" "10" max_devices
  prompt_with_default "Enable device tracking (true/false)" "true" enable_device
  prompt_with_default "API URL" "https://${tt_domain}/api" api_url
  prompt_with_default "Frontend URL" "https://${tt_domain}" frontend_url
  prompt_with_default "CORS origins (comma separated)" "" cors_origins
  prompt_with_default "Email host" "smtp.gmail.com" email_host
  prompt_with_default "Email port" "587" email_port
  prompt_with_default "Email user" "" email_user
  prompt_secret "Email password (optional)" email_pass
  prompt_with_default "Email from" "noreply@tradetally.io" email_from
  prompt_with_default "Registration mode" "open" registration_mode
  prompt_with_default "Enable Swagger (true/false)" "true" enable_swagger
  prompt_with_default "Run migrations on start (true/false)" "true" run_migrations
  prompt_with_default "Billing enabled (true/false)" "false" billing_enabled
  prompt_with_default "Stripe secret key" "" stripe_secret
  prompt_with_default "Stripe publishable key" "" stripe_pub
  prompt_with_default "Stripe webhook secret" "" stripe_webhook
  prompt_with_default "Enable debug mode (true/false)" "false" debug

  cat > "${env_file}" <<EOF
# Auto-generated on $(date -u)
DOMAIN=$(printf '%q' "${MAIN_DOMAIN}")
TRADETALLY_DOMAIN=$(printf '%q' "${tt_domain}")
TRADETALLY_PORT=$(printf '%q' "${tt_port}")
TRADETALLY_IMAGE=$(printf '%q' "${tt_image}")
TRADETALLY_APP_PORT=$(printf '%q' "${app_port}")
TRADETALLY_NODE_ENV=$(printf '%q' "${node_env}")
TRADETALLY_DB_NAME=$(printf '%q' "${db_name}")
TRADETALLY_DB_USER=$(printf '%q' "${db_user}")
TRADETALLY_DB_PASSWORD=$(printf '%q' "${db_pass}")
TRADETALLY_JWT_SECRET=$(printf '%q' "${jwt_secret}")
TRADETALLY_JWT_EXPIRES_IN=$(printf '%q' "${jwt_expires}")
TRADETALLY_ACCESS_TOKEN_EXPIRE=$(printf '%q' "${access_expire}")
TRADETALLY_REFRESH_TOKEN_EXPIRE=$(printf '%q' "${refresh_expire}")
TRADETALLY_MAX_DEVICES=$(printf '%q' "${max_devices}")
TRADETALLY_ENABLE_DEVICE_TRACKING=$(printf '%q' "${enable_device}")
TRADETALLY_VITE_API_URL=$(printf '%q' "${api_url}")
TRADETALLY_FRONTEND_URL=$(printf '%q' "${frontend_url}")
TRADETALLY_CORS_ORIGINS=$(printf '%q' "${cors_origins}")
TRADETALLY_EMAIL_HOST=$(printf '%q' "${email_host}")
TRADETALLY_EMAIL_PORT=$(printf '%q' "${email_port}")
TRADETALLY_EMAIL_USER=$(printf '%q' "${email_user}")
TRADETALLY_EMAIL_PASS=$(printf '%q' "${email_pass}")
TRADETALLY_EMAIL_FROM=$(printf '%q' "${email_from}")
TRADETALLY_REGISTRATION_MODE=$(printf '%q' "${registration_mode}")
TRADETALLY_ENABLE_SWAGGER=$(printf '%q' "${enable_swagger}")
TRADETALLY_RUN_MIGRATIONS=$(printf '%q' "${run_migrations}")
TRADETALLY_BILLING_ENABLED=$(printf '%q' "${billing_enabled}")
TRADETALLY_STRIPE_SECRET_KEY=$(printf '%q' "${stripe_secret}")
TRADETALLY_STRIPE_PUBLISHABLE_KEY=$(printf '%q' "${stripe_pub}")
TRADETALLY_STRIPE_WEBHOOK_SECRET=$(printf '%q' "${stripe_webhook}")
TRADETALLY_DEBUG=$(printf '%q' "${debug}")
EOF

  mkdir -p "${STACKS_DIR}/tradetally/postgres/data" \
           "${STACKS_DIR}/tradetally/config" \
           "${STACKS_DIR}/tradetally/backend/logs" \
           "${STACKS_DIR}/tradetally/backend/data"
  log_success "TradeTally configuration written to ${env_file}"
}

deploy_custom_stack() {
  local stack="$1"
  local compose="${2:-docker-compose.yml}"
  local stack_path="${STACKS_DIR}/${stack}"

  if [[ ! -d "${stack_path}" ]]; then
    log_error "Stack directory not found: ${stack_path}"
    return 1
  fi

  if [[ ! -f "${stack_path}/.env" ]]; then
    log_error "Missing .env for stack ${stack}. Run configuration first."
    return 1
  fi

  ensure_networks
  pushd "${stack_path}" >/dev/null
  log_info "Deploying stack '${stack}'..."
  deploy_stack_with_env "${stack_path}" "${stack}" "${compose}"
  popd >/dev/null

  local service="${STACK_SERVICE_NAMES[$stack]:-}"
  if [[ -n "${service}" ]]; then
    wait_for_service "${service}" || true
  fi
}

deploy_secondary_stack() {
  local stack="$1"
  case "${stack}" in
    n8n)
      configure_n8n
      deploy_custom_stack "n8n"
      ;;
    audiobookshelf)
      configure_audiobookshelf
      deploy_custom_stack "audiobookshelf"
      ;;
    odoo_avva)
      configure_odoo
      deploy_custom_stack "odoo_avva"
      ;;
    tradetally)
      configure_tradetally
      deploy_custom_stack "tradetally"
      ;;
    *)
      log_warn "No automated workflow for stack '${stack}'."
      ;;
  esac
}

deploy_all_secondary_stacks() {
  for stack in "${SECONDARY_STACKS[@]}"; do
    echo ""
    log_info "Deploying secondary stack: ${stack}"
    deploy_secondary_stack "${stack}"
  done
  log_success "Secondary stacks deployment attempted."
}

generic_deploy_stack() {
  local stack="$1"
  local stack_path="${STACKS_DIR}/${stack}"
  if [[ ! -d "${stack_path}" ]]; then
    log_error "Stack '${stack}' directory not found."
    return 1
  fi
  if [[ ! -f "${stack_path}/.env" ]]; then
    log_error "Stack '${stack}' lacks automation and .env is missing. Please create ${stack_path}/.env first."
    return 1
  fi
  deploy_custom_stack "${stack}"
}

deploy_stack_by_name() {
  local stack="$1"
  case "${stack}" in
    traefik)
      ensure_domain_selected
      configure_traefik
      deploy_traefik
      ;;
    portainer)
      ensure_domain_selected
      configure_portainer
      deploy_portainer
      ;;
    n8n|audiobookshelf|odoo_avva|tradetally)
      deploy_secondary_stack "${stack}"
      ;;
    *)
      generic_deploy_stack "${stack}"
      ;;
  esac
}

deploy_single_stack_menu() {
  mapfile -t available_stacks < <(find "${STACKS_DIR}" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort)

  if [[ ${#available_stacks[@]} -eq 0 ]]; then
    log_warn "No stacks found in ${STACKS_DIR}."
    return
  fi

  echo ""
  log_info "Available stacks:"
  local idx=1
  for stack in "${available_stacks[@]}"; do
    echo "  ${idx}. ${stack}"
    ((idx++))
  done
  echo "  0. Cancel"

  local choice
  read -rp "Select stack to deploy: " choice

  if [[ "${choice}" == "0" ]]; then
    log_info "Cancelled."
    return
  fi

  if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#available_stacks[@]} )); then
    log_warn "Invalid selection."
    return
  fi

  local selected="${available_stacks[choice-1]}"
  deploy_stack_by_name "${selected}"
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
4. Deploy All Secondary Stacks
5. Deploy Single Stack
6. List Stacks
7. Show Status
8. Remove Stack
9. Remove All Infrastructure
10. View Service Logs
11. Ensure Networks
12. Reset Networks
13. Exit
MENU

    read -rp "Select an option (1-13): " choice
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
        deploy_all_secondary_stacks
        ;;
      5)
        deploy_single_stack_menu
        ;;
      6)
        list_stacks
        ;;
      7)
        show_status
        ;;
      8)
        read -rp "Enter stack name to remove: " stack_name
        remove_stack "${stack_name}"
        ;;
      9)
        infra_down
        ;;
      10)
        read -rp "Enter service name (e.g., traefik_traefik): " service_name
        show_logs "${service_name}"
        ;;
      11)
        ensure_networks
        ;;
      12)
        reset_networks
        ;;
      13)
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
    secondary)
      case "${action}" in
        up|all|"") deploy_all_secondary_stacks ;;
        single) deploy_single_stack_menu ;;
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

