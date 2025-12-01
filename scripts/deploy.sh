#!/usr/bin/env bash
set -euo pipefail

ASB_DIR="${ASB_DIR:-/opt/asb-platform}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.ecs.yml}"
ENV_FILE="${ENV_FILE:-env/ecs.env}"

log() {
  printf '[asb-deploy] %s\n' "$*"
}

main() {
  log "Starting deployment from ${ASB_DIR}..."

  if [[ ! -d "${ASB_DIR}" ]]; then
    log "Directory ${ASB_DIR} does not exist. Did you run bootstrap?"
    exit 1
  fi

  cd "${ASB_DIR}"

  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log "Compose file ${COMPOSE_FILE} not found."
    exit 1
  fi

  if [[ ! -f "${ENV_FILE}" ]]; then
    log "Env file ${ENV_FILE} not found. Copy env/ecs.env.example and customize it."
    exit 1
  fi

  log "Pulling latest container images..."
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull

  log "Applying docker compose stack..."
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d --remove-orphans

  log "Current service status:"
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" ps

  log "Deployment completed successfully."
}

main "$@"

