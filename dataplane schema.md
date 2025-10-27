<p align="right"> Now can you build the data base schema (data and meta data) of the data plane. this data will be hosted in a postgresql docker container instance. </p>


Awesome — going with **Option 2 (Hybrid)** means each tenant **base** carries a **minimal runtime metadata cache** alongside its data, while the **control plane remains the source of truth** and pushes migrations. Below is a tight, implementation-ready **spec update** for the **data plane** (no SQL dump — just precise structures, invariants, and flows).

---

# Data Plane (per Base) — Updated Structure

Each **Base** has **two schemas** inside its Postgres DB (or inside its per-base schema if you’re consolidating):

1. **`runtime_meta`** — small, read-optimized cache of descriptors needed to render/query locally
2. **`data`** — actual user tables, join tables, (optional) history

> All secrets (OAuth, webhooks secrets, Stripe refs) remain in the **control plane**.

---

## 1) `runtime_meta` (local cache)

Goal: be *just enough* to drive the UI, API filtering/sorting, and relations without calling the control plane on every request.

### 1.1 Registry & versioning

* **`base_registry`**

  * `base_id` (uuid) — stable id for this base
  * `meta_version` (int) — monotonically increasing, **must match control plane** version after successful sync
  * `spec_hash` (text) — checksum of the canonical spec
  * `applied_at` (timestamptz) — when this version became active locally
  * `control_checkpoint` (json) — optional: control-plane build id, migration batch id, registry LSN
  * **Invariant:** all reads use only the **latest committed** version

### 1.2 Tables catalog

* **`tables`**

  * `id` (uuid), `system_name` (text, stable), `display_name` (text), `status` (`active|archived|deleted`)
  * `created_at`, `updated_at`
  * **Note:** `system_name` maps to physical `data.t_<table_id>`; renames never change physical name.

* **`fields`**

  * `id` (uuid), `table_id` (uuid FK → `tables.id`)
  * `name` (text, stable column id), `display_name`, `kind` (`text|number|integer|boolean|date|datetime|select|multiselect|json|attachment|relation|lookup|rollup|formula`)
  * `is_required` (bool), `is_unique` (bool), `default_value` (text), `options` (json: precision, validation, select options, etc.)
  * `position` (int)

* **`relations`**

  * `id` (uuid), `from_table_id`, `to_table_id`
  * `cardinality` (`1:N|N:1|N:N`)
  * `from_field_id`, `to_field_id` (optional backlink)
  * `options` (json: cascade, constraint names, join table name/id)

* **`indexes`** (optional, for UI hints + DDL application)

  * `id`, `table_id`, `name`, `columns` (text[]), `method` (`btree|gin|gist|hash`), `is_unique` (bool), `predicate` (text)

* **`views`**

  * `id`, `table_id`, `name`, `kind` (`grid|kanban|calendar|gantt|gallery|form`)
  * `definition` (json: filters/sorts/grouping/visible fields)
  * `is_public` (bool), `public_token` (text)

* **`features`** (optional switches)

  * capability flags (e.g., `history_enabled`, `fts_enabled`) for runtime

### 1.3 Migration bookkeeping

* **`migrations_applied`**

  * `id`, `meta_version`, `step` (e.g., “add_column amount”), `started_at`, `finished_at`, `status` (`ok|failed|rolled_back`), `details` (json)
  * Used for support and idempotency checks.

**Access control:**

* Only the **control-plane service account** can **write** `runtime_meta` and run DDL.
* The app/API **reads** `runtime_meta` freely for fast rendering.

---

## 2) `data` (user content)

### 2.1 Physical tables

* One table per logical meta table: **`data.t_<table_uuid>`**

  * Columns: `id uuid PK`, `created_at`, `updated_at`, `created_by`, `updated_by`, then **typed columns** per `runtime_meta.fields`
  * Optional: `ft tsvector` (if full-text enabled)

### 2.2 Relations

* **1:N / N:1:** foreign key on child; enforced by DDL generated from meta
* **N:N:** dedicated join table **`data.jt_<relation_field_uuid>`** with `(from_record_id, to_record_id, position, created_at)`

