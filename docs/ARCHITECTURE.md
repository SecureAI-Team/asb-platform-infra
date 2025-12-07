# ASB Platform Infra Architecture

## Purpose
`asb-platform-infra` packages every component required to run the ASB Security Platform on a single Alibaba Cloud ECS instance (Ubuntu 24.04). Application repositories (control plane, gateway, security services) only build Docker images and push them into Aliyun ACR (`${ACR_REGISTRY}/${ACR_NAMESPACE}`); this repo owns the ECS bootstrap scripts, Docker Compose stack, initialization SQL/realm definitions, TLS termination, and operational documentation.

## Component Overview

```
┌───────────────┐      ┌────────────┐
│   Internet    │─────▶│   Nginx    │ TLS (443) proxies /cp /gateway /keycloak
└───────────────┘      └─┬──────────┘
                          │
          ┌───────────────────────────────────────────────┐
          │                   asbnet                      │
          │                                               │
          │  Infra:  postgres (init SQL), redis, keycloak │
          │          opa, clickhouse (init SQL)           │
          │  Apps :  cp-backend, cp-frontend, gateway     │
          │          auth, policy, privacy, prompt-defense│
          │          output-guard, agent-control, audit   │
          │          example-service                      │
          └───────────────────────────────────────────────┘
```

All containers attach to the `asbnet` bridge network. Nginx is the only service exposing 80/443 to the outside world and terminates TLS using self-signed certs generated during bootstrap (operators should replace them with real certificates for production).

## Repository Contents

- `docker-compose.ecs.yml` – Defines infra, application, and security services. Adds healthchecks/`depends_on` with `condition: service_healthy`, mounts initialization assets, and exposes the nginx TLS layer.
- `env/ecs.env.example` – Template configuring ACR registry/namespace, image references, database credentials, Keycloak admin + realm, host ports, etc. Copy to `env/ecs.env` and edit on the ECS host.
- `scripts/bootstrap-ecs.sh` – One-time host prep. Installs Docker Engine + Compose plugin, generates self-signed certs in `certs/`, seeds `env/ecs.env` (if missing) with randomized secrets, and optionally logs into ACR.
- `scripts/deploy.sh` – Pulls container images from ACR and runs `docker compose --env-file env/ecs.env -f docker-compose.ecs.yml up -d --remove-orphans`.
- `postgres/init/00-create-databases.sql` – Creates the logical databases required by ASB services (schemas are created by each service at runtime).
- `clickhouse/init/security_events.sql` – Creates the `asb_events.security_events` table for the audit-service pipeline.
- `keycloak/realm-asb.json` & `keycloak/import-realm.sh` – Minimal Keycloak realm export plus helper script to import it into the running Keycloak container.
- `nginx/nginx.conf` – Reverse proxy configuration (TLS termination + routing to cp-frontend, gateway, keycloak).
- `docs/ARCHITECTURE.md` – This document; see below for runbooks and manual steps.

## ECS Bootstrap & Deployment Flow

1. **Provision ECS** – Ubuntu 24.04 with outbound access to ACR/GitHub.
2. **Bootstrap (run once):**
   ```bash
   sudo su -
   git clone https://github.com/SecureAI-Team/asb-platform-infra.git /opt/asb-platform-infra
   cd /opt/asb-platform-infra
   scripts/bootstrap-ecs.sh
   ```
   This installs Docker + Compose, generates `/opt/asb-platform-infra/certs/server.{crt,key}` (self-signed), and creates `env/ecs.env` if it does not exist.
3. **Configure environment:**
   - Edit `env/ecs.env` with real ACR credentials (`ACR_USERNAME/ACR_PASSWORD`), image tags, database passwords, and Keycloak client secrets.
   - Create Postgres databases if additional ones are required beyond the init script.
4. **Deploy / Update:**
   ```bash
   cd /opt/asb-platform-infra
   scripts/deploy.sh
   ```
   The script logs into ACR (if creds exist), pulls images, stops the running stack, removes all named volumes (`pgdata`, `redis-data`, `keycloak-data`, `clickhouse-data`), and brings the compose stack back up. **All persistent data is wiped on every run**, so only use this flow in disposable test environments unless you adjust the script.
5. **Optional CI/CD:** `.github/workflows/deploy-ecs.yml` SSHes into the host and runs `scripts/deploy.sh`. It assumes the repo is already cloned on ECS.

## Initialization Hooks & Manual Steps

### Postgres
- `postgres/init/00-create-databases.sql` runs automatically on first container start and creates `asb_control_plane`, `asb_auth`, `asb_audit`, `asb_gateway`.
- Schemas/migrations are executed by each application on startup. Operators only need to ensure the logical DBs exist.

### ClickHouse
- `clickhouse/init/security_events.sql` creates the `asb_events` database and the `security_events` table. If the audit-service repo provides a canonical DDL later, replace the file and redeploy.

### Keycloak Realm
- After Keycloak is healthy, import the bundled realm (or configure manually):
  ```bash
  ./keycloak/import-realm.sh
  ```
  This loads `realm-asb.json` (clients: cp-frontend, cp-backend, asb-gateway). Update the JSON if client secrets or redirect URIs change.
- Alternatively, log into the Keycloak UI via `https://<ECS_IP>/keycloak` (proxied through nginx) and configure the realm/clients manually.

### TLS Certificates & Nginx
- Bootstrap generates `/opt/asb-platform-infra/certs/server.crt` and `server.key`. Replace them with CA-issued certificates for production and rerun `scripts/deploy.sh`.
- `nginx/nginx.conf` proxies:
  - `/cp` → `cp-frontend`
  - `/gateway` → `gateway`
  - `/keycloak` → `keycloak`
  Adjust upstreams if service names or paths change.

### Service Health & Dependencies
- Compose healthchecks ensure infra is up before dependent services start. Use `docker compose ps` to see health states.
- To inspect logs:
  ```bash
  docker logs -f asb-platform-infra-cp-backend-1
  docker logs -f asb-platform-infra-gateway-1
  ```

## Manual Verification Checklist

1. `docker compose --env-file env/ecs.env -f docker-compose.ecs.yml ps` (all services `Up (healthy)`).
2. `https://<ECS_IP>/cp` loads the control plane UI via nginx (accept the self-signed cert or replace with trusted cert).
3. `https://<ECS_IP>/gateway` responds (depends on gateway config).
4. `https://<ECS_IP>/keycloak` shows Keycloak login page; `realm-asb` exists with expected clients.
5. Postgres contains the required databases:
   ```bash
   docker exec -it asb-platform-infra-postgres-1 psql -U "$POSTGRES_USER" -d postgres -c "\l"
   ```
6. ClickHouse table exists:
   ```bash
   docker exec -it asb-platform-infra-clickhouse-1 clickhouse-client -q "SHOW TABLES FROM asb_events"
   ```

## Notes for Application Teams
- Control plane, gateway, and security services must expose `/healthz` endpoints for the compose healthchecks to pass.
- Each service should handle DB migrations/schema bootstrapping on startup (the infra only creates the empty databases).
- When a new service is added, publish its image to ACR and add the corresponding `${ASB_*_IMAGE}` variable + compose entry.

By centralizing these concerns in `asb-platform-infra`, deploying to a fresh ECS host becomes:
1. Run `scripts/bootstrap-ecs.sh`.
2. Edit `env/ecs.env`.
3. Execute `scripts/deploy.sh`.
4. (Optional) Import Keycloak realm and verify DBs.

All subsequent updates are `git pull` + `scripts/deploy.sh`, ensuring a reproducible, fully scripted “one-click” deployment experience.

