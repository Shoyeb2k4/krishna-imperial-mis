# Master Specification — Hospitality Management MIS

Owner: Shoyeb Akhtar
Directive ID: SHOYEB-HOSPITALITY-MIS
Master Spec Version: **1.1**
Status: Active — binding
Last updated: 2026-08-26

This document is the detailed, binding product specification. `CLAUDE.md` imports it.
Where this document and the code disagree, investigate; do not assume either is right.

**Version 1.1** records the owner's decisions on accounting basis, tax configuration,
business-day cut-off, revenue granularity, permission scoping and period close, plus three
architectural corrections (offline reporting parity, void concurrency, encryption key
management). Change log in §30.

---

## 1. Product definition

A premium management MIS and profitability system for two hospitality business units:

1. **Crystal Canopy Rooftop**
2. **Hotel Krishna Imperial**

Management records business income and expenses at operational detail. The system
transforms those entries automatically into daily, weekly, monthly and custom-range
reporting; department, section and category analysis; business-unit and consolidated
profitability; P&L; expense analysis; revenue analysis; trend analysis; and business-unit
comparison.

It is a **management MIS and profitability system**. It is explicitly **not** a statutory
accounting system, not an ERP, not a Tally replacement.

## 2. Platform requirement (non-negotiable)

Genuine installable applications, built with **Flutter + Dart**:

**Android**
- Native-installable signed APK; architecture ready for AAB / Play Store distribution
- Phone-first interface, proper Android application package and lifecycle handling
- Local offline database; native filesystem, share, and camera/gallery capabilities

**Windows**
- Genuine compiled Windows desktop application (`.exe`)
- Installer suitable for a normal end user; Start Menu entry when packaged
- Desktop-optimised UI: keyboard and mouse, dense tables, printing and export

Not a web app, not a PWA, not React/Next.js, not Electron wrapping a website.
No web target is built for this product.
Android and Windows **share the domain and data layers**; only presentation differs.

Changing the client technology requires a documented serious technical blocker,
recorded in `DECISIONS.md`, before the change is made.

## 3. Business hierarchy

```
Organization
  └── Business Unit          (Crystal Canopy Rooftop, Hotel Krishna Imperial)
        └── Department       (F&B / Kitchen, Housekeeping, Front Office, Utilities …)
              └── Section    (Food Production, Beverage, Maintenance …)
                    └── Category (Kirana & Pulses, Electricity, Diesel …)
                          └── Transaction
```

Example: Organization → Crystal Canopy Rooftop → F&B / Kitchen → Food Production →
Kirana & Pulses → ₹8,450 expense on 07 June 2026.

The hierarchy is **configurable master data**, administered in-app. Seed values are
shipped; category structure is never hard-coded into business logic. Historical
transactions must never silently change meaning because a master was edited — see §10.

## 4. Seed master data (initial, not permanent)

### Crystal Canopy Rooftop
Revenue categories: Restaurant, **Nandbhog**.
Expense concepts (from the existing management P&L): Kirana & Pulses; Vegetables &
Fruits; Milk & Dahi; Cylinder & Coal; Water; Paneer / Dairy; Kitchen / F&B payroll;
Other wages; Incentives; Electricity; Other operating expenses.

**Nandbhog (owner decision, V1):** Nandbhog is a **revenue category under Crystal Canopy
Rooftop**, not a separate business unit. It does not receive an independent P&L hierarchy
in V1. Master data is modelled so that promoting it to a business unit later is a
deliberate, auditable migration rather than a schema rewrite — see §31.

### Hotel Krishna Imperial
Revenue categories: Room, Banquet.
Expense concepts: Housekeeping Salary; Front Office Salary; Water; Tanker; Water Cans;
Diesel; Building Expenses; Electricity; Housekeeping Expenses; Maintenance; Payroll;
Other operating expenses.

The owner can add, archive, safely rename, and reorganise masters, subject to the
historical-integrity rules in §10.

## 5. Accounting basis — management accrual (owner decision)

**The P&L is prepared on a management accrual basis.** An expense belongs to the period in
which it was economically incurred, not the period in which cash happened to leave the
bank or the drawer.

