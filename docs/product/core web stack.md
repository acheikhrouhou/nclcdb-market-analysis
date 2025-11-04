Totally agree: you can (and should) use the **same core web stack** across the three sites. That keeps hiring simple, speeds up delivery, and lets you share a design system + utilities.

Here’s a **clean bill-of-materials per site**, with what’s shared vs. what’s different.

---

# Shared web stack (all three)

* **Framework:** Next.js (React) + TypeScript
* **UI:** Tailwind CSS + shadcn/ui, icons with lucide-react
* **Forms & validation:** React Hook Form + Zod
* **Data fetching/state:** TanStack Query (React Query), Axios/fetch wrapper
* **Design system:** shared component library + tokens (Tailwind preset)
* **Internationalization:** next-intl (or next-i18next)
* **Animations:** Framer Motion (sparingly)
* **Auth client:** NextAuth (OIDC) or Auth0 SDK (both usable across apps)
* **Observability:** Sentry (front-end), OpenTelemetry web exporter (if needed)
* **Analytics:** PostHog (product) + GA4 (marketing)
* **Testing:** Playwright (E2E), Jest/Vitest (unit), ESLint + Prettier
* **Security headers:** next-safe/middleware (CSP, HSTS, XFO, etc.)
* **CI/CD:** GitHub Actions (lint/test/build), deploy to Vercel (or Netlify) behind Cloudflare

---

# [www.nclcdbaas.com](http://www.nclcdbaas.com) (Marketing & Docs)

**Purpose:** convert visitors; SEO; light docs preview

* **Rendering mode:** SSG/ISR (fast, CDN-friendly)
* **Content:** MDX + Contentlayer (MVP) or Sanity/Contentful (if you want non-dev edits)
* **Docs:** MDX pages; embed Redoc/Swagger UI for API reference; Algolia DocSearch (optional)
* **SEO:** next-sitemap, robots.txt, canonical tags, OpenGraph, JSON-LD
* **A/B & experiments:** Vercel Experiments / Google Optimize alternative
* **Lead capture:** HubSpot/ConvertKit forms (serverless webhook)
* **Pricing & calculator:** client components + shared “pricing config” from Control Plane
* **Blog:** MDX with image optimization; RSS feed
* **Integrations:** Crisp/Intercom chat widget, Cookie consent
* **Hosting:** Vercel (edge network); Cloudflare in front (DNS/WAF)

---

# app.nclcdbaas.com (Tenant Portal + Workspace)

**Purpose:** authenticated control + data UX

* **Rendering mode:** SSR for auth gates + SPA for workspace
* **Auth:** NextAuth/Auth0 (email/OAuth); SAML via WorkOS (Business+)
* **RBAC:** role guard HOCs + server actions checking session claims
* **Data fetching:** React Query bound to **Control Plane API** and **CRUD API**
* **Real-time:** Ably/Pusher or WebSockets (presence, live grid updates)
* **Data grid:** TanStack Table (virtualized) or AG Grid (if heavy)
* **Uploads:** S3 pre-signed URLs; background virus scan hook
* **Automations UI:** flow builder (React Flow), run logs (virtualized list)
* **Usage & billing:** Stripe Customer Portal link; charts with Recharts
* **Templates:** gallery + “Install to workspace” action
* **Feature flags:** LaunchDarkly/OpenFeature to gate enterprise features
* **Error boundaries:** per-section; toast layer (sonner)
* **Localization:** next-intl namespaces per module (tables/forms/automations)
* **Accessibility:** Radix primitives via shadcn/ui; axe rules in CI
* **Hosting:** Vercel (or container on ECS/Fargate if you prefer); Cloudflare in front

---

# admin.nclcdbaas.com (Internal Console)

**Purpose:** ops, support, billing, audits (staff-only)

* **Rendering mode:** SSR (server actions to query Control/Logs DBs)
* **Admin SSO:** Google Workspace OIDC (via NextAuth) + IP allowlist/VPN
* **RBAC:** fine-grained permissions (support/finance/ops/eng)
* **Data views:** server-side tables with cursor pagination; CSV export
* **Audit viewer:** streamed logs from **admin_log**/**portal_log**/**data_activity** DBs
* **Metrics:** lightweight charts (Recharts) + links/embeds to Grafana
* **Dangerous actions:** confirm modals with reason (logged), break-glass workflow
* **Impersonation:** short-lived signed session with dual-control (optional)
* **Error handling:** strict; every mutation logs to `admin_log.admin_events`
* **Hosting:** same as app; SSO + network guardrails

---

## Cross-cutting services these apps talk to

* **Control Plane API** (tenants, bases, tokens, billing, usage, registry)
* **CRUD API** (`api.nclcdbaas.com`, records only)
* **Stripe** (checkout/portal webviews)
* **Search (optional):** Typesense/OpenSearch for template/docs search
* **Notifications:** in-app bell fed by notify service (SSE/WebSocket)

---

## Minimal “wiring” you’ll want from day one

* Shared **ui** package (components), **utils** (date/currency), **api** (fetch clients), **config** (env, feature flags) via a monorepo (pnpm + Turborepo)
* Environment handling: Doppler/Vercel envs; typed `process.env` with zod
* Error & request correlation IDs passed from edge → apps → APIs
* Strict CSP per app (different for www vs app/admin)
* SSO & session cookie settings tuned (SameSite, secure, domain)

---

If you want, I can turn this into a small **architecture diagram** plus a **Turborepo layout** (`apps/www`, `apps/app`, `apps/admin`, `packages/ui`, `packages/api`, etc.) so your team can bootstrap the repo in a day.
