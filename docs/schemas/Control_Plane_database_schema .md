Here’s a **thorough first draft** of the **Control Plane database schema** that fits your rules:

-   Public API is **data-plane CRUD only** (no billing/DDL exposed).
-   Control Plane manages **tenants, users, plans, billing, usage/metering**, and **DB-perimeter API tokens** (➜ **one token = one base/database**).
-   Designed to start simple and scale to industrial.

I’m using neutral types (Postgres-flavored: uuid, timestamptz, jsonb, int, text, numeric) and calling out **PK/UK/FK**, **indexes**, and **notes** where it helps.

**Control Plane — Logical Model**

**Org hierarchy**

-   **tenant** → **workspace** → **base** *(= database in the data plane)*

**Identity & access**

-   **user**, **membership** (user ↔ workspace, role)
-   **sso_config**, **invitation**

**Plans & billing**

-   **plan**, **plan_feature**, **subscription**, **subscription_item**, **invoice**, **payment_method**
-   **wallet**, **wallet_ledger** (credits for automation runs)

**Access to data plane**

-   **api_token** *(scoped to a single* **base***)*, optional **api_token_ip_allowlist**

**Schema governance (control only)**

-   **base_schema_version**, **schema_migration_job**

**Metering & quotas**

-   **usage_base_daily**, **usage_tenant_monthly**, **api_token_usage_daily**
-   **quota_override**, **rate_limit** (per token and/or tenant)

**Ops & config**

-   **region**, **feature_flag_assignment**

(Platform/admin & alarms are in other DBs, by design.)

**Tables & Fields**

**1) Tenancy & Structure**

**tenant**

-   **id (uuid, pk)**
-   slug (text, unique) — for URLs/emails
-   name (text)
-   status (text enum: active\|suspended\|deleted)
-   default_region_id (uuid, fk→region.id)
-   created_at (timestamptz), updated_at (timestamptz)
-   **IDX:** (slug), (status)

**workspace**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id)
-   name (text)
-   status (text enum: active\|archived)
-   created_at, updated_at
-   **UK:** (tenant_id, name) — prevent dup names within tenant
-   **IDX:** (tenant_id, status)

**base (= one logical database in the data plane)**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id)
-   workspace_id (uuid, fk→workspace.id)
-   name (text)
-   status (text enum: active\|locked\|deleted)
-   region_id (uuid, fk→region.id)
-   data_plane_ref (text) — router key or DSN alias (no raw creds)
-   created_at, updated_at
-   **UK:** (workspace_id, name)
-   **IDX:** (tenant_id, region_id, status)

**Note:** In DB-per-tenant mode, data_plane_ref can be a logical reference to a connection broker; in schema-per-tenant mode, it’s a shard key.

**2) Users, Memberships, SSO**

**user**

-   **id (uuid, pk)**
-   email (citext, unique)
-   name (text)
-   status (text enum: active\|invited\|disabled)
-   mfa_enabled (boolean, default false)
-   last_login_at (timestamptz)
-   created_at, updated_at
-   **IDX:** (status), (last_login_at)

**membership (user’s role in a workspace)**

-   **id (uuid, pk)**
-   user_id (uuid, fk→user.id)
-   workspace_id (uuid, fk→workspace.id)
-   role (text enum: owner\|admin\|editor\|viewer)
-   created_at, updated_at
-   **UK:** (user_id, workspace_id)
-   **IDX:** (workspace_id, role), (user_id)

**invitation**

-   **id (uuid, pk)**
-   workspace_id (uuid, fk→workspace.id)
-   email (citext)
-   role (text enum: as above)
-   invited_by_user_id (uuid, fk→user.id)
-   token_hash (text, unique)
-   expires_at (timestamptz)
-   accepted_at (timestamptz null)
-   created_at
-   **IDX:** (workspace_id, email)

**sso_config (Business+)**

(Per tenant; SAML/OIDC metadata)

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id, unique)
-   provider (text enum: saml\|oidc)
-   metadata_json (jsonb)
-   sso_enforced (bool, default false)
-   created_at, updated_at

**3) Plans, Billing & Credits**

**plan**

-   **id (uuid, pk)**
-   code (text, unique) — free\|pro\|business\|enterprise
-   name (text)
-   price_cents (int) — per editor / mo (annualized logic in app)
-   monthly_included_runs (int)
-   record_cap (int) — per base
-   storage_cap_gb (int)
-   features_json (jsonb) — toggles
-   created_at, updated_at

**plan_feature**

