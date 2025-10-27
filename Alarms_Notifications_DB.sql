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
