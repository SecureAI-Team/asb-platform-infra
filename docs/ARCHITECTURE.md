# ASB Platform Infra Architecture

## Purpose
`asb-platform-infra` is the authoritative infrastructure repository for running the ASB Security Platform on a single Alibaba Cloud ECS instance (Ubuntu 24.04). Application repositories are responsible for building container images and pushing them to Aliyun Container Registry (ACR), but only this repo defines how the images are composed, how the ECS node is prepared, and how deployments are executed (manually or via CI) in a repeatable “one-click” fashion.

- **ACR location:** `${ACR_REGISTRY}/${ACR_NAMESPACE}/<repo-name>:<tag>`, where by default `ACR_REGISTRY=registry.cn-hangzhou.aliyuncs.com` and `ACR_NAMESPACE=asbsecurity`.
- **Scope:** One ECS VM, single Docker Compose stack, single user-defined network (`asbnet`), persistent named volumes for stateful components.

## Service Catalog

| Category       | Services & Image Source                                                                              |
|----------------|------------------------------------------------------------------------------------------------------|
| Infra          | `postgres`, `redis`, `keycloak`, `opa`, `clickhouse` (official upstream images)                      |
| Control Plane  | `cp-backend`, `cp-frontend` (`${ACR_REGISTRY}/${ACR_NAMESPACE}/cp-backend`, `cp-frontend`)           |
| Gateway        | `asb-secure-gateway` (`${ACR_REGISTRY}/${ACR_NAMESPACE}/asb-secure-gateway`)                         |
| Security Svcs  | `auth`, `policy`, `privacy`, `prompt-defense`, `output-guard`, `agent-control`, `audit` (ACR)        |
| Demo Service   | `example-service` (optional ACR image used for integration smoke tests)                              |

Every service joins the `asbnet` bridge network so it can communicate privately with the rest of the stack on the same ECS host.

## Repository Layout

- `docker-compose.ecs.yml` &mdash; Single Compose definition that wires infra, control plane, gateway, security services, and optional demos together on `asbnet`. Uses environment variables for image references, ports, and credentials, and defines named volumes (`pgdata`, `redis-data`, `keycloak-data`, `clickhouse-data`, etc.) for persistence.
- `env/ecs.env.example` &mdash; Template for `env/ecs.env`. Captures registry settings (`ACR_REGISTRY`, `ACR_NAMESPACE`), image tags, database passwords, Keycloak admin credentials, and exposed ports. Operators copy it, replace placeholders with real secrets, and keep the populated file out of Git.
- `scripts/bootstrap-ecs.sh` &mdash; Run once on a fresh Ubuntu 24.04 ECS node. Installs Docker Engine + Compose plugin, logs into ACR if needed, prepares `/opt/asb-platform`, and reminds operators to configure `env/ecs.env`. Idempotent so it can be re-run safely.
- `scripts/deploy.sh` &mdash; Run for each deployment/upgrade. Changes into `/opt/asb-platform`, pulls the images listed in `docker-compose.ecs.yml` with `--env-file env/ecs.env`, and executes `docker compose up -d --remove-orphans`.
- `.github/workflows/deploy-ecs.yml` &mdash; Optional GitHub Actions workflow that SSHes into the ECS VM (`ECS_HOST`, `ECS_USER`, `ECS_SSH_KEY`, `ECS_DEPLOY_PATH` secrets) and runs `scripts/deploy.sh`. Triggered manually (`workflow_dispatch`) or by upstream repos via `repository_dispatch`.
- `docs/ARCHITECTURE.md` &mdash; This document, explaining how all components fit together and how other repos interact with the infra pipeline.

## Configuration & Images

- **Environment:** All configurable values live in `env/ecs.env` (copied from the example). This includes the registry endpoint, namespace, per-service tags, database credentials, Keycloak settings, OPA URLs, and host port mappings (`CP_BACKEND_PORT`, `CP_FRONTEND_PORT`, `GATEWAY_PORT`, etc.).
- **Images:** Every ASB-owned service references `${ACR_REGISTRY}/${ACR_NAMESPACE}/<repo>:<tag>` so changing regions or tags is just an environment update. Infra services use stable upstream images but can be overridden via env vars as well.
- **Secrets:** Operators must never commit populated env files. Instead, they configure GitHub Secrets (for CI) and copy the env example locally on the ECS node.

## Lifecycle

1. **Build & Push:** Application repos (`cp-backend`, `cp-frontend`, `asb-secure-gateway`, `auth`, `policy`, etc.) build artifacts and push tagged images into the `asbsecurity` namespace in ACR.
2. **Bootstrap:** On a new ECS host, run `scripts/bootstrap-ecs.sh` (via SSH) to install Docker + Compose, clone this repo into `/opt/asb-platform`, and prepare directories/permissions.
3. **Configure:** Copy `env/ecs.env.example` to `env/ecs.env`, customize registry credentials, select image tags, and set service secrets/ports.
4. **Deploy:** Run `scripts/deploy.sh` (or trigger `.github/workflows/deploy-ecs.yml`) to pull images and start the stack using `docker compose -f docker-compose.ecs.yml --env-file env/ecs.env up -d`.
5. **Operate:** Use `docker compose ps/logs` on the ECS host for troubleshooting. Re-run `scripts/deploy.sh` whenever image tags change or configuration updates are needed.

Only `asb-platform-infra` (or its CI workflow) is permitted to SSH into the ECS host for deployment. Application repositories remain limited to building and pushing images; they never run Docker Compose remotely. This separation guarantees a single source of truth for runtime configuration and keeps the ECS environment consistent.