> June salary paid on 5 July appears in the **June** operating P&L.

This is **not** double-entry accounting. There is no ledger, no journal, no payables
sub-ledger, no trial balance. It is a management MIS that separates four distinct dates
and states, and uses the right one for each report.

### 5.1 The four concepts, kept separate

| Concept | Field | Meaning |
|---|---|---|
| **Business date** | `business_date` | The operational date the document belongs to, derived under the business-day cut-off (§9). Used for the ledger, daily views and the edit window. |
| **Accounting period** | `accounting_period_start` / `_end` | Optional. The service period a cost covers — a salary month, a rent month, an electricity billing period. |
| **P&L date** | `pnl_date` (derived, stored) | The single date that decides which reporting period the amount lands in. |
| **Payment** | `payment_status`, `payment_date`, `payment_method_id` | Whether and when cash actually moved, and by what means. |

### 5.2 The attribution rule

```
pnl_date = COALESCE(accounting_period_end, business_date)
pnl_period_key = year-month of pnl_date          -- e.g. '2026-06'
```

Both values are computed once, deterministically, and **stored** on the expense and
copied to its allocation lines, so every report indexes on a plain column and no report
re-derives the rule.

The June salary example: `business_date = 2026-06-30`,
`accounting_period = 2026-06-01 … 2026-06-30`, `pnl_date = 2026-06-30` → June P&L;
`payment_status = paid`, `payment_date = 2026-07-05` → July cash outflow.

### 5.2.1 Cross-period allocation (owner decision, D-034)

There is **no universal closing-month rule.** By default the full amount belongs to the
one accounting period above, and that stays the fast, normal workflow — an expense dated
18 June is entirely June's.

Where a cost genuinely spans periods — electricity across two months, an annual
subscription, insurance, rent, an AMC or maintenance contract, a prepaid operating cost —
an **authorised** user may deliberately allocate it across more than one accounting
period:

```
Electricity invoice  ₹60,000     service period 15 May – 14 June
  ├── May   ₹30,000
  └── June  ₹30,000
```

Rules:
- Optional. Absent, the expense behaves exactly as the default above.
- Period allocations attach to an **expense allocation line**, so a shared *and*
  cross-period bill splits on both dimensions without either mechanism special-casing
  the other.
- `SUM(period allocations) = the allocation line's amount`, enforced in the database.
  **No paise may disappear or be duplicated.**
- Gated by the `expense.allocate_periods` capability — finance and owner roles only.
- Every allocation is audited, and each target period is checked against period locks
  and the edit window individually.
- Reporting uses period allocations where they exist, and the expense's own accounting
  period otherwise.

Day-count proration, if added later, is an **explicit helper that proposes a split for
the user to accept or edit** — never a hidden or irreversible assumption.

This is a management attribution mechanism. It is **not** a general ledger: no journal
entries, no prepaid or accrual accounts, no accrual reversals, no statutory accounting
(§29).

### 5.3 What each report uses

| Report | Date basis |
|---|---|
| Operating P&L, profitability, margin, expense analysis, dashboard | `pnl_date` |
| Transaction ledger, daily operations, edit window | `business_date` |
| Cash / payment outflow reporting, unpaid-expense list | `payment_date`, `payment_status` |

Every report states, on screen and in every export, which basis it used. A P&L never
silently mixes bases.

### 5.4 Payment status in V1

`payment_status ∈ { unpaid, paid }`. `paid` requires a `payment_date` and a
`payment_method_id`. Partial payment is **not** modelled in V1 (it is the doorway to a
payables ledger); the schema leaves room for it and the decision is recorded.

Revenue is recorded on its business date. Revenue does not carry a payment/settlement
model in V1.

## 6. Expense model

An expense document carries: id; transaction number; business date; optional accounting
period; derived P&L date and period key; amount; vendor; payment status, payment date and
payment method; reference / invoice number; notes; bill or receipt attachment; created by;
created at; updated by; updated at; sync state; audit metadata; approval state when
approvals are enabled.

