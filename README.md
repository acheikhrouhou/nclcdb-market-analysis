# NC LC/NC DBaaS – Project Overview

This repository defines a Low‑Code / No‑Code Database‑as‑a‑Service (DBaaS) offering, including:

- Market landscape and positioning
- Control Plane and Data Plane logical/physical schemas (PostgreSQL)
- Public CRUD API (base‑scoped) specification and UI guidelines
- Admin Console and Tenant Portal UX
- Marketing UX and a ready‑to‑embed Pricing page (React/Tailwind)


## Scope at a Glance

- Marketing: `www.nclcdbaas.com` – value prop, pricing, docs
- App (Tenant Portal + Workspace): `app.nclcdbaas.com` – manage bases, schema, usage
- Public API: `api.nclcdbaas.com` – CRUD on base data (no DDL/billing exposure)
- Admin Console: `admin.nclcdbaas.com` – internal operations (billing, migrations, alerts)

See: `API docs and UI.md:1`, `Admin Console UX.md:1`, `Marketing Website UX.md:1`.


## Repository Map (key files)

- Market analysis
  - `Cloud DB Services Market Analysis.md:1` – competitive landscape and taxonomy
  - `LCNC DBaaS_pricing offer.md:1` – pricing logic and credit wallet model ($5 → 2,500 runs)
  - `Low-Code-No-Code Database Service - Market Entry Report (Draft v2).md:1` – entry strategy

- Control plane (design + SQL)
  - `Control_Plane_database_schema .md:1` – logical model narrative
  - `control_plane_logical_model.sql:1` – first‑draft Postgres DDL (tenants, bases, tokens, billing, usage, wallet, schema registry, notifications, access logs)
  - `Common_bootstrap.sql:1` – shared types/extensions seed

- Data plane (design + SQL)
  - `data_plane_database_schema.md:1` – data‑plane structure and invariants
  - `data_plane_logical_model.sql:1` – first‑draft Postgres DDL for per‑base DB

- API and UI
  - `API docs and UI.md:1` – stack, security, CRUD endpoints, query model, error model, cURL quickstart
  - Pricing page components: `PricingPage.jsx:1`, `PricingPage.tsx:1`

- Admin, Tenant, and Marketing UX
  - `Admin Console UX.md:1` – navigation, operations workflows, safety rules
  - `Tenant Portal-Workspace.md:1` – tenant workspace and base operations
  - `feature-level_menus_per_portal.md:1` – portal menus by feature level
  - `Marketing Website UX.md:1` – marketing site structure

- Ops/Observability (logging schemas)
  - `PostgreSQL_schema_four logging databases.md:1` – overview
  - `Admin_Operations_Log_DB.sql:1`, `Tenant_Portal_Operations_Log_DB.sql:1`, `Data-Plane_Activity_Log_DB.sql:1`, `Alarms_Notifications_DB.sql:1` – specialized logging DBs

- Use cases and building blocks
  - `ContolPlane-Dataplane_UseCase.md:1` – end‑to‑end flows (control ↔ data)
  - `core_building_blocks.md:1` – conceptual building blocks for the platform


## Architecture Summary

- Isolation model
  - Base‑scoped tokens; each token maps to exactly one base/database
  - Control Plane holds identity, plans, usage, billing, wallets, schema registry
  - Data Plane (per base) holds `runtime_meta` cache and `data.*` tables

- API surface (CRUD only)
  - `/v1/tables/{tableId}/records` for list/create/delete‑by‑filter
  - `/v1/tables/{tableId}/records/{id}` for get/patch/delete
  - Batch upsert/delete; CSV import/export; attachment signed‑URL flow
  - Pagination (cursor), rich filters/sorts, projections; idempotency and optimistic concurrency
  - See `API docs and UI.md:1`

- Observability and safety
  - Structured logs and OpenTelemetry; Sentry for errors
  - Admin actions audited and justified; rate limits and quotas enforced
  - Alerting for payments, migrations, thresholds


## Getting Started (Docs and UI)

- Pricing page (React + Tailwind)
  - Use either `PricingPage.jsx` or `PricingPage.tsx`
  - Drop into a React app (Vite/CRA/Next). Ensure Tailwind is configured
  - Optional: wire annual/monthly toggle math inside the component

- API documentation
  - Specs live in `API docs and UI.md:1`
  - Next step: generate an OpenAPI 3.1 document and publish docs (Redoc/Swagger)


## Database Schemas (PostgreSQL)

- Control Plane
  - Tenancy (`tenants`, `users`, memberships), bases, API tokens (scoped), plans/subscriptions, wallet and ledger, usage/metering, schema registry, notifications, access logs
  - Start from `control_plane_logical_model.sql:1` and split into migrations

- Data Plane (per Base)
  - `runtime_meta` for local descriptors (tables, fields, relations, views, versions, migrations)
  - `data.*` physical tables (`t_<uuid>`, `jt_<uuid>`, optional history)
  - See `data_plane_database_schema.md:1` and `data_plane_logical_model.sql:1`

- Logging and notifications DBs
  - Separate schemas for admin ops, tenant portal ops, data‑plane activity, alarms/notifications (see files in Ops/Observability above)


## Security Model

- Base‑scoped tokens with scopes: `read`, `write`, `delete`
- Strict CORS (app domain only by default), WAF/CDN at edge, Envoy/NGINX gateway
- App service role has no DDL access to data planes; schema changes flow via control‑plane migrations
- Optional RLS later; tenant isolation via base routing from the control plane


## Roadmap / Next Steps

- Author OpenAPI 3.1 spec and generate SDKs (TS/Python)
- Convert SQL drafts into versioned migrations (e.g., Atlas/Liquibase/Flyway)
- Seed plans and features; implement wallet/ledger logic
- Stand up Admin Console skeleton (SSO, roles, audit log integration)
- Normalize text encoding artifacts across docs (smart quotes/symbols)


## Notes

- Some Markdown/SQL files contain minor encoding artifacts (smart quotes, symbols). As you operationalize, normalize to UTF‑8 to avoid tooling issues.
