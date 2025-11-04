Absolutely — here’s a clean, production-ready **PostgreSQL schema** for your four logging databases. It uses sensible enums, high-cardinality indexes, and **monthly partitions** so you can enforce retention cheaply. You can deploy each section into its own database (recommended) or as separate schemas in one instance.

> Conventions used
>
> * `uuid` (via `pgcrypto`), `timestamptz`, and a `occurred_on date` **generated column** for partitioning.
> * **Monthly RANGE partitions**; create the next month’s partition via a cron.
> * BRIN on time for huge tables, BTREE on tenant/action for filters.
> * All JSON payloads are **structured**, not freeform strings.

---

# 0) Common bootstrap (run in each logs DB)

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()

-- helper enum(s) reused across DBs if you want
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sev_level') THEN
    CREATE TYPE sev_level AS ENUM ('info','warn','critical');
  END IF;
END$$;
```

---

# 1) Admin Operations Log DB  (admin portal actions & security)

```sql
-- =========================================================
-- SCHEMA
-- =========================================================
CREATE SCHEMA IF NOT EXISTS admin_log;

-- =========================================================
-- TABLES
-- =========================================================

-- Admin sessions & auth events (logins, MFA, failures)
CREATE TABLE IF NOT EXISTS admin_log.security_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  occurred_on      date GENERATED ALWAYS AS (occurred_at::date) STORED,
  admin_id         uuid,                         -- staff user id (internal directory)
  ip               inet,
  user_agent       text,
  type             text NOT NULL,                -- ADMIN_LOGIN, ADMIN_LOGOUT, MFA_SUCCESS, MFA_FAIL, FAILED_LOGIN, ...
  details          jsonb NOT NULL DEFAULT '{}'::jsonb
) PARTITION BY RANGE (occurred_on);

-- Administrative actions taken in the platform
CREATE TABLE IF NOT EXISTS admin_log.admin_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  occurred_on      date GENERATED ALWAYS AS (occurred_at::date) STORED,
  actor_admin_id   uuid,
  tenant_id        uuid,
  workspace_id     uuid,
  base_id          uuid,
  ip               inet,
  action           text NOT NULL,                -- TENANT_SUSPEND, WALLET_ADJUST, REFUND_CREATE, SCHEMA_APPLY, FEATURE_FLAG_SET, ...
  target_type      text NOT NULL,                -- TENANT, USER, SUBSCRIPTION, BASE, PLAN, INVOICE, ...
  target_id        text,
  severity         sev_level NOT NULL DEFAULT 'info',
  diff             jsonb NOT NULL DEFAULT '{}'::jsonb,  -- before/after or params
  comment          text
) PARTITION BY RANGE (occurred_on);

-- =========================================================
-- INDEXES (attach to each partition automatically)
-- =========================================================
-- Create on the parent; Postgres 15+ propagates to partitions.
CREATE INDEX IF NOT EXISTS admin_log_sec_time_brin ON admin_log.security_events USING BRIN (occurred_on);
CREATE INDEX IF NOT EXISTS admin_log_sec_type_time  ON admin_log.security_events (type, occurred_at DESC);

CREATE INDEX IF NOT EXISTS admin_log_evt_time_brin  ON admin_log.admin_events USING BRIN (occurred_on);
CREATE INDEX IF NOT EXISTS admin_log_evt_tenant_time ON admin_log.admin_events (tenant_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS admin_log_evt_action_time ON admin_log.admin_events (action, occurred_at DESC);
CREATE INDEX IF NOT EXISTS admin_log_evt_sev_time    ON admin_log.admin_events (severity, occurred_at DESC);

-- =========================================================
-- PARTITION CREATION HELPERS
-- =========================================================
-- Create current & next month partitions (call monthly via cron)
CREATE OR REPLACE FUNCTION admin_log.create_month_partition(_table regclass, _yyyymm text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  start_date date := to_date(_yyyymm, 'YYYYMM');
  end_date   date := (start_date + INTERVAL '1 month')::date;
  part_name  text := format('%s_%s', _table::text, _yyyymm);
BEGIN
  EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF %s FOR VALUES FROM (%L) TO (%L);',
                 part_name, _table, start_date, end_date);
END$$;

-- example:
-- SELECT admin_log.create_month_partition('admin_log.admin_events', to_char(now(),'YYYYMM'));
-- SELECT admin_log.create_month_partition('admin_log.security_events', to_char(now(),'YYYYMM'));
```

---

# 2) Tenant Portal Operations Log DB (end-user actions on control plane)

```sql
CREATE SCHEMA IF NOT EXISTS portal_log;

-- Auth & session events for tenant users
CREATE TABLE IF NOT EXISTS portal_log.auth_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  occurred_on      date GENERATED ALWAYS AS (occurred_at::date) STORED,
  tenant_id        uuid,
  user_id          uuid,
  ip               inet,
  user_agent       text,
  type             text NOT NULL,               -- USER_LOGIN, USER_LOGOUT, PASSWORD_RESET, INVITE_ACCEPTED, SSO_ASSERTION, ...
  details          jsonb NOT NULL DEFAULT '{}'::jsonb
) PARTITION BY RANGE (occurred_on);