Its classification (business unit → department → section → category) and its monetary
split live on **allocation lines**, not on the document header. See §7.

Indian currency formatting is first class: `₹12,36,420`, never `₹1,236,420`.

### 6.1 GST on expenses (owner decision)

The operating expense is the **gross amount actually incurred or paid to the supplier,
including GST**. There is no input-tax-credit accounting, no GST ledger and no statutory
GST support in V1.

An optional, informational `tax_amount_minor` may be recorded on an expense where the user
happens to know it. It is metadata only: it never appears in any V1 calculation, never
reduces the expense, and never implies recoverability. It must not add a required field or
an extra step to the primary expense workflow.

## 7. Shared / split expenses (allocation)

No expense is assumed to belong entirely to one business unit.

```
Electricity Bill        ₹58,000
  ├── Crystal Canopy Rooftop   ₹25,000
  └── Hotel Krishna Imperial   ₹33,000
```

Rules:
- Every expense has **one or more** allocation lines. A simple expense has exactly one
  line at 100%.
- Each line carries its own business unit, department, section, category and amount.
- `SUM(allocation.amount) == expense.amount` is **transactionally enforced** in the
  database, not merely validated in the UI.
- All expense reporting aggregates allocation lines. This is what prevents shared costs
  such as electricity from becoming unattributable.
- Business unit scoping in permissions is enforced at line level, so a unit-scoped manager
  sees only their property's share of a shared bill.

## 8. Revenue model

Manual daily revenue entry, per business unit and revenue category.

```
Business date 15 June 2026
  Crystal Canopy Rooftop   Restaurant  ₹76,450     Nandbhog  ₹8,700
  Hotel Krishna Imperial   Room        ₹52,000     Banquet   ₹28,500
```

A revenue record carries: business date; business unit; revenue category; gross amount;
tax amount; net amount; the tax rate and treatment actually applied; entry basis; notes;
source / reference; entry kind; entered by; audit history.

`net = gross − tax` is enforced by a database check constraint.

### 8.1 Tax configuration (owner decision)

Sales figures are normally recorded **tax-inclusive** (the gross figure the guest paid).
**No rate is hard-coded anywhere in the application.** Tax is resolved from configuration
that varies by:

- **revenue category** — Restaurant, Nandbhog, Room and Banquet are never assumed to share
  a treatment;
- **effective date** — rates change over time, and historical records keep the rate that
  was correct then;
- **treatment** — `inclusive`, `exclusive`, or `none`.

The rate, treatment and configuration row actually used are **snapshotted onto the revenue
record**, so a rate change next year can never retroactively alter last year's Net Sales.

Inclusive extraction, in exact integer paise:

```
tax_minor = round_half_up( gross_minor × rate_bp ÷ (10000 + rate_bp) )
net_minor = gross_minor − tax_minor
```

Exclusive: `tax_minor = round_half_up(net_minor × rate_bp ÷ 10000)`, `gross = net + tax`.
Rounding is half-up, applied once, at the record — never re-derived during aggregation.
Aggregates sum stored paise; they never re-apply a rate to a total.

A 5% inclusive example may be used in **sanitised test fixtures**, because the supplied
June management report behaves that way arithmetically. That is a fixture value, never a
default baked into code. Seeded configuration rows are editable master data.

V1 builds **no statutory GST filing engine**.

### 8.2 Revenue entry granularity (owner decision)

The routine V1 workflow is a simple **Daily Sales Summary**: one figure per revenue
category per business date. The UI does not force shift-level entry.

The **schema deliberately permits multiple revenue records** for the same business unit,
category and business date, to support shift summaries, POS imports, corrections and
distinct source references later. There is therefore **no uniqueness constraint** on
`(business_unit, revenue_category, business_date)`. Each record carries an `entry_kind`
(`daily_summary` · `shift` · `import` · `correction`) and an optional source reference.

Reporting aggregates all active records for the period deterministically. Because the
normal workflow expects one summary per day, the entry screen detects an existing record
for that unit/category/date and asks the user explicitly whether to **edit the existing
entry** or **add another entry** — it never silently creates a duplicate.

