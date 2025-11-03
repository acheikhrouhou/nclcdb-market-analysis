We're going to freeze the current state in a handover document a developer can literally read on day 1 and understand “what exists, how it works, and where to start coding.”

I’ll write it like an internal engineering README / onboarding doc.

---

# NC LCDBaaS — Platform Bootstrap Overview

Environment Status / Developer Onboarding
Date: 2025-11-03

## 1. High-level Concept

This platform is the foundation of a Low-Code / No-Code Database-as-a-Service (LC/NC DBaaS).
Goal: allow a non-technical customer (a “tenant”) to create databases, define tables/columns, and access their data securely via API calls, without managing infra.

We are building a multi-tenant SaaS with:

* a Control Plane to manage tenants, billing, quotas, API tokens, etc.
* a Data Plane to store tenant data (their actual tables/records)
* a Log Plane for audit trails and activity logging
* an API layer that exposes CRUD operations on tenant data
* a Portal/Console UI for tenants
* an Admin UI for internal ops
* a Marketing site / Docs site

We already have:

* Two VMs (VM-DB and VM-Web)
* Split containers for DB/storage vs web/API
* Working app-to-DB connectivity across VMs
* A running Node.js API service that hits Postgres and Redis
* A repeatable Docker Compose setup

This doc explains how it is structured and how to build on it.

---

## 2. Physical / Host Layout

We run two Ubuntu 24.04 servers (VMs).
These are currently separate VMs on the same private /24 LAN.

### 2.1 VM-DB

**Role:** stateful services (datastores)

* Runs Postgres for:

  * `control-db` on port 5432
  * `data-db`    on port 5433
  * `logs-db`    on port 5434
* Runs Redis on port 6379 (currently single-instance)
* Docker is installed and used to run these DB containers
* `ufw` firewall allows only VM-Web to connect to those ports

This VM “owns the data.”

### 2.2 VM-Web

**Role:** stateless web/API services

* Runs:

  * `api-service` (Node.js backend API)
  * `www-app`     (public marketing site / docs placeholder)
  * `portal-app`  (tenant portal placeholder)
  * `admin-app`   (internal admin console placeholder)
  * `nginx-proxy` (will front these apps by hostname)
* Docker is installed and used to run those app containers
* The `api-service` talks to VM-DB’s Postgres + Redis using internal service users

This VM “serves traffic.”

We also enabled port mapping (`4000:4000`) for `api-service` so we can curl/test the API directly on VM-Web.

---

## 3. Network / Security Model

### LAN connectivity

* VM-Web can reach VM-DB over the private LAN (`192.168.106.x` in our current setup).
* We confirmed connectivity using `nc -vz VM-DB 5432` etc.

### UFW on VM-DB

* Postgres ports (5432/5433/5434) and Redis (6379) are open only to VM-Web’s LAN IP.
* SSH (22) is allowed for ops.

This means external traffic cannot hit the databases directly. All data access should go through `api-service`.

### Docker networking

* Each VM uses Docker locally.
* VM-Web’s app containers share an internal Docker network called `nclc_internal`.
* `nginx-proxy` reverse-proxies to app containers over that internal network (no public exposure yet except the `api-service` test port).

---

## 4. Directory Layout (on the hosts)

On both VMs we keep everything under:

```bash
/opt/nclcdbaas
```

Inside that directory:

