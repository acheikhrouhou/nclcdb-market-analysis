--- Admin Operations Log DB (admin portal actions & security)

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