## 9. Business date and the business-day cut-off (owner decision)

**Business date is a first-class derived concept and is never the raw device timestamp.**

Each business unit has its own IANA timezone and its own **business-day cut-off**,
configurable, defaulting to **05:00** local property time.

```
local      = instant converted to the unit's timezone
businessDate = local.time < cutoff ? local.date − 1 day : local.date
```

So a rooftop transaction captured at 01:00 on 16 June, in a unit with an 05:00 cut-off,
has business date **15 June**.

Rules:
- The exact capture instant is stored (`captured_at`) alongside the derived
  `business_date`. Both are kept; neither replaces the other.
- `business_date` is persisted, not recomputed at read time, so a later change to a unit's
  cut-off can never silently restate history.
- The user may enter a business date explicitly (recording an expense for a previous day
  is normal); the record notes whether the date was `derived`, `manual` or `corrected`.
- An Owner or suitably privileged finance user may **correct** a business date subject to
  permission and the period/edit rules of §13. Every correction is audited with before and
  after values, actor, timestamp and reason.
- **Server timestamps are authoritative.** The device clock is never trusted for
  `created_at`, `updated_at` or ordering; client-supplied instants are retained as
  forensic metadata only.
- Timezone handling is DST-safe by construction (IANA zones, not fixed offsets), even
  though Asia/Kolkata observes no DST today.

## 10. Reporting

Users enter data once, at daily transaction level. They never re-key weekly or monthly
figures. The reporting engine derives: Today, Yesterday, This Week, Last Week,
This Month, Last Month, Financial Year, Custom Range — all from source transactions.

**Every figure on every dashboard, screen, PDF and spreadsheet comes from one canonical
calculation specification.** See §21 for how that is guaranteed across two physical
execution environments.

### P&L semantics (minimum)

```
Gross Sales
  − GST / applicable tax
  = Net Sales

Net Sales
  − Operating Expenses          (accrual basis, by pnl_date)
  = Operating Profit

Operating Profit ÷ Net Sales × 100 = Operating Profit Margin
```

Zero and negative revenue are handled safely (no division by zero; margin is reported as
not applicable when net sales is zero). The result is labelled **Operating Profit** —
never "net profit" — because the scope excludes depreciation, interest, tax and other
statutory adjustments. Every report states which expenses are included and which date
basis was used.

### Target report shape

For a selected period (e.g. 01–15 June 2026), per business unit: revenue lines by
category → Gross Sales → less GST → Net Sales → expense lines by category → Total
Expenses → Operating Profit → Operating Profit Margin. Plus a consolidated view across
business units.

## 11. Traceability — no dead-end numbers

Every summarised amount drills down to its source, wherever practical:

```
Dashboard → Total Expenses → Category breakdown → "Kirana & Pulses ₹1,50,181"
  → 02 Jun · Sharma Traders · ₹18,400
  → 03 Jun · Metro Wholesale · ₹12,600
  → 05 Jun · Sharma Traders · ₹27,100
      → expense detail: attachment, actor, edit/audit history (subject to permission)
```

A manager must always be able to see where a number came from.

## 12. Master data integrity

Masters: Organization, Business Units, Departments, Sections, Expense Categories,
Revenue Categories, Tax Rates, Vendors, Payment Methods, Users, Roles.

- Masters are **archived**, never deleted, once referenced by history.
- Renaming is permitted only where it does not change meaning. Re-purposing an existing
  category (e.g. renaming "Water" to "Diesel") is prohibited; archive and create new.
- Historical transactions keep their original references intact.
- Tax configuration is versioned by effective date rather than edited in place.

## 13. Users, roles, permissions and period control

### 13.1 Capabilities, not role names

Authorisation is expressed as explicit **capabilities**, always evaluated together with a
**business-unit scope**. Role names never appear in conditional logic in the UI or the
backend. Enforcement is server-authoritative: Postgres RLS plus server-side validation in
RPCs. The client's permission model exists only to shape the UI, and is treated as
untrusted by the backend.

### 13.2 Roles (owner decision)

