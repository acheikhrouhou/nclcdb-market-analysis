<p align="right">now let's go back to the control and dataplane for my understanding. We're goingf to apply all what we've build so far on a use case. Imagine I am a tenant. As soon as I create my account, I have a first database created. Then I log into my account (through the portal) and add three tables, each table with a set of columns? I will generate an API key to access that database. Then I created a second database, and create the associated API Key. Then add 1 table in that database. The table is dedicated to customer data. As a free subscriber tenant, I also added a payment for 2500 runs. Where are all pieces of that context (split which are in the control plane, which are in the dataplane? What is supposed to be logged and where?) </p>

Great scenario. I’ll map every step/state to **where it lives** (Control Plane vs Data Plane) and **what gets logged** (which logging DB), so you can see the boundaries in action.

---

# Snapshot view

| Thing                                   | Control Plane (authoritative)                                                                                                   | Data Plane (per-base, runtime)                                                                                                   | Logged where                                                                                                                                 |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant account                          | `tenants`, `users`, `tenant_memberships`                                                                                        | —                                                                                                                                | **portal_log.auth_events / portal_events**                                                                                                   |
| Auto-created **Base #1**                | `bases` row (tenant, region), `usage_counters` seed                                                                             | Provisioned DB/schema for Base #1                                                                                                | **portal_log.portal_events** (BASE_CREATE) + **admin_log.admin_events** (if system-initiated)                                                |
| Base #1 **schema** (3 tables + columns) | **Schema registry**: `schema_registry` (versions), change requests                                                              | **runtime_meta**: `tables`, `fields`, `relations`, `views` (+ `base_registry.meta_version`); **data**: `t_<uuid>` tables created | **portal_log.portal_events** (schema ops) + **data_activity.record_events** (for any seed/initial rows)                                      |
| API key for **Base #1**                 | `api_tokens` (token_hash, scopes, base_id, last_used_at)                                                                        | — (runtime only needs base routing)                                                                                              | **portal_log.token_events** (ISSUE), later **data_activity.api_access_logs** on use                                                          |
| Created **Base #2**                     | New `bases` row (+ `usage_counters` seed)                                                                                       | Provisioned DB/schema for Base #2                                                                                                | **portal_log.portal_events** (BASE_CREATE)                                                                                                   |
| API key for **Base #2**                 | New `api_tokens` (scoped to Base #2)                                                                                            | —                                                                                                                                | **portal_log.token_events** (ISSUE)                                                                                                          |
| Base #2 **Customer** table              | Registry update in `schema_registry`                                                                                            | **runtime_meta** rows + `data.t_<uuid>` table                                                                                    | **portal_log.portal_events** (TABLE_CREATE)                                                                                                  |
| Free plan + **$5 credits (2,500 runs)** | `subscriptions` (Free), `wallets` (balance), `wallet_ledger` (+2,500 runs, +$500 cents), `usage_counters` (per month, per base) | —                                                                                                                                | **portal_log.portal_events** (TOPUP) + **admin_log.admin_events** (if staff assisted). **notify.alerts/notifications** later for low balance |

---

# Step-by-step with detail

## 1) Tenant signs up → auto-provision Base #1

* **Control Plane**

  * `tenants`, `users`, `tenant_memberships` rows created.
  * `bases`: **Base #1** row (tenant, region, status).
  * `usage_counters`: (tenant, base, month) initialized.
