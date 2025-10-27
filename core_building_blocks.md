
Got it—you want the **core building blocks** locked before we go deeper. Here’s a clean, scalable database layout that matches your constraints:

* **APIs = data plane CRUD only** (insert/read/update/delete records).
* **No schema or billing via the public API.**
* **Separated databases/containers** for control, user data, logs, and alarms—built to scale from MVP to industrial.

---

# Guiding principles

* **Hard separation of concerns:** control plane ≠ data plane.
* **Least privilege:** data-plane API cannot reach billing or DDL endpoints.
* **Multi-tenant flexibility:** start simple (schema-per-tenant), grow to DB-per-tenant or regional clusters.
* **Append-only logs:** everything auditable, partitioned for scale, cheap to query and archive.
* **Migration-safe IDs:** use **ULIDs** (sortable) or UUIDv7 everywhere.

---

# Database map (each in its own container)

1. **Control DB** (control plane)
2. **Data DB(s)** (data plane; tenants’ data)
3. **Admin Audit DB** (platform/admin actions & security-critical events)
4. **User/Resource Activity DB** (tenant-visible operational logs)
5. **Alarms & Notifications DB** (quota/runs/storage/rate-limit alerts)

> You can colocate (3), (4), (5) in one physical instance at MVP, but **keep separate logical databases/schemas** so you can split them later with minimal change.

---

## 1) Control DB (control plane)

Purpose: tenants, users, authN/Z artifacts, plans/quotas, billing pointers, API tokens.
Engine: **Postgres** (RLS optional here; stricter at application layer).

**Core tables**

* `tenants(id, slug, name, region, status, created_at, updated_at)`

* `workspaces(id, tenant_id, name, status, created_at, …)`

* `users(id, email, name, status, mfa_enabled, created_at, …)`

* `memberships(id, workspace_id, user_id, role, created_at, …)`
  *Index:* (workspace_id, user_id), (user_id)

* `plans(id, code, name, tier, monthly_runs, record_cap, storage_cap_gb, features_json, price_cents)`

* `subscriptions(id, tenant_id, plan_id, seats, period_start, period_end, status, created_at, …)`

* `usage_counters(id, tenant_id, month, runs_used, storage_gb_used, api_calls, records_count, updated_at)`
  *Unique:* (tenant_id, month)

* `wallets(id, tenant_id, balance_cents, expires_at, auto_refill_enabled, refill_threshold_cents, created_at)`

* `wallet_ledger(id, wallet_id, type, amount_cents, runs_delta, ref, created_at)`
  *(type: topup|debit|expire|adjustment; keep both money and run deltas for reconciliation)*

* `api_tokens(id, tenant_id, workspace_id NULLABLE, token_hash, scopes, created_by_user, last_used_at, created_at, revoked_at)`
  *Index:* (tenant_id), (token_hash)

* `schema_registry(id, tenant_id, base_id, version, ddl_hash, spec_json, created_at)`
  *(Authoritative schema spec used by control plane when applying DDL; **not** exposed via public API.)*

* `rate_limits(id, tenant_id, window, api_limit, runs_limit, created_at, …)`

**Notes**

* **Public API only receives** a scoped token → validated here → **authorized** to a specific tenant/workspace/base for **data CRUD** only.
* The **Portal/Control UI** is the only way to modify schema or billing. The backend reads `schema_registry` → executes DDL on the appropriate Data DB.

---

## 2) Data DB(s) (data plane)

Purpose: tenants’ actual tables/records; high-read/write performance; strong isolation.

**Tenancy strategy**

* **MVP:** single cluster; **schema-per-tenant** (`tenant_<id>`), **RLS enabled per table** as extra safety.
* **Scale-up:** heavy tenants → **database-per-tenant**; route via a connection broker.
* **Scale-out:** region-based clusters (EU/US/…); pin `tenant.region` in Control DB.

**Per-tenant metadata (in each tenant schema)**

* `bases(id, name, status, created_at, updated_at)`
* `tables(id, base_id, name, display_name, created_at)`
* `fields(id, table_id, name, type, options_json, is_required, is_unique, created_at)`
* `views(id, table_id, name, kind, definition_json, created_at)`  *(kind: grid, form, kanban, gantt, gallery)*

**Data tables (pattern)**

* For each logical table: physical table e.g., `t_<tableid>` with **typed columns** + a catch-all `extra jsonb` if needed.
* Common audit columns: `id ULID PK, created_by, created_at, updated_at, updated_by`.
* **RLS policies** scoped by `(tenant_id, workspace_id, user_role)` stored in session/claims.

**Indexes**

* Per-table: `(primary key)`, common filters, date fields, and any FK columns.
* For quick filters/sorts at scale, add **covering indexes** on frequent combinations (e.g., `(status, created_at DESC)`).

**Attachments**

* Keep **only pointers**: `files(id, base_id, path, size_bytes, checksum, mime, created_at)`. Actual blobs in S3/GCS with signed URLs.

---

## 3) Admin Audit DB (platform/admin actions)

Purpose: immutable, append-only evidence for **security & compliance**.
Partitioning: **monthly partitions** on `occurred_at`.
Retention: 3+ years (configurable), cold storage after N months.

**Tables**