| Role | Scope | Capability shape |
|---|---|---|
| **Owner** | All business units | Everything: financial reporting, masters, administration, period close and reopen, audit |
| **Manager** | **Assigned units only** | Operational entry of permitted sales and expenses; permitted operational reports |
| **Accountant** | Assigned financial units | Finance transactions, financial reporting, corrections within permission |
| **Data Entry** | Assigned units only | Restricted entry workflows |

**A Manager does not automatically gain access to both properties.** Manager, Accountant
and Data Entry grants **require** an explicit business-unit scope; only the Owner role may
hold an unscoped, all-units grant. This is enforced by a database constraint, not by
convention.

No real production user accounts are created during design phases.

### 13.3 Edit window while a period is open (owner decision)

| Actor | Rule |
|---|---|
| Manager / Data Entry | May edit their permitted transactions for up to **7 calendar days** after the business date, subject to capability |
| Accountant | May correct permitted transactions while the period remains open |
| Owner | May correct permitted transactions while the period remains open |

The window length is configuration (`edit_window_days`, default 7), not a constant in
code. Editing beyond the window requires a distinct capability
(`transaction.correct.beyond_window`). Every correction is audited.

### 13.4 Period close (owner decision)

A period may be **closed**. Once closed:

- financial transactions inside it are **immutable to normal users** — every create, edit,
  void and business-date correction affecting that period is rejected server-side;
- the Owner may **explicitly reopen** it. Reopening is a deliberate action that records
  actor, timestamp and a mandatory reason, and appears in the audit trail;
- **no silent or automatic reopening exists anywhere in the system.**

Period state is part of the financial integrity model and is enforced in the same
server-side path as every other financial write, not in the UI. The complete closing
console may arrive in a later phase; the enforcement model is designed and built into the
write path from the start.

## 14. Audit trail

Every important mutation is auditable: entity, entity id, action, before state, after
state, actor, timestamp, and client/device metadata where appropriate. Covered actions
include expense created / edited / voided, revenue created / edited / voided, allocation
changed, business date corrected, master archived, tax configuration changed, period
closed / reopened, role changed, settings changed.

Financial history is never silently overwritten. Corrections use void/reversal semantics
with a reason, not destructive deletion. Audit records are append-only.

## 15. Attachments

Expenses may carry bill images, receipt images or invoice documents. Capture from the
Android camera or gallery, and from the Windows file picker. Storage is access
controlled with deterministic ownership rules. Attachments created offline are held
locally and uploaded through a robust deferred-upload flow that survives app restart, and
never block their transaction from syncing.

## 16. Export and printing

- **Excel** — professional worksheets genuinely useful for management analysis
- **PDF** — professional management report suitable for saving, sharing and printing
- **Printing** — Windows print workflow

Exports consume the same calculation specification as the screen (§21). Financial formulas
are never duplicated inside export code.

## 17. Dashboard

Date-range selector (Today / This Week / This Month / Custom) driving: Net Sales,
Operating Expenses, Operating Profit, Profit Margin, business-unit comparison, revenue
trend, expense trend, profit trend, top expense categories, department spending,
period-over-period comparison, and drill-down everywhere.

Every chart must answer a management question. No decorative charts.

Every figure is labelled with its **data freshness** (§21.4) so a manager always knows
whether they are looking at locally current information including unsynced entries, or
fully synchronised information.

## 18. Mobile UX (Android)

Android is the operational entry device; optimise for fast daily use.
Navigation: Home · Transactions · central Add action · Reports · More.

Expense entry: Business → Department → Section → Category → Amount → optional
vendor / payment / reference / receipt → Save. Distinguish fields required for integrity
from useful optional metadata; never present a wall of fifteen mandatory fields. Remember
previous selections where safe. Sync status is visible but not intrusive. The Windows UI
is never merely shrunk onto a phone.

Accrual fields stay out of the fast path: business date is pre-filled from the cut-off
rule, and accounting period and payment details are optional, progressive disclosure.

## 19. Windows UX

The management, finance and reporting workstation. Sidebar navigation; dense but readable
financial tables; keyboard and mouse; search; multi-column filtering; sorting; date
filtering; drill-down; Excel and PDF export; printing; larger analytics surfaces.

