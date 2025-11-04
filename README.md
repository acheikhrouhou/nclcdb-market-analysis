# NC LC/NC DBaaS - Project Overview

This repository defines a Low-Code / No-Code Database-as-a-Service (DBaaS) offering, including:

- Market landscape and positioning
- Control plane, data plane, and logging database schemas (PostgreSQL)
- Public CRUD API (base-scoped) specification and UI guidelines
- Admin console and tenant portal UX
- Marketing UX and a ready-to-embed pricing page (React/Tailwind)


## Scope at a Glance

- Marketing: `www.nclcdbaas.com` - value prop, pricing, docs
- App (tenant portal + workspace): `app.nclcdbaas.com` - manage bases, schema, usage
- Public API: `api.nclcdbaas.com` - CRUD on base data (no DDL/billing exposure)
- Admin console: `admin.nclcdbaas.com` - internal operations (billing, migrations, alerts)

See `docs/product/API docs and UI.md`, `docs/product/Admin Console UX.md`, `docs/product/Marketing Website UX.md`.


## Repository Layout

```
docs/                      # Market, product, ops, and schema narratives
  market/
  product/
  ops/
  schemas/
apps/                      # User-facing and API applications
  www/                     # Marketing site artefacts
  admin/                   # Admin console front end
  app/                     # Tenant workspace front end
  api/                     # Public CRUD API server
background/                # Batch jobs, workers, scheduled tasks
  jobs/
  workers/
db/                        # SQL assets for control/data/log databases
  control-plane/
    migrations/
    seed/
  data-plane/
    templates/
  logs/
    admin/
    tenant/
    data-plane/
    alerts/
shared/                    # Cross-cutting libraries, config, design system
  config/
  lib/
  ui/
  testing/
ops/                       # CI/CD, IaC, monitoring, runtime playbooks
  ci/
  cd/
  infra/
  monitoring/
```


## Key Artefacts by Area

- **Market analysis**
  - `docs/market/Cloud DB Services Market Analysis.md` - competitive landscape and taxonomy
  - `docs/product/LCNC DBaaS_pricing offer.md` - pricing logic and credit wallet model ($5 + 2,500 runs)
  - `docs/market/Low-Code-No-Code Database Service - Market Entry Report (Draft v2).md` - entry strategy

- **Control plane (design + SQL)**
  - `docs/schemas/Control_Plane_database_schema .md` - logical model narrative
  - `db/control-plane/migrations/control_plane_logical_model.sql` - first-draft PostgreSQL DDL (tenants, bases, tokens, billing, usage, wallet, schema registry, notifications, access logs)
  - `db/control-plane/seed/Common_bootstrap.sql` - shared types/extensions seed

- **Data plane (design + SQL)**
  - `docs/schemas/data_plane_database_schema.md` - data-plane structure and invariants
  - `db/data-plane/templates/data_plane_logical_model.sql` - first-draft PostgreSQL DDL for per-base databases

- **API and UI**
  - `docs/product/API docs and UI.md` - stack, security, CRUD endpoints, query model, error model, cURL quickstart
  - `apps/www/PricingPage.jsx` and `apps/www/PricingPage.tsx` - embeddable pricing page components

- **Admin, tenant, and marketing UX**
  - `docs/product/Admin Console UX.md` - navigation, operations workflows, safety rules
  - `docs/product/Tenant Portal-Workspace.md` - tenant workspace and base operations
  - `docs/product/feature-level_menus_per_portal.md` - portal menus by feature level
  - `docs/product/Marketing Website UX.md` - marketing site structure

- **Ops and observability**
  - `docs/ops/NC_LCDBaaS_Infra & Runtime Status.md` - infrastructure and runtime notes
  - `docs/schemas/PostgreSQL_schema_four logging databases.md` - overview of logging databases
  - `db/logs/*` - admin, tenant, data-plane activity, and alarms/notifications schemas

- **Use cases and building blocks**
  - `docs/product/ContolPlane-Dataplane_UseCase.md` - end-to-end flows across control and data contexts
  - `docs/product/core_building_blocks.md` and `docs/product/core web stack.md` - platform building blocks and stack overview


## Architecture Summary

- Isolation model
  - Base-scoped tokens; each token maps to exactly one base/database
  - Control plane holds identity, plans, usage, billing, wallets, schema registry
  - Data plane (per base) holds `runtime_meta` cache and `data.*` tables

- API surface (CRUD only)
  - `/v1/tables/{tableId}/records` for list/create/delete-by-filter
  - `/v1/tables/{tableId}/records/{id}` for get/patch/delete
  - Batch upsert/delete; CSV import/export; attachment signed-URL flow
  - Pagination (cursor), rich filters/sorts, projections; idempotency and optimistic concurrency
  - See `docs/product/API docs and UI.md`

- Observability and safety
  - Structured logs and OpenTelemetry; Sentry for errors
  - Admin actions audited and justified; rate limits and quotas enforced
  - Alerting for payments, migrations, thresholds


## Getting Started (Docs and UI)

- Pricing page (React + Tailwind)
  - Use either `apps/www/PricingPage.jsx` or `apps/www/PricingPage.tsx`
  - Drop into a React app (Vite/CRA/Next). Ensure Tailwind is configured
  - Optional: wire annual/monthly toggle math inside the component

- API documentation
  - Specs live in `docs/product/API docs and UI.md`
  - Next step: generate an OpenAPI 3.1 document and publish docs (Redoc/Swagger)


## Database Schemas (PostgreSQL)

- Control plane
  - Tenancy (`tenants`, `users`, memberships), bases, API tokens (scoped), plans/subscriptions, wallet and ledger, usage/metering, schema registry, notifications, access logs
  - Start from `db/control-plane/migrations/control_plane_logical_model.sql` and split into migrations

- Data plane (per base)
  - `runtime_meta` for local descriptors (tables, fields, relations, views, versions, migrations)
  - `data.*` physical tables (`t_<uuid>`, `jt_<uuid>`, optional history)
  - See `docs/schemas/data_plane_database_schema.md` and `db/data-plane/templates/data_plane_logical_model.sql`

- Logging and notifications databases
  - Separate schemas for admin ops, tenant portal ops, data-plane activity, alarms/notifications (see content under `db/logs/`)


## Security Model

- Base-scoped tokens with scopes: `read`, `write`, `delete`
- Strict CORS (app domain only by default), WAF/CDN at edge, Envoy/NGINX gateway
- App service role has no DDL access to data planes; schema changes flow via control-plane migrations
- Optional RLS later; tenant isolation via base routing from the control plane


## Roadmap / Next Steps

- Author OpenAPI 3.1 spec and generate SDKs (TS/Python)
- Convert SQL drafts into versioned migrations (e.g., Atlas/Liquibase/Flyway)
- Seed plans and features; implement wallet/ledger logic
- Stand up admin console skeleton (SSO, roles, audit log integration)
- Normalize text encoding artefacts across docs (smart quotes/symbols)


## Notes

- Some Markdown/SQL files contain minor encoding artefacts (smart quotes, symbols). As you operationalize, normalize to UTF-8 to avoid tooling issues.
