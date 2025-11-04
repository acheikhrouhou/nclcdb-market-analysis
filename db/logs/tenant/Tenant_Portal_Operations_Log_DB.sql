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
