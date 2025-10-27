import React, { useMemo, useState } from "react";

/**
 * LC/NC Database — Pricing & FAQ
 * Single-file React component with Tailwind CSS classes
 *
 * Notes:
 * - Default export is a ready-to-embed component.
 * - No external UI libraries required.
 * - Annual billing toggle is included for visual parity only (prices shown are annual-billed monthly).
 */

const plans = [
  {
    name: "Free",
    price: 0,
    priceNote: "forever",
    editors: "1–2",
    viewers: "Unlimited",
    records: "5,000",
    storage: "1 GB",
    runs: "500 / mo",
    popular: false,
    features: [
      "Basic tables & forms",
      "Public templates",
      "Slack & Zapier integration",
      "CSV/Excel import",
    ],
    cta: "Get started",
  },
  {
    name: "Pro",
    price: 17, // midpoint of $16–18
    priceNote: "/ editor / mo (annual)",
    editors: "Unlimited",
    viewers: "Unlimited",
    records: "100k+",
    storage: "25–50 GB",
    runs: "10,000 / mo",
    popular: true,
    features: [
      "Advanced views (Kanban, Gallery, Gantt)",
      "Webhooks + REST API",
      "Premium templates",
      "Priority support",
    ],
    cta: "Choose Pro",
  },
  {
    name: "Business",
    price: 37, // midpoint of $35–39
    priceNote: "/ editor / mo (annual)",
    editors: "Unlimited",
    viewers: "Unlimited + 50 externals",
    records: "250k–500k+",
    storage: "100 GB",
    runs: "50,000 / mo",
    popular: false,
    features: [
      "SSO/SAML, Audit logs",
      "Row-level security",
      "Admin console",
      "Private templates & marketplace",
    ],
    cta: "Talk to sales",
  },
  {
    name: "Enterprise",
    price: null,
    priceNote: "Custom",
    editors: "Unlimited",
    viewers: "Unlimited",
    records: "1M+ (custom)",
    storage: "Custom",
    runs: "Custom",
    popular: false,
    features: [
      "Data residency, HIPAA/BAA",
      "VPC / BYO cloud",
      "SCIM, advanced RBAC",
      "Premium SLAs & onboarding",
    ],
    cta: "Contact us",
  },
];

const addOns = [
  {
    title: "Automation Credits",
    detail: "$5 = 2,500 runs (12-month rolling validity)",
  },
  {
    title: "Premium Connectors",
    detail: "+$10 / editor / mo (incl. in Business)",
  },
  { title: "Extra Storage", detail: "+$2 / 10 GB" },
  {
    title: "External Users",
    detail: "After 50 free (Business): $3 / user / mo",
  },
  { title: "Seat-Cap Option", detail: "Fixed price for first 10 editors" },
];

const faqs = [
  {
    q: "What counts as an automation run?",
    a: "Each time a workflow trigger fires and executes its actions (e.g., ‘on form submit → send Slack message’) it counts as one run.",
  },
  {
    q: "What happens when I exceed my included runs?",
    a: "You can enable auto top-up: a $5 credit pack (2,500 runs) is purchased when your balance falls below $1. Or pause automations until you manually add credits.",
  },
  {
    q: "Do credits expire?",
    a: "Credits are valid for 12 months from last use. Any usage resets the 12‑month timer (rolling validity).",
  },
  {
    q: "Is storage used for data or attachments?",
    a: "Storage applies to file attachments (images, PDFs, videos). Text and numeric table data use negligible space.",
  },
  {
    q: "Can I switch plans anytime?",
    a: "Yes. Upgrade/downgrade anytime. No setup or cancellation fees.",
  },
  {
    q: "Are viewers and clients free?",
    a: "Viewers/commenters are free on all plans. Business includes 50 external users free, then $3 per external user per month.",
  },
];

function classNames(...args) {
  return args.filter(Boolean).join(" ");
}

