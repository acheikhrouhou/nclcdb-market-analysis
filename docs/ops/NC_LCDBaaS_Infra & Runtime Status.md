This is exactly the right moment to freeze the state, write it down like an ops handover, and make sure someone new could 1) understand what exists, 2) run it, 3) scale it.

Below is a status report / architecture brief for your DevOps engineer.

---

# NC LCDBaaS — Infra & Runtime Status (as of 2025-11-03)

## 0. High-level Goal

We are building a multi-tenant Low-Code / No-Code Database-as-a-Service.
Right now we have:

* **Two VMs**:

  * VM-DB: data layer (databases + cache)
  * VM-Web: application layer (API + web apps + reverse proxy)
* **Separation of planes**:

  * Control plane: tenant/account/billing/keys
  * Data plane: customer data / tables
  * Log plane: audit + activity traces
* **App layer**: Express/Node API + portal/admin/marketing apps behind nginx

This document describes current state so DevOps can:

* operate it,
* replicate it,
* start thinking about scaling.

---

## 1. Physical / VM layout

### VM-DB

Role: data backend.

Services running (all Docker containers):

* `control-db` (Postgres 16)
* `data-db` (Postgres 16)
* `logs-db` (Postgres 16)
* `redis` (Redis 7-alpine)

Firewall (ufw):

* Only allows inbound from VM-Web’s IP to:

  * TCP 5432 (control-db)
  * TCP 5433 (data-db)
  * TCP 5434 (logs-db)
  * TCP 6379 (redis)
* Allows SSH from operator addresses / mgmt only.
* Everything else DROP.

Docker networking on VM-DB:

* Default bridge networks from Docker (eg. `nclc_internal` created early on).
* Each db container is bound to `0.0.0.0` at a distinct port, so VM-Web connects via LAN IP (e.g. `192.168.106.138:5432`).

Persistent storage on VM-DB:

* We’re using named Docker volumes:

  * `control-db-data` → `/var/lib/postgresql/data` for control-db
  * `data-db-data`    → `/var/lib/postgresql/data` for data-db
  * `logs-db-data`    → `/var/lib/postgresql/data` for logs-db
* Redis currently uses in-memory only, no durable AOF snapshotting (for now). It's fine for caching/rate limit, not fine for durable queue semantics.

Directory layout on VM-DB:

```text
/opt/nclcdbaas/
  db/
    docker-compose.db.yml
    postgres/
      control-db/
        conf.d/
        initdb.d/        <= initial SQL seeds (roles, grants, etc.)
      data-db/
        conf.d/
        initdb.d/
      logs-db/
        conf.d/
        initdb.d/
  .env/
    db.env               <= original env for DB container bootstrap
```

Current runtime facts:

* Postgres superuser equivalents:

  * `control_admin` on control-db
  * `data_admin` on data-db
  * `logs_admin` on logs-db
* App (runtime) roles with least privilege:

  * `control_app_rw` with password `<known>`, has CRUD on control schema
  * `data_app_rw` with password `<known>`, has CRUD on base_shared schema (data plane)
  * `logs_app_rw` with password `<known>`, has INSERT on logs schema (audit trail)
* Redis:

  * No password enforced yet (inside private LAN + ufw restricted).
  * Accessible from VM-Web at `redis://192.168.106.138:6379`

Networking:

* VM-DB IP (example): `192.168.106.138`
* Docker binds Postgres containers to 0.0.0.0 on that VM so VM-Web can talk over LAN.

---

### VM-Web

Role: application layer (frontend apps + API + ingress proxy).

Services running (Docker containers):