```text
/opt/nclcdbaas
├── build-starter.sh         (bootstrap script we used to generate dirs, compose files, etc.)
├── README.md                (initial infra readme)
├── .env/
│   ├── db.env               (DB/root passwords etc. WAS used at bootstrap, eventually will be secrets)
│   └── web.env              (app secrets; eventually will contain URLs, JWT secret, etc.)
├── db/
│   ├── docker-compose.db.yml
│   └── postgres/
│       ├── control-db/
│       │   ├── initdb.d/    (init SQL for control plane db)
│       │   └── conf.d/
│       ├── data-db/
│       │   ├── initdb.d/    (init SQL for data plane db)
│       │   └── conf.d/
│       └── logs-db/
│           ├── initdb.d/    (init SQL for log plane db)
│           └── conf.d/
├── web/
│   ├── docker-compose.web.yml
│   ├── nginx/
│   │   ├── conf.d/
│   │   │   └── default.conf    (vhost routes for www, app, admin, api)
│   │   ├── certs/              (TLS certs go here eventually)
│   │   └── logs/               (nginx logs)
│   ├── apps/
│   │   ├── www/                (public website / docs app)
│   │   ├── portal/             (tenant portal app)
│   │   ├── admin/              (internal admin console)
│   │   └── api/                (Node.js backend API service)
│   │       ├── Dockerfile
│   │       ├── index.js
│   │       └── package.json
│   └── logs/                   (app logs etc., future)
└── backups/                    (backup target folder - snapshot dumps, etc)
```

### Important: where to put application code

* All backend API logic lives in `/opt/nclcdbaas/web/apps/api`.
* Portal / Admin / WWW frontend code lives in `/opt/nclcdbaas/web/apps/{portal,admin,www}`.
* Nginx config for routing lives in `/opt/nclcdbaas/web/nginx/conf.d/default.conf`.

This structure is meant to scale:

* One repo = one tree (`/opt/nclcdbaas`).
* Each service has its own Dockerfile under `web/apps/...`.
* One `docker-compose.web.yml` builds/launches all web-facing services together.

---

## 5. Docker Compose: DB side vs Web side

We intentionally split Docker Compose into two files.

### 5.1 VM-DB uses: `db/docker-compose.db.yml`

That compose file defines:

* `control-db` (postgres:16)
* `data-db`    (postgres:16)
* `logs-db`    (postgres:16)
* `redis`      (redis:7-alpine)

Each Postgres container:

* Has its own volume (`control-db-data`, etc.) so data persists across container restarts.
* Defines its own `POSTGRES_USER`, `POSTGRES_PASSWORD`, etc., for bootstrap.
* Listens on a unique host port (5432, 5433, 5434) so we can reach the right logical DB from the web VM.

We’ve created least-privilege app roles inside each DB:

* `control_app_rw` on `control` DB

  * Used by the API for reading/writing control plane info (tenants, tokens, etc.)
  * Has limited rights, not superuser.

* `data_app_rw` on `base_shared` DB

  * Will be used by the API to CRUD tenant business data rows.
  * Least-privilege role, not allowed to do DDL (no CREATE DATABASE, no DROP ROLE, etc.).

* `logs_app_rw` on `logs` DB

  * Will be used by the API to write audit and activity logs.
  * Usually only needs INSERT on log tables.

This is very important for security:

* API service never connects as a superuser.
* Each logical area (control plane / data plane / log plane) has its own credentials.

### 5.2 VM-Web uses: `web/docker-compose.web.yml`

That compose file defines:

* `api-service`    → Node.js backend (Express)
* `portal-app`     → tenant-facing UI (placeholder right now)
* `admin-app`      → internal ops UI (placeholder)
* `www-app`        → public marketing/docs site (placeholder)
* `nginx-proxy`    → reverse proxy / future TLS termination

Key points:

* There is an internal Docker network called `nclc_internal` that all these containers share.
* `nginx-proxy` routes:

  * `www.nclcdbaas.com`   → `www-app`
  * `app.nclcdbaas.com`   → `portal-app`
  * `admin.nclcdbaas.com` → `admin-app` (can be IP-restricted later)
  * `api.nclcdbaas.com`   → `api-service:4000`

Currently, we also mapped `api-service` port 4000 directly to the VM host (`"4000:4000"`) for local curl testing. In production, you remove that mapping and only allow traffic via `nginx-proxy`.

---

## 6. The API Service (api-service)

This is the main backend service. This is where product logic will live.

Location on disk:

```bash
/opt/nclcdbaas/web/apps/api
```

### 6.1 Files of interest

**`package.json`**