export default function PricingPage() {
  const [annual, setAnnual] = useState(true);

  const displayPlans = useMemo(() => {
    // If we wanted to show monthly vs annual, we could adjust here.
    return plans;
  }, []);

  return (
    <div className="min-h-screen w-full bg-gray-50 text-gray-900">
      {/* Hero */}
      <header className="mx-auto max-w-6xl px-4 pt-16 pb-10">
        <div className="text-center">
          <h1 className="text-3xl sm:text-4xl md:text-5xl font-bold tracking-tight">
            More records. More control. Fewer limits.
          </h1>
          <p className="mt-4 text-base sm:text-lg md:text-xl text-gray-600 max-w-3xl mx-auto">
            Build your next data workspace without worrying about hitting walls.
            Start free. Upgrade as your team grows — or your workflows get serious.
          </p>

          {/* Annual toggle (visual) */}
          <div className="mt-6 inline-flex items-center gap-3 rounded-full bg-white shadow p-2">
            <button
              onClick={() => setAnnual(true)}
              className={classNames(
                "px-4 py-1.5 rounded-full text-sm font-medium",
                annual ? "bg-gray-900 text-white" : "text-gray-700"
              )}
            >
              Annual billing
            </button>
            <button
              onClick={() => setAnnual(false)}
              className={classNames(
                "px-4 py-1.5 rounded-full text-sm font-medium",
                !annual ? "bg-gray-900 text-white" : "text-gray-700"
              )}
            >
              Monthly billing
            </button>
          </div>
        </div>
      </header>

      {/* Pricing Cards */}
      <section className="mx-auto max-w-6xl px-4 pb-12">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {displayPlans.map((p) => (
            <div
              key={p.name}
              className={classNames(
                "relative rounded-2xl border bg-white shadow-sm flex flex-col",
                p.popular ? "border-gray-900 ring-2 ring-gray-900" : "border-gray-200"
              )}
            >
              {p.popular && (
                <div className="absolute -top-3 left-1/2 -translate-x-1/2">
                  <span className="rounded-full bg-gray-900 text-white text-xs font-semibold px-3 py-1 shadow">
                    Most Popular
                  </span>
                </div>
              )}

              <div className="p-6 flex-1">
                <h3 className="text-xl font-semibold">{p.name}</h3>
                <div className="mt-3 flex items-baseline gap-1">
                  {p.price === null ? (
                    <span className="text-3xl font-bold">Custom</span>
                  ) : p.price === 0 ? (
                    <span className="text-3xl font-bold">$0</span>
                  ) : (
                    <>
                      <span className="text-3xl font-bold">${p.price}</span>
                      <span className="text-sm text-gray-500">{p.priceNote}</span>
                    </>
                  )}
                </div>

                <ul className="mt-6 space-y-2 text-sm">
                  <li><strong>Editors:</strong> {p.editors}</li>
                  <li><strong>Viewers:</strong> {p.viewers}</li>
                  <li><strong>Records/Base:</strong> {p.records}</li>
                  <li><strong>Storage/Base:</strong> {p.storage}</li>
                  <li><strong>Automation Runs:</strong> {p.runs}</li>
                </ul>

                <div className="mt-6">
                  <h4 className="text-sm font-semibold tracking-wide text-gray-700 uppercase">Includes</h4>
                  <ul className="mt-2 space-y-2 text-sm text-gray-700">
                    {p.features.map((f, i) => (
                      <li key={i} className="flex items-start gap-2">
                        <span className="mt-1 inline-block h-2 w-2 rounded-full bg-gray-900"></span>
                        <span>{f}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>

              <div className="p-6 pt-0">
                <button className={classNames(
                  "w-full rounded-xl px-4 py-2.5 text-center text-sm font-semibold shadow",
                  p.popular ? "bg-gray-900 text-white" : "bg-gray-100 hover:bg-gray-200"
                )}>
                  {p.cta}
                </button>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Add-Ons */}
      <section className="mx-auto max-w-6xl px-4 pb-16">
        <div className="rounded-3xl bg-white border border-gray-200 shadow-sm p-6">
          <h3 className="text-xl font-semibold">Add‑Ons</h3>
          <p className="mt-1 text-gray-600 text-sm">Extend capacity without switching plans.</p>
          <div className="mt-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {addOns.map((a) => (
              <div key={a.title} className="rounded-2xl border border-gray-200 p-4">
                <div className="text-sm font-semibold">{a.title}</div>
                <div className="mt-1 text-sm text-gray-600">{a.detail}</div>
              </div>
            ))}
          </div>

          {/* Credit wallet explainer */}
          <div className="mt-6 rounded-2xl bg-gray-50 border border-dashed border-gray-300 p-4">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div>
                <div className="text-sm font-semibold">Automation Credits</div>
                <p className="text-sm text-gray-600">
                  $5 buys 2,500 runs. Credits auto‑refill when your balance drops below $1 (optional). Credits are valid for 12 months from last use.
                </p>
              </div>
              <div className="flex items-center gap-2">
                <div className="h-2 w-40 bg-white rounded-full shadow-inner overflow-hidden">
                  <div className="h-full w-2/3 bg-gray-900" />
                </div>
                <span className="text-xs text-gray-700">1,650 / 2,500 runs left</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="mx-auto max-w-4xl px-4 pb-24">
        <h3 className="text-2xl font-bold text-center">FAQ</h3>
        <div className="mt-8 divide-y divide-gray-200 rounded-3xl border border-gray-200 bg-white shadow-sm">
          {faqs.map((f, idx) => (
            <Disclosure key={idx} q={f.q} a={f.a} />
          ))}
        </div>
      </section>

      {/* Footer CTA */}
      <footer className="mx-auto max-w-6xl px-4 pb-20">
        <div className="rounded-3xl bg-gray-900 text-white p-8 sm:p-10 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6 shadow-lg">
          <div>
            <h4 className="text-xl font-semibold">Ready to build without limits?</h4>
            <p className="text-sm text-gray-300 mt-1">Start free. Upgrade when your workflows go pro.</p>
          </div>
          <div className="flex gap-3">
            <button className="rounded-xl bg-white text-gray-900 px-4 py-2.5 text-sm font-semibold shadow">
              Get started free
            </button>
            <button className="rounded-xl bg-gray-800 text-white px-4 py-2.5 text-sm font-semibold border border-gray-700">
              Talk to sales
            </button>
          </div>
        </div>
      </footer>
    </div>
  );
}

function Disclosure({ q, a }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="px-5 py-4">
      <button
        className="w-full flex items-center justify-between text-left"
        onClick={() => setOpen(!open)}
      >
        <span className="text-sm font-semibold">{q}</span>
        <svg
          className={classNames(
            "h-5 w-5 transition-transform",
            open ? "rotate-180" : "rotate-0"
          )}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      <div
        className={classNames(
          "text-sm text-gray-600 pr-8 transition-all",
          open ? "mt-2 opacity-100" : "max-h-0 overflow-hidden opacity-0"
        )}
      >
        {a}
      </div>
    </div>
  );
}