* `admin_events(id, occurred_at, actor_admin_id, tenant_id NULL, workspace_id NULL, ip, action, target_type, target_id, details_json)`
  *Examples:* `TENANT_SUSPEND`, `WALLET_ADJUST`, `SCHEMA_APPLY`, `REFUND_CREATE`
  *Indexes:* `(occurred_at DESC)`, `(tenant_id, occurred_at DESC)`, `(action, occurred_at DESC)`

* `security_events(id, occurred_at, subject_user_id NULL, ip, type, details_json)`
  *Examples:* `ADMIN_LOGIN`, `FAILED_LOGIN`, `MFA_BYPASS_ATTEMPT`

> Strict access: only super-admin tools read this; all reads are themselves logged.

---

## 4) User/Resource Activity DB (tenant-visible operational logs)

Purpose: show tenants **what happened in their workspace** (non-sensitive).

**Tables**

* `resource_events(id, occurred_at, tenant_id, workspace_id, base_id, actor_user_id NULL, resource_type, resource_id, action, diff_json)`
  *Examples:* `RECORD_CREATE`, `RECORD_UPDATE`, `RECORD_DELETE`, `IMPORT_CSV`, `VIEW_PUBLISH`
  *Partition:* monthly;
  *Indexes:* `(tenant_id, base_id, occurred_at DESC)`, `(resource_type, resource_id)`

* `api_access_logs(id, occurred_at, tenant_id, token_id, route, method, status, latency_ms, bytes, ip)`
  *(Sampling allowed; emit to analytics sink for BI.)*

Retention: 30–180 days hot; archive to object storage after.

---

## 5) Alarms & Notifications DB (quotas & alerts)

Purpose: stateful alerting with dedup, user-delivery tracking.

**Tables**

* `quota_snapshots(id, captured_at, tenant_id, metric, value, window)`
  *(metric: runs_used, storage_gb, records_count, api_calls)*

* `alerts(id, created_at, tenant_id, kind, severity, dedupe_key, status, first_seen_at, last_seen_at, context_json)`
  *(kind: RUNS_THRESHOLD, STORAGE_THRESHOLD, RATE_LIMIT, WALLET_LOW_BALANCE)*
  `status: open|ack|resolved`
  *Unique:* (tenant_id, dedupe_key, status='open') to prevent spam.

* `notifications(id, created_at, alert_id, channel, to, status, send_attempts, last_attempt_at, error)`
  *(channel: email, webhook, slack, inapp)*

**Flow**

* Metering job writes `quota_snapshots`.
* Detector opens/updates `alerts` (idempotent via `dedupe_key`).
* Notifier emits `notifications` and updates status.

---

# API boundaries (enforcement)

* **Public Data API** (only): `/bases/{id}/tables/{id}/records` — **CRUD only**.
  *No* DDL, *no* billing, *no* plan/credit endpoints.
* **Control/Portal API** (private): schema changes, billing, tokens, seats, credits.
* **Admin API**: support tooling; everything logged to Admin Audit DB.

Use **separate service accounts/network paths** so even misconfig won’t let data-plane services touch billing tables.

---

# Scaling path (MVP → industrial)

**MVP**

* Single Postgres cluster with 4 logical DBs (Control, Data, Logs, Alarms) or separate DBs on one instance.
* Data tenancy: **schema-per-tenant** with RLS.
* Monthly partitioning for logs.
* Simple metering cron; wallet debits on automation run batches.

**Growth**

* Move heavy tenants to **database-per-tenant**; route via a connection service (DSN map in Control DB).
* Split **Logs** (Admin/User) into dedicated instances; enable **timeseries partitions** + compression.
* Introduce **read replicas** for the Data DB (analytics & APIs that can read stale ≤1s).
* CDC (logical replication) from Data DB to Search (Typesense/OpenSearch) and analytics lake (S3/GCS).

**Industrial**

* **Regional clusters** (EU/US) with tenant pinning; data residency honored via `tenant.region`.
* **Per-tenant WAL archiving / PITR**; SLO-backed restore tooling.
* Queues/streaming (e.g., **SQS/Kafka/Redpanda**) for automation runs & log pipelines.
* **Rate-limiters** at the edge (per token, tenant) with sliding windows stored in Redis/KeyDB.

---

# Indexing & retention quick defaults

* **Control DB:** B-Tree on fkeys, uniques on (tenant, month) for usage; 24–36 months retention for invoices/ledger.
* **Data DB:** per-table PK; frequent filter indexes; avoid over-indexing at MVP; add **covering indexes** from telemetry.
* **Logs DBs:** monthly partitions; **BRIN** on time for cheap scans + selective B-Tree on (tenant_id, occurred_at DESC).
* **Alarms DB:** B-Tree on (tenant_id, status), (dedupe_key).

---

# Backup & DR

* **Daily full + PITR** for Control & Data; **RPO ≤ 5 min**, **RTO ≤ 30–60 min**.
* **Cross-region** snapshots for disaster scenarios.
* Verify restores weekly; keep a **break-glass** runbook.

---

## Why this fits your rules

* Public API can **only touch records**, because the **schema lives behind the Control Plane** with a registry and migration service.
* Databases are **modular** now and **split-ready** later: you can scale hot paths (Data) independently of governance/billing (Control) and cheap storage (Logs).
* Logs & alarms are **append-only, partitioned**, and auditable—essential for enterprise and clean ROI reporting.

If you want, I can draft:

* a **minimal ERD diagram** (tables/keys/relations), and
* an **OpenAPI snippet** for the public Data CRUD endpoints you’ll ship in v1.