```
Overview
Transactions   → Expenses · Sales · Other Income (if enabled)
Analytics      → Profit & Loss · Expense Analysis · Revenue Analysis
                 Department Performance · Business Comparison
Reports
Masters        → Business Units · Departments · Sections
                 Expense Categories · Revenue Categories · Tax Rates · Vendors
Administration → Users · Roles & Permissions · Period Close · Audit Log · Settings
```

## 20. Visual design

Must read as premium hospitality management and financial software.

Must **not** look like: a generic AI-generated SaaS dashboard; a template marketplace
theme; a neon fintech app; a blue/purple gradient AI product; a page of rounded stat
cards; a childish mobile app.

Direction: premium hospitality; financial clarity; strong hierarchy; excellent
typography; restrained warm accent; off-white and neutral surfaces; charcoal text;
subtle gold/brass accent; refined borders; deliberate spacing; excellent tables; highly
legible numeric alignment (tabular figures, right-aligned); restrained shadows; minimal
visual noise.

Colour is semantic. Profit and loss indication never relies on colour alone — sign,
symbol or label always accompanies it. Material 3 is a technical substrate only; the
visual identity comes from the project's own design tokens and components, not from
per-screen ad-hoc styling.

## 21. One calculation specification, two execution environments (correction)

The V1.0 phrasing "one aggregation engine in SQL" was wrong for an offline-first product.
An Android device must show updated local financial information **immediately** after an
offline entry, so local execution can never be optional — and a server-side engine will
eventually exist for large historical ranges. Two physical execution environments are
therefore a fact. Pretending otherwise is how two implementations silently diverge.

The requirement is restated correctly:

> **One canonical calculation *specification*, executed by interchangeable engines whose
> agreement is proven by tests, not assumed.**

### 21.1 The specification lives in the domain layer

Report definitions — measures, filters, grouping, period math, tax and margin arithmetic —
are pure Dart over integer paise, with no dependency on Drift, Supabase or Flutter. Every
derived value (Net Sales, Operating Profit, margin, period-over-period delta) is computed
**once, in that shared Dart code**, from primitive aggregates.

### 21.2 Engines only fetch primitives

An engine's entire job is: given a date basis, a date range, a unit scope and a grouping,
return summed integer paise for the matching rows. It performs no business arithmetic.
This shrinks the divergence surface from "the whole P&L" to "select and sum the right
rows", which is exactly what a parity test can pin down.

- `LocalReportingEngine` — SQL against the local encrypted SQLite database. **Default for
  every screen, always available, works with no network.**
- `RemoteReportingEngine` — Postgres RPC. Used for ranges outside local retention, for
  verification, and for future server-side scale.

### 21.3 Parity is enforced by tests, not by hope

A shared, sanitised fixture set is loaded into both engines and identical report requests
are executed against each. The suite asserts **exact equality in integer paise**, and the
export layer is asserted against the same expected values:

```
fixture X →  local SQLite P&L : ₹3,26,862
             Postgres      P&L : ₹3,26,862
             Excel export      : ₹3,26,862
             PDF export        : ₹3,26,862
```

Any divergence in semantics fails the build. Export and print are not separately
implemented formulas; they render the same result objects the screen rendered.

### 21.4 Freshness is shown, never guessed

Offline reporting is never gated on connectivity. Because local results may include
entries not yet on the server, every report and dashboard figure carries an explicit
freshness state:

- **Local — current, includes N unsynced entries**
- **Synced — as of <timestamp>**
- **Local — server has newer changes not yet pulled**

A manager always knows which of the two they are looking at.

## 22. Offline-first

Offline operation is architectural, not an afterthought. A manager records an expense or
sale with no connectivity: it saves locally at once, shows its sync state, queues, and
synchronises safely when the network returns. Retries never duplicate transactions.
Android and Windows converge on the same central state.

Required: globally unique client-generated ids; local capture instant; server timestamps;
sync state; idempotent writes; deterministic retry; an explicit conflict policy; a
tombstone/void strategy; authentication-expiry handling; queue recovery after restart.

