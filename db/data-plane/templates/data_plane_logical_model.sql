-- =========================================================
-- 0) Extensions & Schemas
-- =========================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE SCHEMA IF NOT EXISTS runtime_meta;
CREATE SCHEMA IF NOT EXISTS data;

-- =========================================================
-- 1) runtime_meta (Local, read-optimized descriptors)
--    Control plane remains source of truth; this is a cache.
-- =========================================================

-- 1.1 Helper enums
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'field_kind') THEN
    CREATE TYPE runtime_meta.field_kind AS ENUM (
      'text','long_text','number','integer','boolean','date','datetime',
      'select','multiselect','email','url','phone',
      'attachment','relation','lookup','rollup','json','formula'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'view_kind') THEN
    CREATE TYPE runtime_meta.view_kind AS ENUM ('grid','kanban','calendar','gantt','gallery','form');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'index_method') THEN
    CREATE TYPE runtime_meta.index_method AS ENUM ('btree','gin','gist','hash');
  END IF;
END$$;

-- 1.2 Registry & versioning
CREATE TABLE IF NOT EXISTS runtime_meta.base_registry (
  base_id           uuid PRIMARY KEY,                 -- stable id for this base
  meta_version      integer          NOT NULL,        -- must match control-plane registry after sync
  spec_hash         text             NOT NULL,        -- checksum of canonical spec
  applied_at        timestamptz      NOT NULL DEFAULT now(),
  control_checkpoint jsonb           NOT NULL DEFAULT '{}'::jsonb
);

-- 1.3 Tables catalog
CREATE TABLE IF NOT EXISTS runtime_meta.tables (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  system_name       citext           NOT NULL,        -- stable logical name
  display_name      text             NOT NULL,
  status            text             NOT NULL DEFAULT 'active',  -- active|archived|deleted
  created_at        timestamptz      NOT NULL DEFAULT now(),
  updated_at        timestamptz      NOT NULL DEFAULT now(),
  UNIQUE (system_name)
);

-- 1.4 Fields catalog
CREATE TABLE IF NOT EXISTS runtime_meta.fields (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id          uuid             NOT NULL REFERENCES runtime_meta.tables(id) ON DELETE CASCADE,
  name              citext           NOT NULL,        -- stable column key
  display_name      text             NOT NULL,
  kind              runtime_meta.field_kind NOT NULL,
  is_required       boolean          NOT NULL DEFAULT false,
  is_unique         boolean          NOT NULL DEFAULT false,
  default_value     text,
  options           jsonb            NOT NULL DEFAULT '{}'::jsonb,  -- precision, validation, select options, relation targets, etc.
  position          integer          NOT NULL DEFAULT 0,
  created_at        timestamptz      NOT NULL DEFAULT now(),
  updated_at        timestamptz      NOT NULL DEFAULT now(),
  UNIQUE (table_id, name)
);

-- 1.5 Relations catalog
CREATE TABLE IF NOT EXISTS runtime_meta.relations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_table_id     uuid NOT NULL REFERENCES runtime_meta.tables(id) ON DELETE CASCADE,
  to_table_id       uuid NOT NULL REFERENCES runtime_meta.tables(id) ON DELETE CASCADE,
  cardinality       text NOT NULL CHECK (cardinality IN ('1:N','N:1','N:N')),
  from_field_id     uuid NOT NULL REFERENCES runtime_meta.fields(id) ON DELETE CASCADE,
  to_field_id       uuid,                                -- optional backlink
  options           jsonb NOT NULL DEFAULT '{}'::jsonb,  -- cascade rules, join-table name/id, etc.
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (from_field_id)
);

-- 1.6 Optional indexes hints (DDL is applied to data.*)
CREATE TABLE IF NOT EXISTS runtime_meta.indexes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id          uuid NOT NULL REFERENCES runtime_meta.tables(id) ON DELETE CASCADE,
  name              text NOT NULL,
  columns           text[] NOT NULL,                      -- in order
  method            runtime_meta.index_method NOT NULL DEFAULT 'btree',
  is_unique         boolean NOT NULL DEFAULT false,
  predicate         text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (table_id, name)
);

-- 1.7 Views (UI descriptors, not DB views)
CREATE TABLE IF NOT EXISTS runtime_meta.views (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id          uuid NOT NULL REFERENCES runtime_meta.tables(id) ON DELETE CASCADE,
  name              text NOT NULL,
  kind              runtime_meta.view_kind NOT NULL,
  definition        jsonb NOT NULL DEFAULT '{}'::jsonb,  -- filters/sorts/grouping/visible fields
  is_public         boolean NOT NULL DEFAULT false,
  public_token      text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_runtime_views_public ON runtime_meta.views(is_public);

-- 1.8 Migration bookkeeping
CREATE TABLE IF NOT EXISTS runtime_meta.migrations_applied (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meta_version      integer      NOT NULL,
  step              text         NOT NULL,       -- human-readable step name
  started_at        timestamptz  NOT NULL DEFAULT now(),
  finished_at       timestamptz,
  status            text         NOT NULL DEFAULT 'ok',  -- ok|failed|rolled_back
  details           jsonb        NOT NULL DEFAULT '{}'::jsonb
);

-- =========================================================
-- 2) data (User content)
--    Physical tables (data.t_<table_uuid>) are created by the migration service.
-- =========================================================

