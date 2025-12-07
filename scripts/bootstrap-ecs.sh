#!/usr/bin/env bash
set -euo pipefail

ASB_BASE_DIR="${ASB_BASE_DIR:-/opt/asb-platform-infra}"
ENV_FILE="${ASB_BASE_DIR}/env/ecs.env"

log() {
  echo "[asb-bootstrap] $*"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log "This script must be run with sudo/root privileges."
    exit 1
  fi
}

assert_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    log "Cannot detect OS (missing /etc/os-release). Aborting."
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    log "Unsupported OS: ${PRETTY_NAME:-unknown}. This script targets Ubuntu 24.04."
    exit 1
  fi

  if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    log "Warning: detected Ubuntu ${VERSION_ID}. Proceeding, but script is tested on 24.04."
  else
    log "Detected Ubuntu 24.04 (${PRETTY_NAME})."
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed. Skipping installation."
    return
  fi

  log "Installing Docker Engine + Compose plugin..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename
  codename=$(lsb_release -cs)
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    ${codename} stable" >/etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl start docker
  log "Docker installation complete."
}

prepare_directories() {
  log "Ensuring base directory exists at ${ASB_BASE_DIR}..."
  mkdir -p "${ASB_BASE_DIR}"
  log "Directory ready."
}

acr_login_if_configured() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    log "No ${ENV_FILE} found. Skipping ACR login (configure env/ecs.env later)."
    return
  fi

  # shellcheck disable=SC1090
  source "${ENV_FILE}"

  if [[ -n "${ACR_REGISTRY:-}" && -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
    log "Logging into ACR registry ${ACR_REGISTRY}..."
    echo "${ACR_PASSWORD}" | docker login "${ACR_REGISTRY}" -u "${ACR_USERNAME}" --password-stdin
    log "ACR login succeeded."
  else
    log "ACR credentials incomplete in ${ENV_FILE}. Skipping docker login."
  fi
}

post_summary() {
  cat <<EOF

Docker & Docker Compose plugin are installed.

Next steps:
  1. git clone https://github.com/<your-org>/asb-platform-infra.git ${ASB_BASE_DIR}
  2. Copy env/ecs.env.example to env/ecs.env and update registry tags, passwords,
     and Aliyun credentials. Keep env/ecs.env out of Git.
  3. Run scripts/deploy.sh (manually or via CI) to pull images and start the stack.

You can re-run this bootstrap script safely; it only installs missing components.
EOF
}

main() {
  require_root
  assert_ubuntu
  install_docker
  prepare_directories
  acr_login_if_configured
  post_summary
  log "Bootstrap procedure complete."
}

main "$@"
