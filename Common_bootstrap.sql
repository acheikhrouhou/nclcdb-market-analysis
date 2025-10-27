--- Common bootstrap SQL for all DBs
--- run in each logs DB


CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()

-- helper enum(s) reused across DBs if you want
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sev_level') THEN
    CREATE TYPE sev_level AS ENUM ('info','warn','critical');
  END IF;
END$$;