Sync UI states: **Synced · Pending Sync · Syncing · Sync Failed · Conflict / Attention
Required**.

"Just retry the API request" is not an acceptable implementation. The actual protocol is
specified in `ARCHITECTURE.md`.

### 22.1 Concurrency semantics for every financial mutation (correction)

The V1.0 claim that a void "cannot conflict" was wrong. A void is a mutation of financial
state and can be issued from a stale view:

> Device A loads Expense v3. Device B edits it to v4. Device A then voids "v3".
> The server must **not** void v4 on the strength of a stale intent.

Therefore **every state-changing financial operation declares explicit concurrency
semantics**, and they are documented and tested:

| Operation | Idempotency | Concurrency |
|---|---|---|
| Create | `mutation_id` | Not applicable — new identity |
| Update | `mutation_id` | **Requires `base_row_version`**; mismatch is rejected as conflict |
| Void | `mutation_id` | **Requires `base_row_version`**; mismatch is rejected as conflict |
| Business-date correction | `mutation_id` | **Requires `base_row_version`** |
| Master archive | `mutation_id` | **Requires `base_row_version`** |
| Period close / reopen | `mutation_id` | Requires the period's current state |

The distinction that matters: **re-delivery of the same mutation** (same `mutation_id`) is
idempotent and replays the stored result; **a different mutation based on a stale version**
is a conflict and is refused. No financial state is ever changed on stale intent.

## 23. Data integrity

Database constraints; foreign keys; appropriate uniqueness constraints; explicit
transaction boundaries; server-authoritative authorisation; exact monetary precision; no
binary floating point for currency; valid date, timezone and cut-off handling;
deterministic aggregation; idempotent sync.

## 24. Security

Treat this as real company financial information. Secure authentication; RLS; least
privilege; no service-role secret in any client binary; secure local token storage;
encrypted local database; attachment access control; no secrets committed to git; input
validation; safe export behaviour; no production credentials in test fixtures; separate
**development / staging / production** environments; full auditability.

### 24.1 Local database encryption and key management (correction)

Encrypted local storage is approved. Key management is documented **per platform**, and
proven on both platforms early in Phase 1 rather than discovered near release.

The encryption key must never be hard-coded, never stored in plaintext configuration,
never committed to git, never logged, and never included in diagnostics, crash reports or
support bundles.

- **Android** — key protected by an Android Keystore–backed secret store.
- **Windows** — key protected by a Windows-native protected-secret mechanism (DPAPI /
  Credential Manager, as provided by the chosen Flutter implementation).

The threat model, the residual risks that remain unmitigated on each platform, and the
logout / key-loss / recovery behaviour are specified in `ARCHITECTURE.md` §8. If the chosen
encryption implementation proves to carry an unacceptable build or maintenance trade-off on
either platform, that is a Phase 1 finding to be recorded and decided — not a late
surprise.

## 25. AI policy