### 2.3 History (optional, feature-flagged)

* Per table history **`data.h_<table_uuid>`** with snapshots (`action`, `changed_by`, `snapshot jsonb`)
* Inserted by triggers emitted during migration

### 2.4 Attachments

* Data column for attachment references (`uuid[]` or `jsonb`)
* Attachment rows (pointer + metadata) can live in `runtime_meta.attachments` or in a thin `data.files` if you prefer all data in `data`
* Binary lives in object storage (S3/GCS), never in Postgres

---

# Sync & Consistency Model

### Read path (steady state)

1. UI/API reads **`runtime_meta`** for table/field/view/rel descriptors.
2. Queries hit **`data.*`** using **stable physical names** (`t_<uuid>`).
3. Zero trips to control plane in the hot path.

### Write path (schema changes)

1. Admin edits schema in **control plane** (source of truth).
2. Control plane issues a **migration bundle** to the base:

   * DDL (CREATE/ALTER TABLE/INDEX, triggers)
   * New `runtime_meta` rows
   * New `base_registry.meta_version + spec_hash`
3. Migration runs in a **transaction** (or phased for large ops), writes `migrations_applied`, **commits**, then **bumps `meta_version`** in `base_registry`.

### Drift detection

* On open/base-switch, the app compares **`base_registry.meta_version`** with control plane **registry version**:

  * **Match:** proceed.
  * **Mismatch:** read-only banner or quick **pull** to refresh local meta (depending on your policy).

### Failure handling

* If DDL succeeds but meta write fails (or vice versa), migration retries with **idempotent plan** keyed by version/spec hash.
* `migrations_applied` helps detect partials and no-ops.

---

# Isolation & Security (cross-tenant leak prevention)

* **Token → Base scoping:** The public API routes to exactly **one base DB** (or one base schema). Tokens include `{tenant_id, base_id, scopes}`; the router refuses cross-base.
* **Namespacing:** Physical table names embed the **table UUID**; accidental cross-table joins are only possible if routed to the wrong base — which the router forbids.
* **RLS (optional by use case):** If you need per-user row scoping, enable **RLS** on `data.*` tables with request-scoped GUCs. Not required for tenant-level isolation in DB-per-base.
* **Service roles:** Only the migration service account can change `runtime_meta` or run DDL; application role has **no DDL privilege**.
* **Caches/queues:** Keys always include `{tenant_id}:{base_id}`.

---

# Backup & Restore (atomic local recovery)

* **Back up the base DB** (which includes both `runtime_meta` + `data`) using PITR or snapshots.
* On restore:

  1. Bring the base back to a **consistent point** (data + local meta).
  2. Compare **`base_registry.meta_version/spec_hash`** with the control-plane registry.
  3. If behind, **replay forward migrations** from control plane; if ahead (rare), **reconcile** or keep local and mark control plane to catch up (policy decision).
* This gives you the “restore both databases to last stable situation” property you wanted, without cross-instance consistency issues.

---

# Observability (minimal but essential)

* **Per-base gauges:** `runtime_meta.meta_version`, `data.table_count`, `data.row_count` (estimated), `index_bloat%`
* **Migration SLOs:** success rate, duration p95, rollback count
* **Alerting:** mismatch between control version and `base_registry.meta_version` beyond N minutes; failed migrations; schema drift detection

---

# What changes compared to the earlier (“control-only meta”) plan?

* You **add** the small `runtime_meta` schema **locally** with:

  * `base_registry`, `tables`, `fields`, `relations`, `views`, (optional) `indexes`, `migrations_applied`
* You **keep** user data exactly as before in `data.*`
* You **add** a lightweight **version checkpoint** to tie the two together

That’s it — the shape of your **data tables** remains the same; you’ve just reduced latency, improved failure isolation, and simplified atomic restores.

If you want, I can next draft a **migration playbook** (phased DDL patterns, online index creation, backfill strategy, and rollback plans) tailored to this hybrid setup.