* **Data Plane (Base #1)**

  * Empty per-base Postgres DB (or schema) created.
  * `runtime_meta.base_registry` initialized (version 1).
* **Logs**

  * **portal_log.auth_events**: USER_SIGNUP / USER_LOGIN.
  * **portal_log.portal_events**: BASE_CREATE (actor = user or system).
  * (Optional) **admin_log.admin_events** if provisioning is system-automated via admin service account.

## 2) In portal, tenant adds **three tables** (with columns) in Base #1

* **Control Plane**

  * Canonical spec updated in `schema_registry` (new **meta_version**).
* **Data Plane (Base #1)**

  * Migration runner:

    * Writes `runtime_meta.tables` + `fields` (+ `relations/views` if any).
    * Creates physical tables `data.t_<uuid>` with typed columns.
    * Updates `runtime_meta.base_registry.meta_version`.
* **Logs**

  * **portal_log.portal_events**: TABLE_CREATE ×3, FIELD_CREATE ×N.
  * **runtime_meta.migrations_applied** (inside Base #1) records each DDL step.
  * If sample data inserted: **data_activity.record_events** (INSERT) per record.

## 3) Tenant generates an **API key** for Base #1

* **Control Plane**

  * `api_tokens`: token (hash), **scoped to Base #1**, scopes (`read|write|delete`).
* **Data Plane**

  * None (routing uses base_id).
* **Logs**

  * **portal_log.token_events**: ISSUE (tenant, base, token_id).
  * On use: **data_activity.api_access_logs** for each call; **data_activity.record_events** for CRUD.

## 4) Tenant creates **Base #2** and its **API key**

* **Control Plane**

  * `bases`: new row for Base #2.
  * `api_tokens`: new token (hash), **scoped to Base #2**.
  * `usage_counters`: seed for Base #2 (new month record).
* **Data Plane (Base #2)**

  * Fresh DB/schema; `runtime_meta.base_registry` initialized.
* **Logs**

  * **portal_log.portal_events**: BASE_CREATE (Base #2).
  * **portal_log.token_events**: ISSUE (Base #2).

## 5) In Base #2, tenant adds **one table**: “Customers”

* **Control Plane**

  * `schema_registry`: version bump for Base #2.
* **Data Plane (Base #2)**

  * `runtime_meta.tables + fields` rows for Customers.
  * Physical `data.t_<uuid>` created with chosen columns (e.g., `email`, `name`, etc.).
  * `base_registry.meta_version` advanced.
* **Logs**

  * **portal_log.portal_events**: TABLE_CREATE (Customers), FIELD_CREATE ×N.
  * **runtime_meta.migrations_applied** entries inside Base #2.

## 6) Tenant (Free plan) buys **$5 credit (2,500 runs)**

* **Control Plane**

  * `wallets`: `runs_balance += 2500`, `balance_cents += 500` (optional).
  * `wallet_ledger`: `topup` (+$500, +2500 runs).
  * `subscriptions`: still `Free`.
* **Data Plane**

  * None.
* **Logs**

  * **portal_log.portal_events**: WALLET_TOPUP (amount, runs).
  * **admin_log.admin_events**: only if a staff action (manual adjustment/refund).
  * **notify.alerts / notify.notifications**: not yet; later when low balance or thresholds hit.

---

# During API use and CRUD

* **Every API call**

  * **data_activity.api_access_logs**: (tenant_id, base_id, token_id, route, method, status, latency, ip, ua).
  * **usage_counters.api_calls** (Control Plane) incremented (batched).
* **On successful CRUD**

  * **data_activity.record_events**: one row per INSERT/UPDATE/DELETE (tenant_id, base_id, table_id, record_id, action, actor, token_id).
  * **usage_counters.runs_used** (Control Plane) only for **automation runs**; plain CRUD tallied as `api_calls`. (If you count some writes as “runs”, debit wallet accordingly.)
* **Thresholds & alerts**

  * Metering job writes **notify.quota_snapshots** from `usage_counters`.
  * Detectors open **notify.alerts** (e.g., RUNS_THRESHOLD 80%).
  * Delivery logged in **notify.notifications** (email/slack/webhook).

---

# Where things do **not** live

* **No billing/credits/secrets** in any data plane DBs. Those stay in Control Plane.
* **No schema changes via public API**; all DDL originates from Control Plane → migration runner.

---

# Quick “cheat sheet”

* **Identity, plans, billing, wallets, tokens, usage, base list** → **Control Plane**
  (`tenants`, `users`, `bases`, `api_tokens`, `subscriptions`, `wallets`, `wallet_ledger`, `usage_counters`, `schema_registry`)

* **Runtime schema + data** (per base) → **Data Plane**
  (`runtime_meta.*` + `data.t_<uuid>` tables, join tables, optional `data.history`)

* **Logs**

  * Admin/staff actions → **admin_log.***
  * Tenant portal actions (create base, invite, token issue, top-up) → **portal_log.***
  * API calls + record CRUD → **data_activity.api_access_logs / record_events**
  * Quotas/alerts/notifications → **notify.quota_snapshots / alerts / notifications**

This is exactly the separation that keeps **security tight**, **restores simple** (data+runtime meta together), and **billing/governance auditable** centrally.