-- CRUD & settings in the **portal** (NOT data plane):
-- e.g., create workspace/base, invite member, change plan, toggle SSO, generate API token
CREATE TABLE IF NOT EXISTS portal_log.portal_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  occurred_on      date GENERATED ALWAYS AS (occurred_at::date) STORED,
  tenant_id        uuid NOT NULL,
  user_id          uuid,
  workspace_id     uuid,
  base_id          uuid,
  route            text,                         -- /billing/upgrade, /tokens/create, ...
  action           text NOT NULL,                -- WORKSPACE_CREATE, BASE_CREATE, MEMBER_INVITE, TOKEN_ISSUE, PLAN_CHANGE...
  result           text NOT NULL DEFAULT 'ok',   -- ok|error
  context          jsonb NOT NULL DEFAULT '{}'::jsonb
) PARTITION BY RANGE (occurred_on);

-- API token issuance/rotation (duplicated here for quick forensics)
CREATE TABLE IF NOT EXISTS portal_log.token_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  occurred_on      date GENERATED ALWAYS AS (occurred_at::date) STORED,
  tenant_id        uuid NOT NULL,
  user_id          uuid,
  base_id          uuid NOT NULL,
  token_id         uuid,                         -- control-plane token id (for correlation)
  action           text NOT NULL,                -- ISSUE, REVOKE, ROTATE
  reason           text,
  context          jsonb NOT NULL DEFAULT '{}'::jsonb
) PARTITION BY RANGE (occurred_on);