```json
{
  "name": "nclc-api",
  "version": "1.0.0",
  "type": "module",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "express": "^4.19.2",
    "pg": "^8.12.0",
    "redis": "^4.6.13"
  }
}
```

* `"type": "module"` lets us use `import ... from '...'` in Node 22.
* `express` is our HTTP server.
* `pg` is our Postgres client.
* `redis` is our Redis client (rate limiting, caching, etc. later).

**`index.js`** (current server entry point)

* Connects once to Postgres (control DB) and Redis.
* Boots an Express server.
* Exposes `/healthz` endpoint to confirm DB and Redis are reachable.
* Listens on port 4000.

This is the first “real” runtime service.

### 6.2 How it gets its config / secrets

In `docker-compose.web.yml`, we define environment variables *for that container only*:

```yaml
  api-service:
    environment:
      NODE_ENV: "production"

      CONTROL_DB_URL: "postgres://control_app_rw:<password>@192.168.106.138:5432/control"
      DATA_DB_URL:    "postgres://data_app_rw:<password>@192.168.106.138:5433/base_shared"
      LOG_DB_URL:     "postgres://logs_app_rw:<password>@192.168.106.138:5434/logs"

      REDIS_URL: "redis://192.168.106.138:6379"
      JWT_SECRET: "dev-jwt-secret"

    ports:
      - "4000:4000"   # <-- exposed to host for curl during dev
```

Notes:

* `<password>` are actual working passwords we manually set using SQL inside each Postgres container.
* `CONTROL_DB_URL` is already known good (we tested with real queries).
* `DATA_DB_URL` and `LOG_DB_URL` are defined once we’ve created `data_app_rw` / `logs_app_rw`.
* `JWT_SECRET` will be used later for token signing.

### 6.3 How to rebuild and run the API after you change code

From VM-Web:

```bash
cd /opt/nclcdbaas

# rebuild api-service image and restart that one container
docker compose -f web/docker-compose.web.yml up -d --build api-service

# inspect logs
docker logs -f api-service
```

During development you’ll repeat that after changing code under `web/apps/api`.

---

## 7. nginx-proxy

File: `/opt/nclcdbaas/web/nginx/conf.d/default.conf`

Today it's a simple reverse proxy with different `server_name`s:

* `www.nclcdbaas.com`   → `www-app:3000`
* `app.nclcdbaas.com`   → `portal-app:3001`
* `admin.nclcdbaas.com` → `admin-app:3002` (we can IP-restrict here)
* `api.nclcdbaas.com`   → `api-service:4000`

This is how we'll expose the services eventually using real DNS.

Right now, we haven’t fully wired ports 3000/3001/3002 in the other containers (the placeholder apps are just Node boilerplates). That’s fine — those frontends are stubs. The important one is `api-service` which is already listening on 4000.

Later:

* We’ll add TLS certs under `web/nginx/certs`.
* We’ll publish port 80/443 from `nginx-proxy` on VM-Web to the outside world.

---

## 8. How to connect to Postgres manually for debugging

From VM-Web host (not inside container), you can check the control DB using psql:

```bash
psql "postgres://control_app_rw:<password>@192.168.106.138:5432/control"
```

This is useful to:

* look at tables (e.g. `SELECT * FROM tenants;`)
* test perms from the same role the API uses
* confirm network/security

As we build application features, the control DB will hold:

* `tenants`
* `tenant_databases`
* `api_tokens`
* quotas / billing info

The data DB will hold:

* actual tenant tables and records

The logs DB will hold:

* audit trails: who did what, when, from which token

---

## 9. Development Workflow Cheat Sheet

This is what a dev should do day 1:

1. **SSH into VM-Web**
   You’ll be doing most app development here.

2. **Go to project root**

   ```bash
   cd /opt/nclcdbaas
   ```

3. **Edit backend logic**
   Work in:

   ```bash
   /opt/nclcdbaas/web/apps/api/index.js
   /opt/nclcdbaas/web/apps/api/package.json
   /opt/nclcdbaas/web/apps/api/... (new routes, controllers, etc.)
   ```