-   **id (uuid, pk)**
-   plan_id (uuid, fk→plan.id)
-   key (text) — e.g., sso, row_level_security, private_templates
-   value (jsonb)
-   **UK:** (plan_id, key)

**subscription**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id)
-   plan_id (uuid, fk→plan.id)
-   status (text enum: trialing\|active\|past_due\|canceled)
-   seats (int)
-   period_start (timestamptz), period_end (timestamptz)
-   external_ref (text) — Stripe subscription id
-   created_at, updated_at
-   **IDX:** (tenant_id, status), (period_end)

**subscription_item (seat counts / add-ons)**

-   **id (uuid, pk)**
-   subscription_id (uuid, fk→subscription.id)
-   item_type (text enum: seat\|premium_connectors\|extra_storage)
-   quantity (int)
-   price_cents (int)
-   **IDX:** (subscription_id, item_type)

**invoice**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id)
-   external_ref (text, unique) — Stripe invoice id
-   amount_due_cents (int)
-   amount_paid_cents (int)
-   status (text enum: draft\|open\|paid\|void\|uncollectible)
-   issued_at (timestamptz), due_at (timestamptz), paid_at (timestamptz null)
-   created_at
-   **IDX:** (tenant_id, issued_at DESC), (status)

**payment_method**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id)
-   provider (text enum: stripe)
-   external_ref (text) — PM id in Stripe (no PAN here)
-   brand (text), last4 (text)
-   is_default (bool)
-   created_at, updated_at
-   **UK:** (tenant_id, external_ref)

**wallet (Automation credits wallet)**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id, unique)
-   balance_cents (int) — \$ balance for credits
-   balance_runs (int) — pre-purchased runs remaining
-   auto_refill_enabled (bool, default true)
-   refill_threshold_cents (int, default 100) — \$1
-   expires_at (timestamptz) — **12-month rolling**
-   created_at, updated_at

**wallet_ledger**

-   **id (uuid, pk)**
-   wallet_id (uuid, fk→wallet.id)
-   entry_type (text enum: topup\|debit\|expire\|adjust)
-   amount_cents (int) — positive for topups
-   runs_delta (int) — positive for credit purchase, negative for usage
-   ref (text) — external payment ref / usage batch id
-   created_at
-   **IDX:** (wallet_id, created_at DESC)

**Pricing alignment:** \$5 = 2,500 runs. App logic updates both amount_cents and runs_delta atomically.

**4) API Access (Per-Database Tokens)**

**api_token**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id)
-   **base_id (uuid, fk→base.id)** — **required** ➜ **token is scoped to exactly one base**
-   label (text) — user-friendly name
-   token_hash (text, unique) — store only a hash
-   scopes (text[] enum: records:read, records:write, records:delete)
-   status (text enum: active\|revoked)
-   last_used_at (timestamptz)
-   last_used_ip (inet)
-   created_by_user_id (uuid, fk→user.id)
-   created_at, revoked_at
-   **IDX:** (tenant_id, base_id, status), (last_used_at DESC)

**api_token_ip_allowlist (optional)**

-   **id (uuid, pk)**
-   api_token_id (uuid, fk→api_token.id, on delete cascade)
-   cidr (cidr)
-   **UK:** (api_token_id, cidr)

**Notes**

-   A tenant can issue **several tokens**, each **locked to one base**.
-   Scopes are **CRUD-only** for records. No billing or DDL scopes exist.

**5) Schema Governance (Control-side, not public)**

**base_schema_version**

-   **id (uuid, pk)**
-   base_id (uuid, fk→base.id)
-   version (int) — monotonic
-   ddl_hash (text) — checksum of applied DDL/spec
-   spec_json (jsonb) — canonical schema spec (tables/fields)
-   created_by_user_id (uuid, fk→user.id)
-   created_at
-   **UK:** (base_id, version)
-   **IDX:** (base_id, created_at DESC)

**schema_migration_job**

-   **id (uuid, pk)**
-   base_id (uuid, fk→base.id)
-   from_version (int), to_version (int)
-   status (text enum: queued\|running\|succeeded\|failed\|rolled_back)
-   requested_by_user_id (uuid, fk→user.id)
-   started_at, finished_at
-   error (text)
-   **IDX:** (base_id, status)

Public API never hits these. Only the Portal/Admin services use them.

**6) Metering, Quotas & Rate Limits**

**usage_base_daily**