-- Indexes
CREATE INDEX IF NOT EXISTS portal_auth_time_brin    ON portal_log.auth_events USING BRIN (occurred_on);
CREATE INDEX IF NOT EXISTS portal_auth_tenant_time  ON portal_log.auth_events (tenant_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS portal_evt_time_brin     ON portal_log.portal_events USING BRIN (occurred_on);
CREATE INDEX IF NOT EXISTS portal_evt_tenant_time   ON portal_log.portal_events (tenant_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS portal_evt_action_time   ON portal_log.portal_events (action, occurred_at DESC);

CREATE INDEX IF NOT EXISTS portal_tok_time_brin     ON portal_log.token_events USING BRIN (occurred_on);
CREATE INDEX IF NOT EXISTS portal_tok_tenant_time   ON portal_log.token_events (tenant_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS portal_tok_base_time     ON portal_log.token_events (base_id, occurred_at DESC);

-- Partition helper (reuse the same function pattern; optional to share via a util schema)
```

---

# 3) Data-Plane Activity Log DB (record-level CRUD + API gateway access)

> This DB records **two streams**:
> (a) **API access logs** at the gateway (cheap fields, high volume)
> (b) **Record events** (INSERT/UPDATE/DELETE) from each base, forwarded asynchronously (e.g., via queue)

```sql
CREATE SCHEMA IF NOT EXISTS data_activity;

-- API Gateway access logs (high volume; sampleable)
CREATE TABLE IF NOT EXISTS data_activity.api_access_logs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  occurred_on      date GENERATED ALWAYS AS (occurred_at::date) STORED,
  tenant_id        uuid NOT NULL,
  base_id          uuid NOT NULL,
  token_id         uuid,                         -- control-plane token id
  route            text NOT NULL,                -- /v1/records, /v1/records/{id}
  method           text NOT NULL,                -- GET, POST, PATCH, DELETE
  status           int NOT NULL,
  latency_ms       int,
  bytes_in         int,
  bytes_out        int,
  ip               inet,
  user_agent       text,
  source           text NOT NULL DEFAULT 'api'    -- api|ui|automation (if known)
) PARTITION BY RANGE (occurred_on);

-- Record-level CRUD events (normalized across all bases)
CREATE TABLE IF NOT EXISTS data_activity.record_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  occurred_on      date GENERATED ALWAYS AS (occurred_at::date) STORED,
  tenant_id        uuid NOT NULL,
  base_id          uuid NOT NULL,
  table_id         uuid NOT NULL,                -- runtime_meta.tables.id
  record_id        uuid,
  action           text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  actor_user_id    uuid,
  token_id         uuid,
  source           text NOT NULL DEFAULT 'api',  -- api|ui|automation|import
  diff             jsonb,                        -- optional {before, after} or changed keys
  error            text                          -- if a write failed but we logged the attempt
) PARTITION BY RANGE (occurred_on);

-- Indexes
CREATE INDEX IF NOT EXISTS daa_api_time_brin       ON data_activity.api_access_logs USING BRIN (occurred_on);
CREATE INDEX IF NOT EXISTS daa_api_tenant_time     ON data_activity.api_access_logs (tenant_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS daa_api_base_time       ON data_activity.api_access_logs (base_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS daa_api_route_time      ON data_activity.api_access_logs (route, occurred_at DESC);

CREATE INDEX IF NOT EXISTS daa_rec_time_brin       ON data_activity.record_events USING BRIN (occurred_on);
CREATE INDEX IF NOT EXISTS daa_rec_tenant_time     ON data_activity.record_events (tenant_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS daa_rec_base_time       ON data_activity.record_events (base_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS daa_rec_table_time      ON data_activity.record_events (table_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS daa_rec_action_time     ON data_activity.record_events (action, occurred_at DESC);
```

**Notes**

* If volume is extreme, enable **sampling** on `api_access_logs` (e.g., only 1 in N 200-OKs).
* For analytics, ship to a lakehouse as parquet too; keep **90–180 days hot** here.

---

# 4) Alarms & Notifications DB (quotas, wallet alerts, delivery tracking)

```sql
CREATE SCHEMA IF NOT EXISTS notify;

-- Metrics snapshots (feeds detectors)
CREATE TABLE IF NOT EXISTS notify.quota_snapshots (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  captured_at      timestamptz NOT NULL DEFAULT now(),
  captured_on      date GENERATED ALWAYS AS (captured_at::date) STORED,
  tenant_id        uuid NOT NULL,
  base_id          uuid,
  metric           text NOT NULL,                 -- runs_used, storage_gb, records_count, api_calls, wallet_balance_cents
  value_numeric    numeric(20,6),                 -- generic numeric
  value_int        bigint,
  window           text NOT NULL DEFAULT 'monthly' -- minute|hour|day|monthly
) PARTITION BY RANGE (captured_on);

-- Alerts (stateful, de-duplicated)
CREATE TABLE IF NOT EXISTS notify.alerts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_on       date GENERATED ALWAYS AS (created_at::date) STORED,
  tenant_id        uuid NOT NULL,
  base_id          uuid,
  kind             text NOT NULL,                 -- RUNS_THRESHOLD, STORAGE_THRESHOLD, RATE_LIMIT, PAYMENT_FAILED, WALLET_LOW
  severity         sev_level NOT NULL DEFAULT 'info',
  dedupe_key       text NOT NULL,                 -- e.g. runs:80pct:2025-10:base=<id>
  status           text NOT NULL DEFAULT 'open',  -- open|ack|resolved
  first_seen_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at     timestamptz NOT NULL DEFAULT now(),
  context          jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (tenant_id, dedupe_key)                  -- prevents alert storms for same condition
) PARTITION BY RANGE (created_on);

-- Notification attempts (delivery log)
CREATE TABLE IF NOT EXISTS notify.notifications (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id         uuid NOT NULL REFERENCES notify.alerts(id) ON DELETE CASCADE,
  created_at       timestamptz NOT NULL DEFAULT now(),
  channel          text NOT NULL,                 -- email|slack|webhook|inapp
  recipient        text,
  status           text NOT NULL DEFAULT 'queued',-- queued|sent|failed|skipped
  send_attempts    int  NOT NULL DEFAULT 0,
  last_attempt_at  timestamptz,
  error            text
);

-- Indexes
CREATE INDEX IF NOT EXISTS not_qs_time_brin        ON notify.quota_snapshots USING BRIN (captured_on);
CREATE INDEX IF NOT EXISTS not_qs_tenant_time      ON notify.quota_snapshots (tenant_id, captured_at DESC);
CREATE INDEX IF NOT EXISTS not_qs_base_time        ON notify.quota_snapshots (base_id, captured_at DESC);

CREATE INDEX IF NOT EXISTS not_alert_time_brin     ON notify.alerts USING BRIN (created_on);
CREATE INDEX IF NOT EXISTS not_alert_status_time   ON notify.alerts (status, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS not_alert_tenant_status ON notify.alerts (tenant_id, status);

CREATE INDEX IF NOT EXISTS not_note_alert_time     ON notify.notifications (alert_id, created_at DESC);
```

---

## Ops notes & good practices

* **Retention:** keep 90–180 days hot partitions; drop older partitions on schedule, or move to cheaper storage.
* **PII:** avoid storing sensitive payloads in logs. Redact tokens and emails where possible.
* **Throughput:** write logs asynchronously via a queue; use batch inserts for access logs.
* **Sharding:** if a single logs DB grows too large, shard by **region** or **tenant hash modulo N**; the monthly partitioning still applies inside each shard.
* **Access:** give **read-only roles** to support; admin logs (`admin_log.*`) should be restricted and every read should itself be auditable if needed.

If you want, I can include a tiny **cron SQL** (or bash) to pre-create next month’s partitions for all four databases, and a one-liner retention job to **drop partitions older than N months**.
