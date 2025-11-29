#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Common helper functions for infrastructure scripts.
#------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
STACKS_DIR="${SCRIPT_DIR}/stacks"
NETWORK_NAME="web"

# Colors for readable output.
COLOR_RESET="\033[0m"
COLOR_INFO="\033[1;34m"
COLOR_SUCCESS="\033[1;32m"
COLOR_WARN="\033[1;33m"
COLOR_ERROR="\033[1;31m"

log_info()    { echo -e "${COLOR_INFO}ℹ ${1}${COLOR_RESET}"; }
log_success() { echo -e "${COLOR_SUCCESS}✓ ${1}${COLOR_RESET}"; }
log_warn()    { echo -e "${COLOR_WARN}⚠ ${1}${COLOR_RESET}"; }
log_error()   { echo -e "${COLOR_ERROR}✗ ${1}${COLOR_RESET}"; }

# Prompt helper with default value.
prompt_with_default() {
  local message="$1"
  local default_value="$2"
  local __resultvar="$3"

  read -rp "${message} [${default_value}]: " input
  if [[ -z "${input}" ]]; then
    printf -v "${__resultvar}" "%s" "${default_value}"
  else
    printf -v "${__resultvar}" "%s" "${input}"
  fi
}

# Secret prompt (input hidden).
prompt_secret() {
  local message="$1"
  local __resultvar="$2"

  read -rsp "${message}: " secret
  echo ""
  printf -v "${__resultvar}" "%s" "${secret}"
}

# Ensure docker command available.
require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed or not in PATH."
    exit 1
  fi
}

# Ensure docker swarm initialized.
ensure_swarm() {
  if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    log_error "Docker Swarm is not initialized."
    log_info "Run 'docker swarm init' on this host before continuing."
    exit 1
  fi
  log_success "Docker Swarm is active."
}

# Ensure overlay network exists for stacks.
ensure_network() {
  if docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    log_success "Network '${NETWORK_NAME}' already exists."
    return
  fi

  log_info "Creating overlay network '${NETWORK_NAME}'."
  docker network create \
    --driver overlay \
    --attachable \
    "${NETWORK_NAME}"
  log_success "Network '${NETWORK_NAME}' created."
}

# Generate htpasswd entry using htpasswd or openssl fallback.
generate_htpasswd() {
  local username="$1"
  local password="$2"

  if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -nb "${username}" "${password}" | sed -e 's/\$/\$\$/g'
  else
    log_warn "htpasswd command not found; using openssl fallback."
    local hash
    hash="$(openssl passwd -apr1 "${password}")"
    echo "${username}:${hash}" | sed -e 's/\$/\$\$/g'
  fi
}

# Wait for a swarm service to report at least one running replica.
wait_for_service() {
  local service_name="$1"
  local attempts=10

  log_info "Waiting for service '${service_name}' to report RUNNING..."
  for ((i=1; i<=attempts; i++)); do
    if docker service ps "${service_name}" --filter "desired-state=running" --format '{{.CurrentState}}' | grep -q "Running"; then
      log_success "Service '${service_name}' is running."
      return 0
    fi
    sleep 3
  done

  log_warn "Service '${service_name}' did not report RUNNING state within expected time."
  docker service ps "${service_name}"
  return 1
}