-   **id (uuid, pk)**
-   date (date)
-   tenant_id (uuid, fk→tenant.id)
-   base_id (uuid, fk→base.id)
-   records_count (int) — snapshot EOD
-   storage_gb (numeric(10,3)) — attachments/storage usage
-   runs_used (int) — automation runs consumed that day
-   api_calls (int) — API requests via api_token
-   updated_at (timestamptz)
-   **UK:** (date, base_id)
-   **IDX:** (tenant_id, date), (base_id, date)

**usage_tenant_monthly**

-   **id (uuid, pk)**
-   month (date) — first day of month
-   tenant_id (uuid, fk→tenant.id)
-   runs_used (int)
-   api_calls (int)
-   records_count_max (int) — max across bases in month
-   storage_gb_max (numeric(10,3))
-   updated_at
-   **UK:** (month, tenant_id)
-   **IDX:** (tenant_id, month)

**api_token_usage_daily**

-   **id (uuid, pk)**
-   date (date)
-   api_token_id (uuid, fk→api_token.id)
-   calls (int)
-   bytes_in (bigint), bytes_out (bigint)
-   p95_latency_ms (int)
-   **UK:** (date, api_token_id)

**quota_override**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id)
-   scope (text enum: runs\|storage\|records\|api_calls)
-   target (text enum: tenant\|base)
-   base_id (uuid, fk→base.id, nullable unless target=base)
-   value (int or numeric) — store as jsonb { "int": 50000 } if mixed types
-   valid_from (timestamptz), valid_to (timestamptz null)
-   reason (text)
-   created_by_admin_id (uuid) *(from Admin DB identity if separate)*
-   **IDX:** (tenant_id, base_id, scope)

**rate_limit**

-   **id (uuid, pk)**
-   api_token_id (uuid, fk→api_token.id) *(or tenant_id for tenant-level caps)*
-   window (text enum: 1s\|10s\|1m\|1h\|1d)
-   max_requests (int)
-   created_at, updated_at
-   **UK:** (api_token_id, window)

**7) Regions & Feature Flags**

**region**

-   **id (uuid, pk)**
-   code (text, unique) — eu-west-1, us-east-1, etc.
-   name (text)
-   created_at

**feature_flag_assignment**

-   **id (uuid, pk)**
-   tenant_id (uuid, fk→tenant.id)
-   key (text) — new_automation_ui, beta_connectors
-   value (jsonb) — { "enabled": true }
-   valid_to (timestamptz null)
-   created_at
-   **UK:** (tenant_id, key)

**Relationships (quick view)**

-   tenant 1—N workspace
-   workspace 1—N base
-   user N—N workspace via membership
-   base 1—N api_token (**perimeter = base**)
-   tenant 1—1 wallet, 1—N wallet_ledger
-   tenant 1—N subscription 1—N subscription_item
-   tenant 1—N invoice, 1—N payment_method
-   base 1—N base_schema_version, 1—N schema_migration_job
-   Usage tables roll up **per base/day** and **per tenant/month**.

**Indexing & Partitioning (starter guidance)**

-   **Hot paths**
    -   api_token(token_hash) — **unique** & fast lookup at auth time.
    -   api_token(tenant_id, base_id, status) — listing tokens for a base.
    -   usage_\* tables — **partition by date** (monthly partitions) if you cross millions of rows.
-   **Foreign key fan-outs**
    -   membership(workspace_id), membership(user_id)
    -   base(workspace_id), base(tenant_id)  
        Add B-trees; keep FKs “ON” (consistency \> micro-perf at control plane scale).
-   **Cardinality**
    -   quota_override(tenant_id, base_id) typically tiny — still index for admin queries.

**Security & Data Hygiene**

-   **Token storage:** store only token_hash (e.g., SHA-256 + salt). Show plaintext once on create.
-   **PII:** user.email is PII. If you later add phone/address, separate user_profile with encryption at rest (pgcrypto/KMS).
-   **Multi-region:** base.region_id governs data-plane residency; enforce via provisioning service.
-   **Soft deletes:** Use status enums and keep historical rows for auditability; do hard deletes only on strict request.

**How tokens map to your rule (“one token = one DB”)**

-   api_token.base_id is **NOT NULL** and **FK → base.id**.
-   No tenant-scoped tokens exist; every token is **base-scoped**.
-   Token’s scopes allow only **record CRUD** (records:read\|write\|delete).
-   DDL/billing endpoints **do not exist** on this token plane.

**What you can build next with this**

