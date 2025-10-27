/* Here’s a **thorough first draft of the Control Plane database schema** (PostgreSQL), designed for your constraints:

* **Public API only does data-plane CRUD** (not here).
* **Control Plane** handles: tenants, users, plans/billing, usage/quota, **API tokens scoped to a single base (database)**, schema registry, credits wallet, notifications, and rate limits.
* IDs use **UUID v7** (or ULID); all time columns are `timestamptz`.

I’ve grouped tables by domain and included key constraints + suggested indexes. You can paste these blocks into migrations as-is and iterate.
*/ 


--- # Control Plane Schema (PostgreSQL)

--- ## 0) Bootstrap (helper types & extensions)

--- sql
--- Enable UUID generation (or bring your own ULID/UUIDv7 function)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enum-like domains (swap to real enums if you prefer)
CREATE TYPE plan_tier AS ENUM ('free','pro','business','enterprise');
CREATE TYPE member_role AS ENUM ('owner','admin','editor','viewer');
CREATE TYPE token_scope AS ENUM ('read','write','delete');         -- additive scopes
CREATE TYPE sub_status AS ENUM ('trialing','active','past_due','canceled','incomplete');
CREATE TYPE wallet_event AS ENUM ('topup','debit','expire','adjustment','refund');
CREATE TYPE region_code AS ENUM ('eu','us','ap');
--- sql

--- ## 1) Tenancy & Identity

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

--- Many users belong to many tenants (via workspaces/bases below).
--- If you want top-level membership, keep this for tenant-level roles/SSO.
CREATE TABLE tenant_memberships (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id            uuid NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  role               member_role NOT NULL DEFAULT 'viewer',
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id)
);

--- Optional: external IdP identities (Google, OIDC/SAML)
CREATE TABLE user_identities (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider           text NOT NULL,                      -- 'google','github','saml'
  provider_user_id   text NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_user_id),
  UNIQUE (user_id, provider)
);

---
--- ## 2) Logical data perimeter (Bases) & base-level membership

--- > A **base** here maps 1:1 to a **data-plane database**.
--- > Your requirement: **tokens are scoped to a base**, not the whole tenant.

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

--- Membership at base level controls who can access that base in the app
CREATE TABLE base_memberships (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  base_id            uuid NOT NULL REFERENCES bases(id)   ON DELETE CASCADE,
  user_id            uuid NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  role               member_role NOT NULL DEFAULT 'editor',
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (base_id, user_id)
);
CREATE INDEX idx_base_memberships_user ON base_memberships(user_id);

---

--- ## 3) API tokens (scoped to a base)

--- > Each token belongs to **one base**; scopes define allowed CRUD.
--- > Only the Control Plane issues/revokes tokens; data-plane validates hash/claims.

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

---

--- ## 4) Plans, subscriptions, billing, and credits wallet

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

--- Credits wallet: $5 = 2,500 runs (you’ll enforce price elsewhere; this stores balances)
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
---
--- ## 5) Usage & metering (per base, per month)

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

---
--- ## 6) Rate limits & policy flags

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
---

--- ## 7) Schema registry (authoritative definition for each base)
--- > Public API **cannot** change schema; only the Control Plane applies migrations to the data-plane DBs using this registry.

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
---

--- ## 8) Notifications & webhooks (for control-plane events)

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
---

--- ## 9) Access logs (control-plane only; user/data logs live elsewhere)

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
---

--- # Notes on scalability & safety

--- * **Token → Base constraint**: `chk_base_tenant_consistency` prevents cross-tenant mistakes.
--- * **Per-month metering** keeps the usage table bounded and fast to query for ROI/billing.
--- * **Wallet + ledger** gives auditable credit accounting (required for finance).
--- * **Schema registry** is your single source of truth for DDL—public API never touches it.
--- * **Indexes** focus on hot paths (lookups by tenant/base/month; latest versions; token validation).
--- * **Partitioning** (phase 2): when large, partition `usage_counters`, `access_logs`, `alerts`, and `notifications` by month.
--- * **Row-level security** is usually not needed in Control DB (service-only), but you can apply RLS to `access_logs` for limited tenant self-serve views if you ever expose them.
---
--- # Example queries you’ll run often
--- * **Resolve data-plane connection for a token:**

--- sql
SELECT b.id AS base_id, b.region, t.tenant_id, a.scopes
FROM api_tokens a
JOIN bases b ON b.id = a.base_id
WHERE a.token_hash = $1 AND a.revoked_at IS NULL;

--- * **Monthly billable usage per base (to compare with plan + wallet):**
--- sql
SELECT u.base_id, u.month, u.runs_used, u.api_calls, u.records_count, u.storage_gb_used
FROM usage_counters u
WHERE u.tenant_id = $1 AND u.month = date_trunc('month', now())::date;

--- * **Wallet balance for auto-refill decision:**
--- sql
SELECT balance_cents, runs_balance, refill_threshold_cents, expires_at
FROM wallets WHERE tenant_id = $1;