-- 2.1 Shared attachments registry (pointers; binaries live in object storage)
CREATE TABLE IF NOT EXISTS data.attachments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id          uuid NOT NULL REFERENCES runtime_meta.tables(id) ON DELETE CASCADE,
  record_id         uuid NOT NULL,                     -- refers to data.t_<table_uuid>.id
  field_id          uuid NOT NULL REFERENCES runtime_meta.fields(id) ON DELETE CASCADE,
  object_key        text NOT NULL,                     -- S3/GCS path
  filename          text NOT NULL,
  size_bytes        bigint NOT NULL,
  mime_type         text,
  checksum          text,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_data_attachments_table_record ON data.attachments(table_id, record_id);

-- 2.2 Optional: Global, append-only history (lighter than per-table history tables)
CREATE TABLE IF NOT EXISTS data.history (
  version_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id          uuid NOT NULL REFERENCES runtime_meta.tables(id) ON DELETE CASCADE,
  record_id         uuid NOT NULL,
  action            text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  changed_by        uuid,                               -- user id (if available)
  changed_at        timestamptz NOT NULL DEFAULT now(),
  snapshot          jsonb NOT NULL                      -- full-row snapshot or changed cols
);
CREATE INDEX IF NOT EXISTS idx_data_history_record ON data.history(table_id, record_id, changed_at DESC);

-- =========================================================
-- 3) OPTIONAL helpers (enable per-table where needed)
--    These are templates; your migration service can attach them case-by-case.
-- =========================================================

-- 3.1 Full-text maintenance (example: concatenate common text fields into tsvector 'ft')
CREATE OR REPLACE FUNCTION data.fn_update_ft(var_cols text[])
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  txt text := '';
  col text;
BEGIN
  FOREACH col IN ARRAY var_cols LOOP
    -- concatenate text columns if they exist; ignore others
    BEGIN
      txt := txt || ' ' || COALESCE((to_jsonb(NEW)->>col), '');
    EXCEPTION WHEN undefined_column THEN
      -- ignore silently
      CONTINUE;
    END;
  END LOOP;
  NEW.ft := to_tsvector('simple', trim(both ' ' from txt));
  RETURN NEW;
END $$;

-- 3.2 History capture (writes to data.history, single table for all changes)
CREATE OR REPLACE FUNCTION data.fn_log_history(table_uuid uuid)
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO data.history(table_id, record_id, action, changed_by, snapshot)
    VALUES (table_uuid, NEW.id, 'INSERT', NEW.created_by, to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO data.history(table_id, record_id, action, changed_by, snapshot)
    VALUES (table_uuid, NEW.id, 'UPDATE', NEW.updated_by, to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO data.history(table_id, record_id, action, changed_by, snapshot)
    VALUES (table_uuid, OLD.id, 'DELETE', NULL, to_jsonb(OLD));
    RETURN OLD;
  END IF;
END $$;

-- 3.3 RLS scaffolding (DISABLED by default; enable per table if needed)
-- Example policy (you would ALTER TABLE data.t_<uuid> ENABLE ROW LEVEL SECURITY; and attach policies)
-- CREATE POLICY rls_read ON data.t_<uuid> FOR SELECT
--   USING ( current_setting('app.base_mode', true) = 'tenant' );  -- replace with your real condition/GUCs

-- =========================================================
-- 4) Notes on creating physical user tables
-- =========================================================
-- Your migration service should, for each runtime_meta.tables.id = <table_uuid>:
--   - CREATE TABLE data.t_<table_uuid_without_dashes> (
--       id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
--       created_at timestamptz NOT NULL DEFAULT now(),
--       updated_at timestamptz NOT NULL DEFAULT now(),
--       created_by uuid, updated_by uuid,
--       ... typed columns based on runtime_meta.fields (cast via fields.kind & options) ...,
--       ft tsvector NULL        -- only if you enable FTS for this table
--     );
--   - Apply UNIQUE/BTREE/GIN indexes as described in runtime_meta.indexes.
--   - If N:N relation exists, CREATE TABLE data.jt_<relation_field_uuid> (...).
--   - Optionally attach:
--       * BEFORE INSERT/UPDATE trigger to data.fn_update_ft('{col1,col2,...}')
--       * AFTER INSERT/UPDATE/DELETE trigger to data.fn_log_history('<table_uuid>');
--   - Set table owner to the app runtime role; **no DDL** for normal app role.