-   **OpenAPI for Control Plane** (internal): endpoints for issuing/revoking tokens, managing wallets/subscriptions, listing usage.
-   **Provisioner** that reads base.region_id + data_plane_ref to create/attach the actual DB.
-   **Metering workers** that write usage_base_daily and usage_tenant_monthly, and debit wallet_ledger in atomic batches.

If you want, I can turn this into:

-   a **SQL DDL starter pack** (Postgres) with types, enums, FKs, and indices

==========================================================
<p align="right"> OK. Now can you build the first draft of the control plane Database schema? </p>

Here’s a **thorough first draft of the Control Plane database schema** (PostgreSQL), designed for your constraints:

* **Public API only does data-plane CRUD** (not here).
* **Control Plane** handles: tenants, users, plans/billing, usage/quota, **API tokens scoped to a single base (database)**, schema registry, credits wallet, notifications, and rate limits.
* IDs use **UUID v7** (or ULID); all time columns are `timestamptz`.

I’ve grouped tables by domain and included key constraints + suggested indexes. You can paste these blocks into migrations as-is and iterate.

---

# Control Plane Schema (PostgreSQL)

## 0) Bootstrap (helper types & extensions)

```sql
-- Enable UUID generation (or bring your own ULID/UUIDv7 function)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enum-like domains (swap to real enums if you prefer)
CREATE TYPE plan_tier AS ENUM ('free','pro','business','enterprise');
CREATE TYPE member_role AS ENUM ('owner','admin','editor','viewer');
CREATE TYPE token_scope AS ENUM ('read','write','delete');         -- additive scopes
CREATE TYPE sub_status AS ENUM ('trialing','active','past_due','canceled','incomplete');
CREATE TYPE wallet_event AS ENUM ('topup','debit','expire','adjustment','refund');
CREATE TYPE region_code AS ENUM ('eu','us','ap');
```

---

## 1) Tenancy & Identity

```sql
CREATE TABLE tenants (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug               citext UNIQUE NOT NULL,           -- e.g., "acme"
  name               text NOT NULL,
  region             region_code NOT NULL DEFAULT 'eu',
  status             text NOT NULL DEFAULT 'active',   -- active|suspended|deleted
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email              citext UNIQUE NOT NULL,
  name               text,
  mfa_enabled        boolean NOT NULL DEFAULT false,
  status             text NOT NULL DEFAULT 'active',   -- active|disabled|deleted
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- Many users belong to many tenants (via workspaces/bases below).
-- If you want top-level membership, keep this for tenant-level roles/SSO.
CREATE TABLE tenant_memberships (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id            uuid NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  role               member_role NOT NULL DEFAULT 'viewer',
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id)
);

-- Optional: external IdP identities (Google, OIDC/SAML)
CREATE TABLE user_identities (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider           text NOT NULL,                      -- 'google','github','saml'
  provider_user_id   text NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_user_id),
  UNIQUE (user_id, provider)
);
```

---

## 2) Logical data perimeter (Bases) & base-level membership

> A **base** here maps 1:1 to a **data-plane database**.
> Your requirement: **tokens are scoped to a base**, not the whole tenant.

```sql
CREATE TABLE bases (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name               text NOT NULL,
  description        text,
  region             region_code NOT NULL,              -- must match/pin to data-plane region
  status             text NOT NULL DEFAULT 'active',    -- active|archived|deleted
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_bases_tenant ON bases(tenant_id);

-- Membership at base level controls who can access that base in the app
CREATE TABLE base_memberships (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  base_id            uuid NOT NULL REFERENCES bases(id)   ON DELETE CASCADE,
  user_id            uuid NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  role               member_role NOT NULL DEFAULT 'editor',
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (base_id, user_id)
);
CREATE INDEX idx_base_memberships_user ON base_memberships(user_id);
```

---

## 3) API tokens (scoped to a base)

> Each token belongs to **one base**; scopes define allowed CRUD.
> Only the Control Plane issues/revokes tokens; data-plane validates hash/claims.

```sql
CREATE TABLE api_tokens (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  base_id            uuid NOT NULL REFERENCES bases(id)   ON DELETE CASCADE,
  name               text NOT NULL,                       -- label shown to user
  token_hash         text NOT NULL,                       -- store hash only (bcrypt/argon2)
  scopes             token_scope[] NOT NULL,              -- e.g. {'read','write'}
  created_by_user    uuid REFERENCES users(id),
  last_used_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  revoked_at         timestamptz,
  CONSTRAINT chk_base_tenant_consistency
    CHECK ((SELECT tenant_id FROM bases WHERE bases.id = base_id) = tenant_id)
);
CREATE UNIQUE INDEX uq_api_token_hash ON api_tokens(token_hash);
CREATE INDEX idx_api_tokens_base ON api_tokens(base_id);
CREATE INDEX idx_api_tokens_last_used ON api_tokens(last_used_at);
```

