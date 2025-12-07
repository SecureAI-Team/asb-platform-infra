#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.ecs.yml}"
ENV_FILE="${ENV_FILE:-env/ecs.env}"
SERVICE_NAME="${SERVICE_NAME:-keycloak}"
REALM_FILE="${REALM_FILE:-/opt/keycloak/realms/realm-asb.json}"

if ! command -v docker compose >/dev/null 2>&1; then
  echo "[keycloak-import] docker compose command not found."
  exit 1
fi

echo "[keycloak-import] Waiting for Keycloak to become healthy..."
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps "${SERVICE_NAME}"

echo "[keycloak-import] Importing realm from ${REALM_FILE}..."
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec "${SERVICE_NAME}" \
  /opt/keycloak/bin/kc.sh import --file "${REALM_FILE}" --override true

echo "[keycloak-import] Realm import completed."

