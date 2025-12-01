# ASB Platform Infra Architecture

## Purpose
`asb-platform-infra` is the single source of truth for packaging and deploying the entire ASB Security Platform onto a single Alibaba Cloud ECS VM (test environment). Application repositories only build and push Docker images; this repo runs them via `docker-compose.ecs.yml`, keeps example env files, provides ECS bootstrap/deploy scripts, and owns the GitHub Actions workflow that SSHes into the VM and executes `docker compose up -d`.

## Related Repositories
- `asb-enterprise-control-plane`: builds `asb-control-plane-backend` (Go) and `asb-control-plane-frontend` (Vue).
- `asb-secure-gateway`: builds `asb-gateway`.
- `asb-security-services`: builds security microservices (`auth-service`, `policy-service`, `privacy-service`, `prompt-defense`, `output-guard`, `agent-control`, `audit-service`, etc.).
- `asb-demo-apps` (optional): builds demo apps such as Dify, Milvus, Minio.

These repos push Docker images to Alibaba Cloud Container Registry (ACR), e.g. `registry.cn-hangzhou.aliyuncs.com/asb/...`. None of them deploy to ECS directly; deployment happens only through `asb-platform-infra`.

## Service Taxonomy

| Category          | Services                                                                                                                         |
|-------------------|----------------------------------------------------------------------------------------------------------------------------------|
| Infra / Shared    | `postgres`, `redis`, `keycloak`, `opa`, `clickhouse`, `prometheus` (optional), `grafana` (optional)                               |
| Control Plane     | `asb-control-plane-backend`, `asb-control-plane-frontend`                                                                        |
| Data Plane        | `asb-gateway`                                                                                                                    |
| Security Services | `auth-service`, `policy-service` (OPA adapter), `privacy-service`, `prompt-defense`, `output-guard`, `agent-control`, `audit-service` |
| Demo Apps         | `dify-api`, `dify-worker`, `dify-web`, `milvus`, `minio`, other optional placeholders                                            |

All containers attach to a single Docker bridge network defined in `docker-compose.ecs.yml`.

## Docker Images
Each service references a tagged image in Alibaba Cloud ACR:

- Control plane backend: `registry.cn-hangzhou.aliyuncs.com/asb/control-plane-backend:<tag>`
- Control plane frontend: `registry.cn-hangzhou.aliyuncs.com/asb/control-plane-frontend:<tag>`
- Gateway: `registry.cn-hangzhou.aliyuncs.com/asb/secure-gateway:<tag>`
- Security services: `registry.cn-hangzhou.aliyuncs.com/asb/auth-service:<tag>`, etc.
- Infra components may use upstream images (`postgres:16-alpine`, `redis:7`, `clickhouse/clickhouse-server:latest`, `keycloak/keycloak:24`, …) or hardened ASB builds.

Use semantic tags (e.g., `:v0.5.2`) for reproducibility; reserve `:latest` for dev/test.

## ECS Topology
- Single Alibaba Cloud ECS VM (test tier) running Docker Engine + Compose plugin.
- `scripts/bootstrap-ecs.sh` installs Docker, configures the `asb` user, and prepares directories (`/opt/asb`, `/var/lib/asb-data/*`).
- Environment variables live in `/opt/asb/ecs.env` (based on `env/ecs.env.example`).
- `docker-compose.ecs.yml` defines all services, shared network, persistent volumes for stateful services (Postgres, ClickHouse, Minio, Milvus), resource limits, and `depends_on` ordering so infra comes up first.

## Deployment Flow
1. Application repos build/push their images to ACR.
2. `asb-platform-infra` GitHub Actions workflow (`.github/workflows/deploy-ecs.yml`) is triggered (manual dispatch, tag, or schedule).
3. Workflow SSHes into the ECS VM using stored secrets and runs `scripts/deploy.sh`.
4. `deploy.sh` pulls the images, then executes `docker compose --env-file ecs.env up -d --remove-orphans`.
5. ECS VM now hosts infra, control plane, data plane, security services, and optional demos on the shared bridge network.

**Only `asb-platform-infra` is authorized to SSH into the ECS VM for CI/CD deployment.** Other repos must limit themselves to build and push operations; they must not invoke `docker compose` remotely.

## Future Enhancements
- Add health-check/smoke-test hooks post-deploy.
- Extend monitoring (Prometheus/Grafana) to cover ECS node metrics.
- Integrate secrets management (Alibaba KMS, HashiCorp Vault) for sensitive env vars.