---

## 4) Plans, subscriptions, billing, and credits wallet

```sql
CREATE TABLE plans (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  code               citext UNIQUE NOT NULL,        -- 'free','pro','business','enterprise'
  tier               plan_tier NOT NULL,
  price_cents        integer NOT NULL,              -- price per editor/month (annualized if needed)
  features_json      jsonb NOT NULL DEFAULT '{}'::jsonb,
  monthly_runs       integer NOT NULL,              -- included automation runs
  record_cap         integer NOT NULL,
  storage_cap_gb     integer NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE subscriptions (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  plan_id            uuid NOT NULL REFERENCES plans(id),
  seats              integer NOT NULL DEFAULT 1,
  status             sub_status NOT NULL DEFAULT 'active',
  period_start       timestamptz NOT NULL,
  period_end         timestamptz NOT NULL,
  external_ref       text,                           -- Stripe sub id
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end > period_start)
);
CREATE UNIQUE INDEX uq_active_sub_per_tenant
ON subscriptions(tenant_id, status)
WHERE status IN ('trialing','active','past_due','incomplete');

CREATE TABLE billing_contacts (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  email              citext NOT NULL,
  company_vat        text,
  address_json       jsonb,
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, email)
);

CREATE TABLE payment_methods (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  provider           text NOT NULL,                  -- 'stripe'
  external_ref       text NOT NULL,                  -- pm_xxx
  brand              text,
  last4              text,
  exp_month          int,
  exp_year           int,
  is_default         boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_pm_tenant ON payment_methods(tenant_id);

-- Credits wallet: $5 = 2,500 runs (you’ll enforce price elsewhere; this stores balances)
CREATE TABLE wallets (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL UNIQUE REFERENCES tenants(id) ON DELETE CASCADE,
  balance_cents      integer NOT NULL DEFAULT 0,     -- money equivalent (optional)
  runs_balance       integer NOT NULL DEFAULT 0,     -- remaining runs from credits
  auto_refill_enabled boolean NOT NULL DEFAULT true,
  refill_threshold_cents integer NOT NULL DEFAULT 100, -- $1 trigger
  expires_at         timestamptz,                    -- rolling 12 months if you choose
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE wallet_ledger (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  wallet_id          uuid NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
  event_type         wallet_event NOT NULL,
  amount_cents       integer NOT NULL DEFAULT 0,     -- money delta
  runs_delta         integer NOT NULL DEFAULT 0,     -- runs delta (+topup, -debit)
  ref                text,                           -- invoice id, run batch id, etc.
  occurred_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_wallet_ledger_wallet_time ON wallet_ledger(wallet_id, occurred_at DESC);
```

---

## 5) Usage & metering (per base, per month)

```sql
CREATE TABLE usage_counters (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  base_id            uuid NOT NULL REFERENCES bases(id)   ON DELETE CASCADE,
  month              date NOT NULL,                        -- e.g., 2025-10-01
  runs_used          integer NOT NULL DEFAULT 0,           -- automations
  api_calls          integer NOT NULL DEFAULT 0,
  records_count      bigint  NOT NULL DEFAULT 0,           -- snapshot or rolling
  storage_gb_used    numeric(10,2) NOT NULL DEFAULT 0,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (base_id, month),
  CONSTRAINT chk_usage_tenant_match
    CHECK ((SELECT tenant_id FROM bases WHERE bases.id = base_id) = tenant_id)
);
CREATE INDEX idx_usage_tenant_month ON usage_counters(tenant_id, month);
CREATE INDEX idx_usage_base_month ON usage_counters(base_id, month);
```

---

## 6) Rate limits & policy flags

```sql
CREATE TABLE rate_limits (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  base_id            uuid NOT NULL REFERENCES bases(id)   ON DELETE CASCADE,
  token_id           uuid REFERENCES api_tokens(id) ON DELETE SET NULL, -- optional per-token override
  window_seconds     integer NOT NULL DEFAULT 60,
  max_api_calls      integer NOT NULL DEFAULT 600,      -- per window
  max_runs           integer NOT NULL DEFAULT 1000,     -- per window (optional)
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (base_id, token_id, window_seconds)
);
```

---

## 7) Schema registry (authoritative definition for each base)

