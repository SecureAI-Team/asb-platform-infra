#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker-compose.ecs.yml"
ENV_FILE="${REPO_ROOT}/env/ecs.env"

log() {
  printf '[asb-deploy] %s\n' "$*"
}

ensure_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log "Required command '${cmd}' not found. Please install it and retry."
    exit 1
  fi
}

ensure_docker_compose() {
  if ! docker compose version >/dev/null 2>&1; then
    log "'docker compose' command unavailable. Install Docker Compose plugin before deploying."
    exit 1
  fi
}

main() {
  log "Starting deployment from ${REPO_ROOT}..."

  ensure_command docker
  ensure_docker_compose

  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log "Compose file ${COMPOSE_FILE} not found."
    exit 1
  fi

  if [[ ! -f "${ENV_FILE}" ]]; then
    log "Env file ${ENV_FILE} not found. Copy env/ecs.env.example -> env/ecs.env and customize it."
    exit 1
  fi

  # Load env vars so we can reuse optional ACR credentials.
  # shellcheck disable=SC1090
  source "${ENV_FILE}"

  if [[ -n "${ACR_REGISTRY:-}" && -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
    log "Logging into ACR registry ${ACR_REGISTRY}..."
    echo "${ACR_PASSWORD}" | docker login "${ACR_REGISTRY}" -u "${ACR_USERNAME}" --password-stdin
  else
    log "ACR credentials not set; skipping docker login (ensure this host is already authenticated)."
  fi

  log "Pulling latest container images..."
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" pull

  log "Applying docker compose stack..."
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d --remove-orphans

  log "ASB platform deployment complete. Use 'docker ps' to inspect services."
}

main "$@"

