
✅ We selected the **MVP domain topology**:

* `www.nclcdbaas.com` → Marketing
* `app.nclcdbaas.com` → Tenant Portal + Workspace (Control + Data Plane UX)
* `api.nclcdbaas.com` → Public CRUD API (no UI, just endpoints)
* `admin.nclcdbaas.com` → Internal Admin Console

we’ll start with **Admin Console UX** — the most operationally critical.

---

# 🛠️ Admin Console UX (admin.nclcdbaas.com)

> Users: Internal staff only (support, ops, finance, engineering leads)
> Must be strictly protected (SSO + role-based rights + IP restriction)

---

## ✅ Admin Console — Navigation structure (MVP)

### Top-level nav (left sidebar)

1️⃣ **Dashboard**

* KPIs: Active tenants, MRR, run volume, API errors, provision queue
* Alerts: overdue payments, failing migrations, large rollback candidates
* Quick actions: suspend tenant, trigger migration, refund credit

2️⃣ **Tenants**

* Table view: name, plan, region, base count, last active, status
* Drill into Tenant detail

  * Org info: name, contacts, region, notes
  * Status & controls: suspend / resume / delete
  * Plan & seats & credits
  * Usage overview: runs, API calls, storage
  * Bases list → link to Base detail pages

3️⃣ **Bases** *(searchable)*

* See all bases across tenants (for triage)
* Base detail

  * Region and DB status (connection pool)
  * Meta version + applied migrations
  * Row count estimate, storage GB
  * Health checks (indexes, bloat)
  * Open in read-only viewer (optional)

4️⃣ **Users** *(tenant users)*

* Global search by email
* Account status (locked / active)
* Tenant memberships list
* Force password reset / lock / impersonate (if approved)

5️⃣ **Billing**

* All subscriptions w/ filters
* Unpaid invoices
* Refund & credit adjustments (with required reason)
* Wallet balances vs consumption
* Accounting export (CSV)

6️⃣ **Usage & Metering**

* Global graphs: API calls/hour, run usage/day, storage/week
* Top consuming tenants
* Rate limiting hit stats

7️⃣ **Audit Logs**

* **Admin actions** (from `admin_log.admin_events`)
* Filters: by admin, tenant, resource, date, action
* Export search results as CSV

8️⃣ **Alerts & Notifications**

* Alerts from `notify.alerts` (status: open/ack/resolved)
* Acknowledge / resolve workflow
* Notification history (email/slack/webhook)

9️⃣ **Migrations (Schema Ops)**

* List pending/failed migrations per base
* Retry/rollback actions (with justification notes)
* Compare runtime meta vs control-plane registry

🔟 **System Health**

* Service uptime
* Worker queue depth
* Error tracking links (Sentry)
* Maintenance mode toggle

⚙️ **Settings**

* Feature flags
* Role management for Admin Console users
* Email templates (notification settings)
* Maintenance banner

---

### Key interaction examples

| Task                         | Where in UI                                       | Required UX                              |
| ---------------------------- | ------------------------------------------------- | ---------------------------------------- |
| Suspend a tenant             | *Tenants → Tenant Detail → Status*                | Hard confirmation modal, reason required |
| Check why automations failed | *Alerts → Filter by RUN_FAILURE* → dive into logs | Link to record + migration state         |
| Investigate runaway query    | *System Health → DB stats → Open Base Health*     | Show slow queries + bloat %              |
| Refund a credit pack         | *Billing → Wallet Ledger → Action: Refund*        | Audit-required note                      |

---

## ✅ Admin Console — Wireframe-style hierarchy (text sitemap)

```
admin.nclcdbaas.com
 ├─ /dashboard
 ├─ /tenants
 │   ├─ /{tenantId}
 │   │   ├─ /overview
 │   │   ├─ /bases
 │   │   │   ├─ /{baseId}
 │   │   │   │   ├─ /overview
 │   │   │   │   ├─ /migrations
 │   │   │   │   └─ /health
 │   │   ├─ /users
 │   │   ├─ /billing
 │   │   └─ /usage
 ├─ /bases
 │   ├─ /{baseId}
 │   │   ├─ /overview
 │   │   ├─ /migrations
 │   │   └─ /health
 ├─ /users
 │   └─ /{userId}
 ├─ /billing
 ├─ /usage
 ├─ /audit-logs
 ├─ /alerts
 ├─ /migrations
 ├─ /system-health
 └─ /settings
```

---

## ✅ Built-in Security & UX Rules

* **Every admin action** requires:
  ✅ server-side permission check
  ✅ logged in `admin_log.admin_events`
  ✅ reason/comment when destructive

* **Search-first** navigation: global search to locate tenants & users fast

* **Data visibility**: only show user email partially masked unless support-approval role

* **Export limits**: CSV exports require *Narrow filters* to avoid accidental PII dumps

---

# Next Step — visual design

Once you approve this structure, I can provide:

✅ High-fidelity Wireframes (Figma layout)
✅ Component mapping (tables, filters, modals, charts)
✅ Role matrix for internal admin types (Support / Finance / Ops / Eng)

---