The core MIS works entirely without AI. Financial calculations are deterministic.
AI must never invent revenue, expenses, taxes, profit, transactions, or accounting
classifications. A future AI layer may explain already-verified data ("why did food cost
increase?", "compare this month with last month", "which department is overspending?").
AI is never part of the canonical financial calculation engine.

## 26. Optional approval framework

Architect so expense approval can be switched on later — e.g. expenses above a
configurable amount require owner approval. Keep it modular. Do not let it delay V1
unless the owner requires it.

## 27. Performance

Designed for years of history. No screen downloads the whole database. Pagination;
indexed date queries; business-unit filters; local cache; incremental sync; server-side
aggregation where and when justified. Financial reports stay responsive as data grows.

## 28. V1 scope

Authentication · user profiles · roles, capabilities and business-unit scoping · business
units · departments · sections · categories · tax configuration · vendors · expense entry
with accrual dates and payment status · expense allocation · sales entry · transaction
ledger · attachments · offline-first local persistence · reliable synchronisation ·
period close enforcement · dashboard · daily / weekly / monthly / custom reporting · P&L ·
expense analysis · revenue analysis · business comparison · department analysis · audit
history · Excel export · PDF export · Android production build path · Windows production
build/installer path.

## 29. V1 non-goals

Not without Shoyeb's explicit approval: full double-entry accounting; a payables
sub-ledger or partial-payment tracking; input tax credit / GST ledger; GST filing; Tally
replacement; payroll processing engine; inventory; purchase orders; recipe costing; hotel
PMS; table reservation; POS replacement; Petpooja integration; AI chatbot; AI-generated
financial calculations; predictive analytics; complex approval workflow.

Historical data import is a **separate, controlled workflow**, not part of the normal
transaction path (§32).

Clean extension points are welcome. Speculative modules are not.

## 30. Change log

**v1.1 — 2026-08-26.** Owner decisions recorded: management accrual basis with separated
business / accounting / payment dates (§5); expense GST treated as gross cost, no ITC
(§6.1); date-effective, per-category, inclusive-or-exclusive tax configuration with no
hard-coded rate (§8.1); revenue schema permits multiple entries per category per day while
the routine UI stays a daily summary (§8.2); configurable per-unit business-day cut-off
defaulting to 05:00 with audited correction (§9); Nandbhog remains a Crystal Canopy revenue
category (§4); mandatory business-unit scoping for non-Owner roles (§13.2); 7-day edit
window and explicit period close/reopen (§13.3, §13.4). Architectural corrections: one
calculation specification with parity-tested engines replacing "one SQL engine" (§21);
explicit concurrency semantics for voids and all financial mutations (§22.1); per-platform
encryption key management and threat model (§24.1).

**v1.0 — 2026-08-26.** Initial specification.

## 31. Reserved future migrations

Designed for, but not implemented in V1:

- **Promoting a revenue category to a business unit** (e.g. Nandbhog). Revenue records
  reference business unit and revenue category as separate columns, and allocation lines
  carry their own business unit, so promotion is a controlled data migration plus a
  documented restatement decision — never a schema rewrite. Whether historical figures are
  restated or split from a cut-over date is an owner decision at that time.
- **Partial payments / payables ageing** (§5.4).
- **Proration of costs across accounting periods** (§5.2, open question Q10).
- **Input tax credit** (§6.1).
- **Approval workflow** (§26).

## 32. Historical data import

No production history is imported during design or foundation phases, and **no real
financial data is ever committed to source control**. Development and tests use sanitised,
anonymised fixtures only.

A future Excel/CSV import runs as a separate, controlled workflow with its own staging,
validation, reconciliation report and audit trail. It writes through the same integrity
rules as normal entry — allocation sums, period locks, capability checks — but is a
distinct path, clearly marked in the audit trail (`entry_kind = import`), so it can never
contaminate or bypass the normal transaction-entry path.

## 33. Test strategy

**Unit** — money arithmetic, business-date/cut-off derivation, tax extraction, P&L, date
periods, aggregation, allocation, sync decisions, concurrency decisions, permission and
period-lock decisions.
**Repository / data** — CRUD, filtering, pagination, transactional integrity.
**Database** — constraints, RLS, RPCs, concurrency, period locks.
**Parity** — identical fixtures through local and server engines and both exports (§21.3).
**Flutter** — critical widgets, forms, navigation, error states, offline states.
**End-to-end (minimum)** — login; create expense; create expense offline; sync expense;
create revenue; view dashboard; drill down a report; export P&L; permission refusal;
stale-void rejection; edit refused in a closed period.

Tests assert real business semantics, not line coverage.

## 34. Delivery phases

Phase 0 Discovery & Architecture · 1 Foundation · 2 Masters & Permissions ·
3 Expense Engine · 4 Revenue Engine · 5 Ledger & Reporting Engine ·
6 Dashboard & Analytics · 7 Export & Printing · 8 Production Hardening ·
9 Distribution.

Detail in `PROJECT_STATUS.md`. Never cross a major phase boundary without updating it.

## 35. Open business questions

Questions whose answers materially change product behaviour, accounting semantics, data
integrity or deployment are tracked in `PROJECT_STATUS.md` under **Open questions for
Shoyeb**. They are never resolved by guessing.