* `api-service` (Node.js 22 / Express) → core backend API.
* `portal-app` (Node.js runtime container) → the tenant portal UI (app.nclcdbaas.com).
* `www-app` (Node.js runtime container) → the marketing site / docs ([www.nclcdbaas.com](http://www.nclcdbaas.com)).
* `admin-app` (Node.js runtime container) → internal/admin console (admin.nclcdbaas.com).
* `nginx-proxy` (nginx:latest) → reverse proxy / host-based routing.

File layout on VM-Web:

```text
/opt/nclcdbaas/
  web/
    docker-compose.web.yml
    nginx/
      conf.d/
        default.conf      <= host routing rules
      certs/              <= (future) TLS certs / keys or acme mounts
      logs/               <= nginx access/error logs
    apps/
      api/
        Dockerfile
        package.json
        index.js          <= Express app
        (future: routes/, services/, etc.)
      www/
        Dockerfile
        config/
      portal/
        Dockerfile
        config/
      admin/
        Dockerfile
        config/
  backups/
  .env/
    web.env              <= (for future use; currently mostly inline env)
    db.env               <= (legacy, not actively interpolated anymore)
```

Important runtime decision:

* We intentionally hardcoded critical env values for now directly in `docker-compose.web.yml` under `api-service.environment`, like:

  * `CONTROL_DB_URL`
  * `DATA_DB_URL`
  * `LOG_DB_URL`
  * `REDIS_URL`
  * `JWT_SECRET`
* This makes the environment self-contained and reproducible. No hidden dependency on missing .env files.
* Long-term, secrets should move to `.env/web.env` or Vault/SSM, but for bootstrap this is safer because it reduces “it works on Aref’s VM but nowhere else” surprises.

Networking on VM-Web:

* Internal Docker network: `nclc_internal`

  * All app containers live on this network.
  * `nginx-proxy` reverse-proxies to the internal container names (www-app, portal-app, admin-app, api-service).
* External exposure:

  * We’re currently doing host ports → nginx:

    * `nginx-proxy` publishes `80:80` and `443:443` (443 not fully configured yet but reserved).
  * For debugging, we also added:

    ```yaml
    ports:
      - "4000:4000"
    ```

    to `api-service`, so you can `curl http://localhost:4000/healthz` directly on VM-Web. This is for development/testing and should be removed for production, because production should expose API only through nginx.

Nginx routing:

* `web/nginx/conf.d/default.conf` currently has something like:

  ```nginx
  server {
    listen 80;
    server_name www.nclcdbaas.com;
    location / { proxy_pass http://www-app:3000; }
  }

  server {
    listen 80;
    server_name app.nclcdbaas.com;
    location / { proxy_pass http://portal-app:3000; }
  }

  server {
    listen 80;
    server_name admin.nclcdbaas.com;
    allow 10.0.0.0/8;  # <- placeholder internal restriction
    deny all;
    location / { proxy_pass http://admin-app:3000; }
  }

  server {
    listen 80;
    server_name api.nclcdbaas.com;
    location / { proxy_pass http://api-service:4000; }
  }
  ```

Note:

* We’ll want to update ports if `www-app`, `portal-app`, `admin-app` don’t actually run on `3000` internally. Right now each Node Dockerfile uses `CMD ["npm","start"]` with `"start": "node index.js"` or similar stub; eventually each must listen on a known port. For the API we explicitly listen on `4000` in Express.
* We’ve already confirmed `api-service` runs on port 4000 inside the container.

---

## 2. Current service behavior

### api-service

* Language/runtime: Node.js 22-slim
* Framework: Express
* Entrypoint: `/opt/nclcdbaas/web/apps/api/index.js` (copied into container)
* It:

  * creates a Postgres connection pool to the **control-db** using `CONTROL_DB_URL`
  * connects to Redis using `REDIS_URL`
  * offers `/healthz` that returns DB time + Redis ping
  * listens on port 4000 and keeps running
* We added `ports: "4000:4000"` in Compose for testing so we can hit `curl http://localhost:4000/healthz` from VM-Web.

  * In production we will remove that and let nginx own public exposure on 80/443.

### www-app / portal-app / admin-app

* Right now these are placeholder Node containers with skeleton Dockerfiles.
* They boot but they’re not yet serving meaningful app code.
* They’re wired into nginx virtual hosts:

  * `www.nclcdbaas.com` → marketing/docs site
  * `app.nclcdbaas.com` → tenant self-service portal (create DBs, manage API keys, billing, usage)
  * `admin.nclcdbaas.com` → internal backoffice for support, audits, tenant suspension, etc.
* `admin.nclcdbaas.com` is restricted in nginx to allowed networks only. Later, we should change that to a VPN/VPC rule or mTLS, not just `allow` CIDR, but this is the right instinct.

---

## 3. Database model (logical)

We’ve split state into 3 planes for clarity, compliance, and blast radius.

### Control Plane DB (control-db @ 5432)

Holds:

* Tenants
* Users / owners / admins for each tenant
* Tenant subscriptions / payment references / quotas / usage counters
* API tokens (which tenant they belong to, which DB they can touch, rate limit, etc.)
* Service configuration (per-tenant limits, row caps, automation run credit balance, etc.)

Main runtime role:

* `control_app_rw`

  * Has CRUD on these tables but is *not* superuser.
  * Used by `api-service` to authenticate incoming tokens and check quotas.

Why separate?

* This is “brains & billing”. You want this tight and auditable.

### Data Plane DB (data-db @ 5433, DB name: `base_shared`)

Holds:

* Actual tenant data tables (their “bases”, like Airtable bases).
* In MVP mode we’re running a shared Postgres instance with multiple logical schemas / tables per tenant.
* Later we can escalate to per-tenant schemas or even per-tenant physical DBs.

Main runtime role:

* `data_app_rw`

  * Has CRUD on tenant tables.
  * This is the identity your public API (with a tenant’s API key) will eventually use to read/write rows.

Why separate?

* If data-db is compromised or overloaded it doesn’t directly expose billing, API keys, etc.
* Easier to scale independently (read replicas, partitioning, etc.).

### Logs / Audit DB (logs-db @ 5434)

Holds:

* Audit events:

  * who called what API
  * from which IP
  * what table was touched
  * errors / throttling / quota exceeded events
* Admin portal actions:

  * suspension of a tenant
  * manual credit adjustment
  * role changes, etc.

Main runtime role:

* `logs_app_rw`

  * Usually INSERT-only into append-only tables.
  * This preserves immutability and evidence trail.

Why separate?

* Forensics and compliance.
* Helps prove we didn’t silently tamper with tenant data.
* Lets us offload logging writes so hot telemetry doesn’t slow the main control plane.

---

## 4. Networking model

**Between VMs:**

* VM-Web ↔ VM-DB over LAN via 192.168.106.x
* Only VM-Web IP is allowed by ufw to access VM-DB’s Postgres ports and Redis.

**Inside VM-Web:**

* Docker network `nclc_internal` connects:

  * `nginx-proxy`
  * `api-service`
  * `www-app`
  * `portal-app`
  * `admin-app`

* `nginx-proxy` listens on `0.0.0.0:80` (and 443 reserved) and routes traffic based on Host header:

  * `api.nclcdbaas.com` → `api-service:4000`
  * `app.nclcdbaas.com` → `portal-app:3000` (placeholder)
  * `www.nclcdbaas.com` → `www-app:3000` (placeholder)
  * `admin.nclcdbaas.com` → `admin-app:3000` (internal only)

**During dev:**

* We also temporarily mapped `api-service` port 4000 directly to the host (`4000:4000`) so we can hit `/healthz` from VM-Web’s shell. That’s a debug convenience, not final production posture.

---

## 5. File / config model

Main tree:

```text
/opt/nclcdbaas
  build-starter.sh          <= bootstrap script we originally used to generate dirs/files
  README.md                 <= early setup notes / quickstart
  backups/                  <= placeholder for pg_dumps etc in future

  .env/
    db.env                  <= original DB bootstrap secrets; now mostly historical
    web.env                 <= placeholder for future centralization of api-service env

  db/
    docker-compose.db.yml   <= defines control-db, data-db, logs-db, redis
    postgres/
      control-db/initdb.d/  <= SQL to create roles/permissions @ first launch
      data-db/initdb.d/
      logs-db/initdb.d/

  web/
    docker-compose.web.yml  <= defines nginx-proxy, api-service, www-app, portal-app, admin-app
    nginx/
      conf.d/default.conf   <= vhost routing logic (www/app/admin/api...)
      certs/                <= to store TLS certificates later
      logs/                 <= nginx access/error logs
    apps/
      api/
        Dockerfile
        package.json
        index.js
      www/
        Dockerfile
        config/...
      portal/
        Dockerfile
        config/...
      admin/
        Dockerfile
        config/...
```

Key principle:

* All core runtime logic for API sits in `web/apps/api/`.
* All infra logic (compose, nginx, networking, env injection) is in `/opt/nclcdbaas/web`.
* All data (Postgres, Redis) and their lifecycle are on VM-DB in `/opt/nclcdbaas/db`.

---

## 6. Operational runbook (current)

**Bring up data layer (VM-DB):**

```bash
cd /opt/nclcdbaas
docker compose -f db/docker-compose.db.yml --env-file .env/db.env up -d
docker compose -f db/docker-compose.db.yml ps
```

**Bring up app layer (VM-Web):**

```bash
cd /opt/nclcdbaas
docker compose -f web/docker-compose.web.yml \
  up -d --build
docker compose -f web/docker-compose.web.yml ps
```

**Check API health:**

* If `ports: "4000:4000"` is enabled for `api-service`:

  ```bash
  curl http://localhost:4000/healthz
  ```

  Should return JSON including `"status":"ok"`.

**Rotate a DB password:**

1. Change it inside the running Postgres container on VM-DB using `ALTER ROLE ... PASSWORD 'newValue';`
2. Update the literal URL in `docker-compose.web.yml` on VM-Web (for example `CONTROL_DB_URL`)
3. Rebuild / restart api-service:

   ```bash
   docker compose -f web/docker-compose.web.yml up -d --build api-service
   ```

**Backup strategy (not implemented yet, but design intent):**

* Nightly `pg_dump` for each of the three Postgres DBs into `/opt/nclcdbaas/backups/` on VM-DB (or mounted NFS).
* Versioned snapshots for `control-db` and `logs-db` are especially critical for audit and recovery.

---

## 7. Scaling direction (next steps for DevOps)

Here’s where a DevOps engineer should focus to take this from PoC → production-ready.

### A. Storage / persistence

Right now:

* Postgres data sits in local Docker volumes on VM-DB.
* That’s fine for a prototype, but it's a single point of failure.

Next steps:

1. Move Postgres data directories to mounted block storage/LVM (so you can snapshot at hypervisor/storage layer).
2. Consider streaming WAL archiving or hot standby replicas (even one read-only replica VM-DB-2).
3. Logs DB will grow fastest in row count. Plan table partitioning (by month) in `logs-db` so it doesn’t get sluggish over time.

### B. CPU / memory / throughput

Right now:

* Everything is on two VMs.
* api-service, www-app, portal-app, admin-app, nginx are all on VM-Web.
* All Postgres + Redis are on VM-DB.

Future:

* You can split horizontally by role:

  * VM-Web-API: run only `api-service` + Redis (high CPU, high concurrency)
  * VM-Web-FRONT: run `www-app`, `portal-app`, `admin-app`, and nginx (mostly static-ish UI / SSR work)
  * VM-DB: run Postgres only
* Or vertically scale:

  * Give VM-DB more RAM and faster disk so Postgres caches more in memory.
  * Give VM-Web more CPU cores so Node’s single-thread event loop has headroom via multiple replicas.

### C. Network / ingress

Right now:

* nginx-proxy on VM-Web is public on port 80 (HTTP).
* TLS (443) is there but not configured.

Next:

1. Add TLS certs (Let's Encrypt or internal ACME) so you terminate HTTPS at nginx.
2. Lock down `api-service` so it's *not* published with `ports: "4000:4000"` in production. Only nginx should reach it on the internal Docker network.
3. Eventually put nginx behind an external load balancer / reverse proxy (HAProxy, cloud LB, etc.) so you can horizontally scale VM-Web and run multiple nginx nodes.

### D. Secrets management

Right now:

* DB URLs and JWT secret are in `docker-compose.web.yml`.

Next:

1. Move secrets to `/opt/nclcdbaas/.env/web.env`.
2. Stop committing real secrets to Git.
3. Later, move secrets to a secure store (Vault, AWS SSM Parameter Store, etc.).
4. Rotate DB role passwords regularly and update the env file + redeploy.

### E. Multi-tenant data isolation

Right now:

* Single `data-db` Postgres instance for all tenants, with shared database `base_shared`.
* The app role `data_app_rw` has broad CRUD across that DB.

Future options for scale / isolation:

1. **Per-tenant schema** in the same Postgres instance:

   * `tenant_123.customers`, `tenant_123.orders`, etc.
   * Let us revoke at schema level, easier per-tenant export/delete.
2. **Per-tenant database** in the same Postgres server (`CREATE DATABASE tenant_123;`):

   * More isolation, but more overhead at high tenant counts.
3. **Dedicated Postgres instance / cluster for big customers**:

   * This becomes an upsell SKU: “Dedicated performance / data residency”.

This is your path to “industrialization”.

### F. Observability / audit

Right now:

* We have logs-db conceptually, but we’re not yet inserting audit events from the API.

Next:

1. Add request logging in api-service:

   * who (token / tenant_id),
   * what endpoint,
   * when,
   * success/fail.
2. Write those to `logs-db` via `logs_app_rw`.
3. Add basic metrics dashboards:

   * container health (docker ps, restart counts)
   * Postgres replication lag (later)
   * API 4xx/5xx counts per tenant (abuse detection / throttling).

---

## 8. Executive summary for handoff

* We are running a functional two-VM architecture:

  * VM-DB = stateful (Postgres x3 + Redis)
  * VM-Web = stateless (API, web apps, nginx)
* We have role-based DB access:

  * `control_app_rw`, `data_app_rw`, `logs_app_rw`
* We have a working Express API container (`api-service`) that can talk to:

  * control-db (for tenant/control logic)
  * Redis (for future rate-limiting / caching)
  * and is reachable externally via nginx or direct port (4000:4000 for dev)
* We have nginx-based virtual hosts that match the product story:

  * `www.nclcdbaas.com` → marketing/docs
  * `app.nclcdbaas.com` → tenant portal
  * `api.nclcdbaas.com` → public API
  * `admin.nclcdbaas.com` → internal admin console

Next steps for DevOps:

1. Add TLS and formalize DNS → nginx.
2. Externalize secrets into env files / secret store.
3. Set up backup & snapshot for Postgres volumes.
4. Plan horizontal split of VM-Web into separate API and Frontend nodes when load grows.
5. Plan replication strategy for VM-DB (HA / failover / performance).
6. Add logging/metrics for api-service and start writing audit trails into logs-db.

Once those are in place, the platform becomes production-capable and we can focus on features: tenant onboarding, token issuance, row-level CRUD on tenant data, quotas, billing.

You’re in a very strong position.
