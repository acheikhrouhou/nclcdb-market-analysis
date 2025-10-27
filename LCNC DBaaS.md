# 💰 Low-Code / No-Code Database — Pricing & Offer Framework (v1.0)

> **Tagline:**
> *Build real tools without engineers. Scale from spreadsheet to workflow — on your terms.*

---

## 🧱 Plans Overview

| Plan           | Monthly (billed annually) | Editors   | Viewers                       | Records/Base   | Storage/Base | Automation Runs / mo | Key Features                                                                                  |
| -------------- | ------------------------- | --------- | ----------------------------- | -------------- | ------------ | -------------------- | --------------------------------------------------------------------------------------------- |
| **Free**       | $0                        | 1–2       | Unlimited                     | **5,000**      | **1 GB**     | **500 runs/mo**      | Basic tables, forms, and automations; public templates; Slack/Zapier integration              |
| **Pro**        | **$16–18 / editor / mo**  | Unlimited | Unlimited                     | **100k+**      | **25–50 GB** | **10,000 runs/mo**   | Advanced views (Kanban, Gallery, Gantt), webhooks, priority support, premium templates        |
| **Business**   | **$35–39 / editor / mo**  | Unlimited | Unlimited + 50 free externals | **250k–500k+** | **100 GB**   | **50,000 runs/mo**   | SSO/SAML, audit logs, row-level security, private templates, admin console, dedicated support |
| **Enterprise** | Custom                    | Unlimited | Unlimited                     | Custom (1M +)  | Custom       | Custom               | Data residency, HIPAA/BAA, VPC deployment, SLAs, SCIM, private marketplace                    |

---

## ⚙️ Add-Ons

| Add-On                 | Price                                        | Details                                                                                                                                                           |
| ---------------------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Automation Credits** | **$5 = 2,500 runs**                          | Pay-as-you-go automation top-up. Runs beyond your monthly limit draw from credits. Auto-refill when balance < $1 (optional). Credits valid **12 months rolling**. |
| **Premium Connectors** | +$10 / editor / mo *(included in Business+)* | Salesforce, HubSpot, Dynamics 365, Jira                                                                                                                           |
| **Extra Storage**      | +$2 / 10 GB                                  | For attachments, media, backups                                                                                                                                   |
| **External Users**     | After 50 free (Business+) → $3 / user / mo   | Ideal for client portals or partner access                                                                                                                        |
| **Seat-Cap Option**    | Fixed price for first 10 editors             | Predictable scaling for agencies                                                                                                                                  |

---

## 🧮 Example ROI Snapshot

| Scenario                          | Monthly Cost    | Automations Used  | Effective $/Run | Comment                     |
| --------------------------------- | --------------- | ----------------- | --------------- | --------------------------- |
| Light user (Free + 1 credit pack) | **$5**          | 2,500 runs        | $0.002 / run    | Semi-pro use; stays prepaid |
| Team (Pro, 5 editors)             | **$80–90/mo**   | 10k runs / editor | $0.0016 / run   | Regular automation workload |
| Business org (10 editors)         | **$350–390/mo** | 50k runs / editor | $0.0008 / run   | Heavy ops; full governance  |
| Enterprise (custom)               | Custom          | 100k + runs       | negotiable      | High-scale, compliance      |

> ⚖️  **Breakeven logic:**
> At ~2,500–5,000 runs/month, prepaid credits make sense.
> Beyond that, the **Pro plan** offers lower effective cost per run + richer features → natural upgrade path.

---

## ❓ FAQ

**Q1: What counts as one “automation run”?**
Each triggered workflow (e.g., “when form submitted → send Slack message”) counts as one run, regardless of how many steps it performs inside your platform.

---

**Q2: What happens when I exceed my included runs?**
You can:

* Auto-purchase a **$5 credit pack (2,500 runs)**, or
* Let the system **pause automations** until credits are added.
  You’ll get alerts at 80 % and at auto-refill.

---

**Q3: Do automation credits expire?**
Credits are valid for **12 months from last use**.
Using any run resets the timer — so light users can keep credits active indefinitely.

---

**Q4: Is storage counted for data or attachments?**
Storage applies only to **file attachments** (images, PDFs, videos).
Text and numeric data inside tables consume negligible space.

---

**Q5: Can I upgrade or downgrade anytime?**
Yes. Plans and credit packs are **modular** — change tiers or add automation packs any time. No setup or cancellation fees.

---

**Q6: What if my team has many viewers or clients?**
Viewers/commenters are **free** on all plans.
Business + tiers include **50 free external users**, then $3/user/mo thereafter.

---

**Q7: What happens if I stop paying?**
Your data remains accessible in **read-only** mode for 90 days.
Automation runs and integrations pause until reactivation.

---

**Q8: Is there a free trial for paid plans?**
Yes — 14 days full access to Pro features (no card required).

---

## 🧭 TL;DR

* **Free forever** for light users (5k records, 1 GB, 500 runs).
* **Pro** for growing teams (100k records, 10k runs, $16–18/editor/mo).
* **Business** for serious ops (250k–500k records, 50k runs, SSO, audit, $35–39/editor/mo).
* **Credits:** **$5 = 2,500 runs**, valid 12 months rolling — ideal bridge for semi-pro use.
* **Upgrade path is natural:** once monthly usage > ~5,000 runs, Pro plan is more economical.

---

Would you like me to extend this into a **visual pricing table + FAQ layout (HTML/React/Tailwind)** so you can drop it into your marketing site or investor deck mockup?

======================================================
Yes please


Done! I dropped a ready-to-embed **React + Tailwind pricing page** with the $5→2,500-runs credits and an FAQ into the canvas. It’s a single-file component with:

* polished 4-tier pricing cards (Pro marked “Most Popular”)
* add-ons block with a credit-wallet explainer
* FAQ accordion
* hero + footer CTAs
* optional “annual vs monthly” toggle (visual only for now)

Want me to:

* wire the monthly billing math,
* add a simple ROI calculator section,
* or restyle it to match your brand tokens (colors, font sizes, spacing)?

what is the filetype of the code ? 
The code is a **React component file**, so its file type should be:

👉 **`.jsx`** (if using plain React)
or
👉 **`.tsx`** (if your project uses TypeScript).

In other words:

* Save it as **`PricingPage.jsx`** in a standard React setup (like Create React App, Next.js, or Vite).
* Or **`PricingPage.tsx`** if your stack supports TypeScript and you prefer typed props.

It’s fully compatible with **Tailwind CSS**, no extra libraries needed — you just need to ensure Tailwind is configured in your build.

Would you like me to add TypeScript types and export it as a `.tsx` version for cleaner integration into a typed codebase?