4. **Rebuild and restart the API container**

   ```bash
   docker compose -f web/docker-compose.web.yml up -d --build api-service
   docker logs -f api-service
   ```

5. **Test locally from VM-Web**

   ```bash
   curl http://localhost:4000/healthz
   ```

   You should get JSON like:

   ```json
   {
     "status": "ok",
     "db_time": "...",
     "redis": "PONG"
   }
   ```

   If that works, your service is alive and wired into the databases.

6. **(Optional) Stop / Start full stack**

   ```bash
   # start or rebuild everything (www, portal, admin, api, nginx)
   docker compose -f web/docker-compose.web.yml up -d --build

   # see all running containers
   docker compose -f web/docker-compose.web.yml ps
   ```

7. **If you need DB-level admin work**

   * SSH into VM-DB
   * `docker exec -it control-db bash`
   * inside container:

     ```bash
     psql -U control_admin -d control
     ```
   * rotate passwords, create new roles, etc.

---

## 10. What happens next (for devs)

The next development milestones are purely application logic:

1. **Tenant creation endpoint**

   * `POST /v1/tenants`
   * Inserts a row into `control.tenants`
   * Generates a tenant_id

2. **API key issuance**

   * `POST /v1/tenants/:tenantId/api-keys`
   * Creates an API token tied to:

     * that tenant
     * that tenant’s DB
     * allowed operations
     * rate limit quota
   * Stores hash of token in control DB (never store raw token)

3. **Data CRUD endpoint**

   * `POST /v1/data/:tenantDb/:table` (insert row)
   * `GET /v1/data/:tenantDb/:table`  (list rows)
   * Authorization: validate provided token against control DB, check tenant-db mapping, then run queries against data plane (`data_db_url`).
   * Log activity in logs DB (`logs_app_rw` role).

That is literally the product: “a hosted multi-tenant data backend with per-tenant API keys and per-tenant DBs.”

---

## 11. Tips / Gotchas

* **Restart loops**:
  If `api-service` keeps restarting every second, check `docker logs -f api-service`.
  Most common reasons:

  * bad Postgres URL/password
  * UFW blocked DB port
  * `npm install` didn’t run (package.json issue)
  * code threw at startup inside `initConnections()`

* **Changing DB passwords**:
  If you `ALTER ROLE ... WITH PASSWORD 'xxx'` in Postgres, you must also update the corresponding `CONTROL_DB_URL` (etc.) in `web/docker-compose.web.yml`, rebuild, and rerun.

* **Don’t use superuser accounts in the app**:
  Only `*_app_rw` users should be in the app URLs.
  `control_admin`, `data_admin`, `logs_admin` are for maintenance only (psql from VM-DB), not for the runtime API.

* **Never expose DB ports publicly**:
  VM-DB should remain LAN-only to VM-Web. In production you'll also close Redis to anything except VM-Web, and only expose `nginx-proxy` externally (80/443).

* **TLS / domains**:
  Eventually:

  * point DNS of `api.nclcdbaas.com` to VM-Web’s public IP
  * run nginx-proxy on 80/443 with TLS certs in `web/nginx/certs`
  * remove the direct `ports: "4000:4000"` mapping so only nginx can hit the API internally

---

## 12. TL;DR for new devs

* VM-DB = data services (Postgres x3 + Redis).
* VM-Web = app services (Express API, portal, admin, marketing, nginx).
* Code lives in `/opt/nclcdbaas/web/apps/...`.
* The backend you’ll extend is `/opt/nclcdbaas/web/apps/api`.
* You rebuild/restart with:

  ```bash
  docker compose -f web/docker-compose.web.yml up -d --build api-service
  ```
* You test with:

  ```bash
  curl http://localhost:4000/healthz
  ```
* The API already talks to live Postgres+Redis using least-privilege roles.
  This is your base to implement tenants, tokens, quotas, and CRUD.

This environment is now “developer-ready”: you can start shipping product logic, not infrastructure.
