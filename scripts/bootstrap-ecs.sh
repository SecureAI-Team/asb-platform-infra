#!/usr/bin/env bash
set -euo pipefail

ASB_DIR="${ASB_DIR:-/opt/asb-platform}"
ASB_INFRA_REPO_URL="${ASB_INFRA_REPO_URL:-}"

log() {
  printf '[asb-bootstrap] %s\n' "$*"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log "This script must be run as root (sudo)."
    exit 1
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed; skipping."
    return
  fi

  log "Installing Docker Engine and Compose plugin..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl start docker
}

prepare_repo_dir() {
  log "Ensuring application directory exists at ${ASB_DIR}..."
  mkdir -p "${ASB_DIR}"

  if [[ -d "${ASB_DIR}/.git" ]]; then
    log "asb-platform-infra repository already present; skipping clone."
    return
  fi

  if [[ -n "${ASB_INFRA_REPO_URL}" ]]; then
    log "Cloning repository from ${ASB_INFRA_REPO_URL}..."
    git clone "${ASB_INFRA_REPO_URL}" "${ASB_DIR}"
  else
    log "Repository URL not provided (ASB_INFRA_REPO_URL unset)."
    log "Please clone asb-platform-infra into ${ASB_DIR} manually."
  fi
}

post_instructions() {
  cat <<'EOF'

Next steps:
  1. Populate env/ecs.env with environment-specific values (registry image tags,
     database passwords, Keycloak admin credentials, etc.). See env/ecs.env.example.
  2. Review docker-compose.ecs.yml and adjust ports/resource limits if needed.
  3. Use scripts/deploy.sh (or the GitHub Actions workflow) to pull images and
     run docker compose up -d on the ECS host.

Re-running this bootstrap script is safe; it will only install missing components.
EOF
}

main() {
  require_root
  install_docker
  prepare_repo_dir
  post_instructions
  log "Bootstrap complete."
}

main "$@"

