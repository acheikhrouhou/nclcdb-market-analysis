--- This DB records two streams:
--- (a) API access logs at the gateway (cheap fields, high volume)
--- (b) Record events (INSERT/UPDATE/DELETE) from each base, forwarded asynchronously (e.g., via queue)

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
