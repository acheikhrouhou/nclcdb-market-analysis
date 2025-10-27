this is where your users spend most time, so clarity and UX quality matter a lot. I’ll map out a detailed sitemap + key page features for the **Tenant Portal + Workspace** on `app.nclcdbaas.com`.

---

# 🧭 Tenant Portal + Workspace UX (app.nclcdbaas.com)

## 🎯 User Roles

* Tenant Owner (full access)
* Admin Editor (manage workspace, templates, automations)
* Editor (CRUD data)
* Viewer/commenter (read only)

## ✅ Top-Level Navigation (left sidebar)

1. **Dashboard**
2. **Workspaces / Bases**
3. **Templates**
4. **Data (active workspace)**

   * Tables
   * Views
   * Forms
   * Automations
   * Integrations
5. **Billing & Usage**
6. **Team & Access**
7. **Settings**
8. **Help & Docs**
9. **Logout**

---

## 🗂 Sitemap & Page Breakdown

### /dashboard

* Snapshot widgets:

  * Active workspace/base count
  * Recent record edits
  * Run credits left / next billing date
  * Outstanding alerts (quota, wallet)
* Quick links: Create new base, Import template, Upgrade plan
* News banner: Product updates + community forum link

### /workspaces

* List all bases for this tenant:

  * Table: Name | Status | Region | Records | Views | Created
  * Actions: Open → workspace, Duplicate, Archive, Delete
  * Create new base button
* Base creation wizard: Choose name, region, template (optional), set visibility
* After creation, redirect to new workspace homepage

### /templates

* Browse gallery (same templates site, but filtered for internal install)
* Categories: My Templates | Official | Marketplace
* Template detail: preview table/fields/views, click “Install to a workspace”
* Manage installed templates: change version, remove

### [When inside a workspace] /workspace/{workspaceId}/...

#### /workspace/{id}/tables

* List of tables: Name | Views | Rows | Last change
* Actions: Add table, Rename, Delete, Duplicate, Export CSV/JSON
* When editing/creating table:

  * Modal: Table name, description
  * Manage fields: Add field types (text, number, select…); drag reorder; set required/unique
  * Field property side pane
  * Reorder fields via drag handle

#### /workspace/{id}/tables/{tableId}/views

* Default view: grid of records
* Switch between view types: Gallery / Kanban / Calendar / Gantt
* Create new view: choose type, filters, grouping, visible fields
* Bookmark/share view: link with permissions

#### /workspace/{id}/tables/{tableId}/forms

* List of forms associated with table
* Create new form: choose fields, set public link or embed, submission notifications
* Manage form rules: validate, on-submit actions

#### /workspace/{id}/tables/{tableId}/automations

* List of automations: Trigger / Condition / Action
* Create new automation: choose trigger (record created/updated, time schedule, webhook), define steps (slack/email/webhook/integration)
* Run log: show last 10 runs, status, error messages
* Run count usage bar (shows part of credit consumption)

#### /workspace/{id}/integrations

* Pre-built connectors: Slack, Teams, Google Sheets, Zapier/Make
* Premium connectors: Salesforce, HubSpot (locked if plan not eligible)
* Manage webhooks: register endpoint, test delivery
* API Tokens: (redirect to billing/team for token creation) – admin only

#### /workspace/{id}/billing-usage

* Current plan (Free / Pro / Business) & seats
* Credit wallet: runs remaining, renewal date, auto-refill toggle
* Usage charts: last 30d runs, API calls, storage used, records count
* Upgrade plan button (if > limit)
* Invoices & payment methods

#### /workspace/{id}/team-access

* List team members: Name | Role | Last login
* Invite new user: email, role
* Edit role, remove, resend invite
* SSO setup (Business tier): configure SAML/SSO provider

#### /workspace/{id}/settings

* Workspace info: Name, description, region, visibility
* Base sharing: public/private, link settings
* Delete workspace: confirmation workflow
* Version/restore: (Enterprise) restore from backup
* Security & compliance: IP allow list, data residency, audit logs (Business+)

#### /workspace/{id}/help-docs

* Inline articles/guides specific to workspace & templates
* Button: Contact support

---

## 🔍 UX Patterns & Behaviour Highlights

* **Empty states**: On first table, show “Add your first table → start from template” with quick video.
* **Inline help & tooltips**: Fields have inline “?” icons with examples.
* **Template-first entry**: On new workspace creation, optionally choose template and prefill sample data; skip step leads to blank table.
* **Credit usage indicator**: On automations page and dashboard show “You have X runs remaining. Buy more or upgrade.”
* **Permissions awareness**: If role = Viewer, hide “Add table” actions; grey out editable elements.
* **Real-time updates**: On table grid, show “Last updated by John at 10:05” and live collaborator presence.
* **Search bar**: Global search across tables + views + records.
* **Breadcrumbs**: `Workspace Name › Tables › Customer › Views › Form 1`
* **Multi-workspace navigation**: Dropdown or sidebar toggle to switch workspace contexts.
* **Global notifications**: Top bar bell icon → shows tasks: e.g., “Run credits low”, “New template available”, “Premium connector” upgrade.

---

## 🗺 Full Sitemap (text tree) for app.nclcdbaas.com

```
app.nclcdbaas.com
 ├─ /login
 ├─ /signup
 ├─ /dashboard
 ├─ /workspaces
 │   ├─ /{workspaceId}
 │   │   ├─ /overview
 │   │   ├─ /tables
 │   │   │   ├─ /create
 │   │   │   ├─ /{tableId}
 │   │   │   │   ├─ /fields
 │   │   │   ├─ /{tableId}/views
 │   │   ├─ /{tableId}/forms
 │   │   ├─ /{tableId}/automations
 │   │   ├─ /integrations
 │   │   ├─ /billing-usage
 │   │   ├─ /team-access
 │   │   ├─ /settings
 │   │   └─ /help-docs
 ├─ /templates
 └─ /account-settings
```

---