> Public API **cannot** change schema; only the Control Plane applies migrations to the data-plane DBs using this registry.

```sql
CREATE TABLE schema_registry (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  base_id            uuid NOT NULL REFERENCES bases(id)   ON DELETE CASCADE,
  version            integer NOT NULL,                    -- monotonically increasing
  ddl_hash           text NOT NULL,                       -- integrity
  spec_json          jsonb NOT NULL,                      -- canonical model (tables/fields/indexes)
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (base_id, version),
  CONSTRAINT chk_schema_tenant_match
    CHECK ((SELECT tenant_id FROM bases WHERE bases.id = base_id) = tenant_id)
);
CREATE INDEX idx_schema_latest ON schema_registry(base_id, version DESC);
```

---

## 8) Notifications & webhooks (for control-plane events)

```sql
CREATE TABLE notification_settings (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL UNIQUE REFERENCES tenants(id) ON DELETE CASCADE,
  email_enabled      boolean NOT NULL DEFAULT true,
  slack_webhook_url  text,
  webhook_url        text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE alerts (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  base_id            uuid REFERENCES bases(id) ON DELETE CASCADE,
  kind               text NOT NULL,                       -- RUNS_THRESHOLD, STORAGE_THRESHOLD, PAYMENT_FAILED, WALLET_LOW
  severity           text NOT NULL DEFAULT 'info',        -- info|warn|critical
  dedupe_key         text NOT NULL,                       -- e.g. 'runs:80%-2025-10'
  status             text NOT NULL DEFAULT 'open',        -- open|ack|resolved
  first_seen_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at       timestamptz NOT NULL DEFAULT now(),
  context_json       jsonb NOT NULL DEFAULT '{}',
  UNIQUE (tenant_id, dedupe_key)                          -- dedupe same alert
);
CREATE INDEX idx_alerts_status ON alerts(status);
CREATE INDEX idx_alerts_tenant_status ON alerts(tenant_id, status);

CREATE TABLE notifications (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  alert_id           uuid NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
  channel            text NOT NULL,                       -- email|slack|webhook|inapp
  recipient          text,
  status             text NOT NULL DEFAULT 'queued',      -- queued|sent|failed
  send_attempts      integer NOT NULL DEFAULT 0,
  last_attempt_at    timestamptz,
  error              text,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_alert ON notifications(alert_id);
```

---

## 9) Access logs (control-plane only; user/data logs live elsewhere)

```sql
CREATE TABLE access_logs (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid REFERENCES tenants(id) ON DELETE SET NULL,
  user_id            uuid REFERENCES users(id)   ON DELETE SET NULL,
  route              text NOT NULL,                         -- e.g., POST /v1/api-tokens
  ip                 inet,
  user_agent         text,
  status_code        int,
  latency_ms         int,
  occurred_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_access_logs_tenant_time ON access_logs(tenant_id, occurred_at DESC);
CREATE INDEX idx_access_logs_user_time   ON access_logs(user_id, occurred_at DESC);
```

---

# Notes on scalability & safety

* **Token → Base constraint**: `chk_base_tenant_consistency` prevents cross-tenant mistakes.
* **Per-month metering** keeps the usage table bounded and fast to query for ROI/billing.
* **Wallet + ledger** gives auditable credit accounting (required for finance).
* **Schema registry** is your single source of truth for DDL—public API never touches it.
* **Indexes** focus on hot paths (lookups by tenant/base/month; latest versions; token validation).
* **Partitioning** (phase 2): when large, partition `usage_counters`, `access_logs`, `alerts`, and `notifications` by month.
* **Row-level security** is usually not needed in Control DB (service-only), but you can apply RLS to `access_logs` for limited tenant self-serve views if you ever expose them.

---

# Example queries you’ll run often

* **Resolve data-plane connection for a token:**

```sql
SELECT b.id AS base_id, b.region, t.tenant_id, a.scopes
FROM api_tokens a
JOIN bases b ON b.id = a.base_id
WHERE a.token_hash = $1 AND a.revoked_at IS NULL;
```

* **Monthly billable usage per base (to compare with plan + wallet):**

```sql
SELECT u.base_id, u.month, u.runs_used, u.api_calls, u.records_count, u.storage_gb_used
FROM usage_counters u
WHERE u.tenant_id = $1 AND u.month = date_trunc('month', now())::date;
```

* **Wallet balance for auto-refill decision:**

```sql
SELECT balance_cents, runs_balance, refill_threshold_cents, expires_at
FROM wallets WHERE tenant_id = $1;
```

---

