# Database Schema (Proposal)

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.2**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Status: **Part proposal, part as-built.** Corrected at Phase 4 closure, 2026-09-07.
Last updated: 2026-09-10 — the Owner Ledger section is at the end

**How to read this document.** It began as a Phase 0 proposal and has grown as-built
sections beneath it. That mixture is deliberate — the proposal is the record of what was
originally designed, and the difference between the two is often the most useful thing on
the page — but it means **the later section wins** wherever the two disagree:

| Concern | Authoritative section |
|---|---|
| Expenses | *Phase 3 — the expense engine, as built* |
| Revenue, tax resolution, contributions | *Phase 4 — the Revenue Engine, as built* |
| Revenue attachments | *Phase 4 Slice 11 — evidence for a sale, as built* |
| Everything else | the numbered Phase 0/2 sections above |

The header used to say *"No migration has been written or applied."* That was true when it
was written; **71 migrations are applied to `krishna-mis-dev` and every one is accounted
for by a committed file** (`supabase/migrations/LEDGER.md`, D-056, A0). Corrected here
rather than left, because a status line nobody re-reads is how a document starts describing
a system that no longer exists.

Postgres is the system of record; the local Drift/SQLite schema mirrors it with the same
names, plus local-only sync columns.

Revision 1.1 adds: accrual date model, date-effective tax configuration, per-unit
business-day cut-off, multi-entry revenue, mandatory unit scoping for non-Owner roles, and
period locks.

---

## 1. Conventions

| Rule | Value |
|---|---|
| Primary keys | `uuid` (v7, generated on the client) |
| Money | `BIGINT` minor units (paise). `amount_minor`, never `amount`. Never `numeric`, never `float` |
| Currency | `char(3)` default `'INR'`, present for future-proofing |
| Business dates | `DATE` (no time zone), derived per §4 of the spec, **persisted** |
| Capture instant | `captured_at timestamptz` — device clock, forensic only, never authoritative |
| System timestamps | `created_at` / `updated_at timestamptz`, server-assigned, authoritative |
| Tenancy | every table carries `org_id`; every RLS policy keys on it |
| Change tracking | `row_version int not null default 1`, `change_seq bigint` from a shared sequence, set by trigger |
| Soft removal | masters: `archived_at`. Financial documents: `voided_at` + `void_reason`. **No hard deletes** |
| Naming | snake_case, plural tables, `*_id` foreign keys |

Shared trigger on every synced table sets `updated_at = now()`, increments `row_version`,
and assigns `change_seq = nextval('global_change_seq')`.

## 2. Identity, tenancy and authorisation

```sql
organizations (
  id uuid pk, name text not null, legal_name text,
  financial_year_start_month smallint not null default 4,  -- April
  timezone text not null default 'Asia/Kolkata',           -- IANA, org default
  base_currency char(3) not null default 'INR',
  created_at timestamptz, updated_at timestamptz
)

profiles (                       -- 1:1 with auth.users
  id uuid pk references auth.users(id) on delete restrict,
  org_id uuid not null references organizations(id),
  full_name text not null, email citext not null,
  phone text, is_active boolean not null default true,
  created_at, updated_at, row_version, change_seq
)

roles (
  id uuid pk, org_id uuid not null,
  code text not null,             -- owner | manager | accountant | data_entry
  name text not null,
  is_system boolean not null default false,
  requires_unit_scope boolean not null default true,   -- false ONLY for owner
  archived_at timestamptz,
  unique (org_id, code)
)

permissions ( code text pk, category text not null, description text not null )

role_permissions ( role_id uuid, permission_code text, primary key (role_id, permission_code) )

user_roles (
  id uuid pk,
  user_id uuid not null references profiles(id),
  role_id uuid not null references roles(id),
  business_unit_id uuid null references business_units(id),  -- null = all units
  granted_by uuid not null, granted_at timestamptz not null,
  revoked_by uuid, revoked_at timestamptz,
  unique nulls not distinct (user_id, role_id, business_unit_id)
)
```

**Unit scoping is mandatory for non-Owner roles (spec §13.2).** A Manager must not silently
gain both properties. Enforced in the database, not by convention:

```sql
-- trigger on user_roles:
--   if (select requires_unit_scope from roles where id = new.role_id)
--      and new.business_unit_id is null
--   then raise exception 'role requires an explicit business unit scope';
```

A manager covering both properties therefore holds **two explicit grants**, which is
visible, auditable and revocable one property at a time.

**Capability catalogue (initial):**

```
expense.view.own        expense.view.all        expense.create
expense.edit.own        expense.edit.all        expense.void
expense.allocate_periods                         -- cross-period allocation (D-034)
revenue.view            revenue.create          revenue.edit          revenue.void
transaction.correct.beyond_window                -- edit outside the 7-day window
transaction.correct.business_date                -- change a derived business date
attachment.view         attachment.upload
report.view             report.export           report.print
master.view             master.manage           tax.manage
user.manage             role.manage
audit.view              settings.manage
period.close            period.reopen
```

Every capability check is evaluated as `(capability, business_unit_id)`. The resolver
function is `has_capability(cap text, bu uuid)`; a grant with `business_unit_id IS NULL`
(Owner only) satisfies any `bu`. Role names never appear in application conditionals.

## 3. Master data

```sql
business_units (
  id uuid pk, org_id uuid not null references organizations(id),
  code text not null,            -- 'CCR', 'HKI'
  name text not null,            -- 'Crystal Canopy Rooftop'
  kind text not null,            -- 'restaurant' | 'hotel' | 'other'
  timezone text not null default 'Asia/Kolkata',        -- IANA, per property
  business_day_cutoff time not null default '05:00',    -- spec §9, configurable
  sort_order int not null default 0,
  archived_at timestamptz,
  unique (org_id, code)
)
```

Changing `business_day_cutoff` affects only **future** derivations. Existing rows keep
their persisted `business_date`; history is never restated by a configuration change.
Cut-off changes are audited like any other master change.

```sql
departments (
  id uuid pk, org_id uuid not null,
  business_unit_id uuid not null references business_units(id),
  code text not null, name text not null,
  sort_order int, archived_at timestamptz,
  unique (business_unit_id, code)
)

sections (
  id uuid pk, org_id uuid not null,
  department_id uuid not null references departments(id),
  code text not null, name text not null,
  sort_order int, archived_at timestamptz,
  unique (department_id, code)
)

expense_categories (
  id uuid pk, org_id uuid not null,
  section_id uuid not null references sections(id),
  code text not null, name text not null,
  nature text not null default 'operating',   -- operating | payroll | utility | other
  is_shared_by_default boolean not null default false,
  sort_order int, archived_at timestamptz,
  unique (section_id, code)
)

revenue_categories (
  id uuid pk, org_id uuid not null,
  business_unit_id uuid not null references business_units(id),
  code text not null, name text not null,     -- 'Restaurant', 'Nandbhog', 'Room', 'Banquet'
  sort_order int, archived_at timestamptz,
  unique (business_unit_id, code)
)
-- NOTE: no default tax rate column. Tax lives in revenue_tax_rates (§4) so it can vary
-- by category AND by effective date. Nandbhog is a category here, not a business unit
-- (spec §4); promoting it later is a controlled migration (spec §31).

vendors (
  id uuid pk, org_id uuid not null,
  name text not null, gstin text, phone text, address text,
  default_category_id uuid null references expense_categories(id),
  notes text, archived_at timestamptz,
  unique (org_id, lower(name))
)

payment_methods (
  id uuid pk, org_id uuid not null,
  code text not null, name text not null,     -- Cash, UPI, Bank Transfer, Card, Credit
  requires_reference boolean not null default false,
  sort_order int, archived_at timestamptz,
  unique (org_id, code)
)

org_settings ( org_id uuid, key text, value jsonb, updated_by, updated_at,
               primary key (org_id, key) )
-- seeded keys: edit_window_days = 7 (spec §13.3)
```

Masters are **archived**, never deleted. `ON DELETE RESTRICT` on every referencing foreign
key makes orphaned history impossible.

## 4. Tax configuration — date-effective, per category

> **Superseded in its shape by v1.2, and corrected here at Phase 4 closure (2026-09-07).**
> What follows is the Phase 2 model: two resolution dimensions (category and date), a table
> without the four conditional columns, and an exclusion constraint that D-093 found would
> **refuse the approved Room feature** and which was therefore replaced. It is retained as
> the record of what Phase 2 built; it is **not** the shipped shape.
>
> The shipped shape adds `input_basis`, `value_band_id`, `supply_subtype_id` and
> `premises_status_code`; resolves over **five** bounded dimensions, zero-or-exactly-one,
> refusing ambiguity rather than ranking it (D-079, D-094); and snapshots the resolved rule
> onto the **component**, not onto the entry. See *Phase 4 — the Revenue Engine, as built*
> at the end of this document, which is authoritative.
>
> Corrected because §4 read as current and no longer was — the same class of finding as the
> phantom `expense_correct_business_date` (D-127, D-137).

Spec §8.1. **No rate is ever hard-coded in application code.**

```sql
revenue_tax_rates (
  id uuid pk, org_id uuid not null,
  revenue_category_id uuid not null references revenue_categories(id),
  effective_from date not null,
  effective_to   date null,          -- exclusive upper bound; null = still in force
  rate_bp int not null check (rate_bp >= 0 and rate_bp <= 10000),  -- basis points
  treatment text not null check (treatment in ('inclusive','exclusive','none')),
  note text,
  created_by uuid not null, created_at timestamptz not null,
  archived_at timestamptz,

  -- no two active rows may overlap in time for one category
  exclude using gist (
    revenue_category_id with =,
    daterange(effective_from, effective_to, '[)') with &&
  ) where (archived_at is null)
)
```

Requires the `btree_gist` extension. The local SQLite mirror enforces the same
non-overlap rule with a trigger, since SQLite has no exclusion constraints.

Resolution: for a revenue record with business date `d` and category `c`, the applicable
row is the one where `d` falls inside `[effective_from, effective_to)`. The **resolved rate,
treatment and the source row id are snapshotted onto the revenue record** (§6), so editing
or superseding a rate can never retroactively change a historical Net Sales figure.

Restaurant, Nandbhog, Room and Banquet each carry their own rows and are never assumed to
share a treatment. Seeded values are ordinary editable data; a 5% inclusive example is used
only in **sanitised test fixtures**.

There is no GST ledger, no ITC tracking and no filing engine (spec §6.1, §29).

## 5. Expenses — accrual dates, payment state, allocation lines

The document header holds *what was paid and when it was incurred*; allocation lines hold
*what it was for*. Classification (business unit → department → section → category) lives
on the **line**, not the header — this is what makes a shared electricity bill fully
attributable while remaining one document with one attachment.

```sql
expenses (
  id uuid pk,
  org_id uuid not null,
  txn_number text not null,                 -- human reference, unique per org

  -- ── dates: four distinct concepts (spec §5) ────────────────────────────────
  business_date date not null,              -- operational date, cut-off derived
  business_date_source text not null        -- 'derived' | 'manual' | 'corrected'
      check (business_date_source in ('derived','manual','corrected')),
  captured_at timestamptz not null,         -- device instant, NOT authoritative
  accounting_period_start date null,        -- optional service period
  accounting_period_end   date null,
  pnl_date date not null,                   -- COALESCE(accounting_period_end, business_date)
  pnl_period_key text not null,             -- 'YYYY-MM' of pnl_date
  -- pnl_date / pnl_period_key are computed once, server-side, and stored.
  -- No report re-derives them.

  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null default 'INR',
  tax_amount_minor bigint null,             -- informational ONLY (spec §6.1);
                                            -- never used in any V1 calculation

  vendor_id uuid references vendors(id),
  vendor_name_snapshot text,
  reference_no text, notes text,

  -- ── payment (cash view, never the P&L basis) ──────────────────────────────
  payment_status text not null default 'unpaid'
      check (payment_status in ('unpaid','paid')),
  payment_date date null,
  payment_method_id uuid null references payment_methods(id),

  status text not null default 'active',    -- active | voided
  voided_at timestamptz, voided_by uuid, void_reason text,
  approval_state text not null default 'not_required',  -- modelled, disabled in V1

  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  row_version int not null default 1,
  change_seq bigint not null,

  unique (org_id, txn_number),
  check (accounting_period_start is null or accounting_period_end is null
         or accounting_period_start <= accounting_period_end),
  check ((accounting_period_start is null) = (accounting_period_end is null)),
  check (payment_status = 'unpaid'
         or (payment_date is not null and payment_method_id is not null)),
  check (payment_status = 'paid' or (payment_date is null))
)
```

The June-salary case: `business_date = 2026-06-30`,
`accounting_period = 2026-06-01 … 2026-06-30` → `pnl_period_key = '2026-06'` (June P&L),
while `payment_status='paid'`, `payment_date='2026-07-05'` (July cash outflow). One
document, two truthful answers, no double-entry machinery.

```sql
expense_allocations (
  id uuid pk,
  org_id uuid not null,
  expense_id uuid not null references expenses(id) on delete restrict,
  business_unit_id uuid not null references business_units(id),
  department_id uuid not null references departments(id),
  section_id uuid not null references sections(id),
  category_id uuid not null references expense_categories(id),
  amount_minor bigint not null check (amount_minor > 0),
  -- denormalised from the header, maintained by trigger, purely for indexed reporting:
  business_date date not null,
  pnl_date date not null,
  pnl_period_key text not null,
  status text not null,
  notes text,
  line_no int not null,
  unique (expense_id, line_no)
)
```

**Integrity rules enforced in the database, not the UI:**

1. `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` asserting
   `SUM(expense_allocations.amount_minor) = expenses.amount_minor` per expense, checked at
   commit. Header and lines are always written in one transaction.
2. At least one allocation line per expense (same deferred trigger).
3. Trigger validates that `category_id → section_id → department_id → business_unit_id`
   form a consistent chain.
4. Trigger propagates `business_date`, `pnl_date`, `pnl_period_key` and `status` from the
   header to every line.
5. Percentage splits are computed with **largest-remainder distribution** so a split of an
   odd amount still sums exactly to the header total, to the paisa.

### 5.1 Cross-period allocation (optional, D-034)

By default an allocation line sits wholly in its own `pnl_period_key`, and that is the
normal, fast path. Where a cost genuinely spans accounting periods, an authorised user may
split it — and the split hangs off the **allocation line**, so cross-business-unit and
cross-period splitting compose without either knowing about the other.

```sql
expense_period_allocations (
  id uuid pk,
  org_id uuid not null,
  expense_allocation_id uuid not null
      references expense_allocations(id) on delete restrict,
  pnl_period_key text not null,          -- 'YYYY-MM'
  pnl_date date not null,                -- representative date inside that period
  amount_minor bigint not null check (amount_minor > 0),
  basis text not null default 'manual'
      check (basis in ('manual','day_count_suggested')),
  note text,
  line_no int not null,
  created_by uuid not null, created_at timestamptz not null default now(),
  unique (expense_allocation_id, pnl_period_key),
  unique (expense_allocation_id, line_no)
)
```

Enforced in the database, not the UI:

6. `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` asserting, for any allocation
   line that has period rows at all,
   `SUM(expense_period_allocations.amount_minor) = expense_allocations.amount_minor`.
   **No paise may disappear or be duplicated.** A line with no period rows is valid and
   means "wholly in my own period".
7. `pnl_date` must fall inside `pnl_period_key`, and `pnl_period_key` must be a real
   `YYYY-MM`.
8. The `expense.allocate_periods` capability is required to create or change these rows —
   finance and owner roles only, never Manager or Data Entry.
9. **Each target period is checked separately** against `period_locks` and the edit
   window. A split that touches a closed month is refused exactly like any other write
   into it, with the same `period_closed` error.
10. Every insert, change and removal writes an `audit_logs` row.

Day-count proration is **not** implemented. If it is added it must propose a split for
the user to accept or edit — largest-remainder distributed so the proposal already
reconciles exactly — never applied silently (D-034).

```sql
expense_attachments (
  id uuid pk, org_id uuid not null,
  expense_id uuid not null references expenses(id) on delete restrict,
  storage_path text not null,               -- org/{org}/expenses/{expense}/{id}.{ext}
  file_name text not null, mime_type text not null,
  byte_size bigint not null, content_sha256 text not null,
  uploaded_at timestamptz, created_by uuid, created_at timestamptz
)
```

**A row here means an uploaded, hash-verified bill and nothing else** (D-073). It is
written only by `public.attachment_register`, which the client calls *after* the object
is in the bucket, passing the size and SHA-256 it computed locally; the RPC refuses if
they disagree with the stored object. So Postgres — not a Storage bucket listing — is the
financial record of what evidence exists, and there is no `upload_state` column on the
server, because a half-uploaded bill is a client concern and has no canonical existence.

Read authorisation is the same predicate as the header projection, on both the table and
the Storage object: a user who receives a **scoped** view of a shared expense receives
neither. The attachment is the whole bill and states the whole total (D-063).

The client's side of it is a durable eight-state machine on the local
`expense_attachments` table — `staged`, `waitingForExpense`, `pendingUpload`,
`uploading`, `uploaded`, `stagingReclaimed`, `retryNeeded`, `rejected` — recording where
a bill is between the picker and the bucket. Two of those encode rules rather than
progress: `waitingForExpense` because an upload is refused until the server has accepted
the expense it belongs to, and `rejected` because a terminal refusal must never carry a
`nextAttemptAt` — a null there once meant "due now" and retried a refusal for ever. See
`ARCHITECTURE.md` §16.

## 6. Revenue

> **Superseded as a design, 2026-08-31 — and not yet built either way.** The sketch below
> is the Phase 0 flat-record model: one entry, one rate, one gross amount. Phase 4's
> approved plan replaces it with a **document-plus-components** model (D-078 … D-087),
> because one day's revenue in one category can carry more than one tax treatment — room
> tax varying by accommodation value, restaurant treatment depending on a premises status,
> banquet invoicing more than one kind of supply. §6.1 records the approved shape.
>
> The sketch is retained rather than deleted because this document's Phase 0 sections are
> the record of what was originally proposed, and the difference between the two is
> instructive. **Corrected 2026-09-07:** this line used to end "neither is implemented: no
> revenue table exists in `krishna-mis-dev`", which was true when it was written and is
> not now. The document-plus-components model is built, shipped and accepted across
> Slices 2-13; the sketch below is the superseded one.

```sql
-- Phase 0 sketch. Superseded by §6.1. Not built.
revenue_entries (
  id uuid pk, org_id uuid not null,
  txn_number text not null,

  business_date date not null,              -- cut-off derived, persisted
  business_date_source text not null,
  captured_at timestamptz not null,
  pnl_period_key text not null,             -- 'YYYY-MM' of business_date

  business_unit_id uuid not null references business_units(id),
  revenue_category_id uuid not null references revenue_categories(id),

  gross_amount_minor bigint not null check (gross_amount_minor >= 0),
  tax_amount_minor  bigint not null default 0 check (tax_amount_minor >= 0),
  net_amount_minor  bigint not null,

  -- snapshot of the tax configuration actually applied (spec §8.1)
  tax_rate_bp int null,
  tax_treatment text not null check (tax_treatment in ('inclusive','exclusive','none')),
  tax_rate_id uuid null references revenue_tax_rates(id),
  entry_basis text not null check (entry_basis in ('gross','net')),  -- what the user typed

  entry_kind text not null default 'daily_summary'
      check (entry_kind in ('daily_summary','shift','import','correction')),
  source_reference text, notes text,

  status text not null default 'active',
  voided_at timestamptz, voided_by uuid, void_reason text,
  created_by uuid not null, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  row_version int not null default 1, change_seq bigint not null,

  unique (org_id, txn_number),
  check (net_amount_minor = gross_amount_minor - tax_amount_minor),
  check (tax_amount_minor <= gross_amount_minor)
)
```

**No uniqueness constraint on `(business_unit_id, revenue_category_id, business_date)`**
— deliberately (spec §8.2). Multiple records per category per day are valid and are needed
for shift summaries, POS imports and corrections. Reporting sums all `active` rows
deterministically.

The routine UI still treats one daily summary as normal: when the entry screen finds an
existing active record for that unit/category/date it asks the user whether to **edit the
existing entry** or **add another entry**. It never silently creates a duplicate. A
non-unique index supports that lookup:

```sql
create index on revenue_entries (org_id, business_unit_id, revenue_category_id, business_date)
  where status = 'active';
```

### 6.1 The approved Phase 4 model — the planning baseline, since built

> **Correction, 2026-09-05 — `business_date_source` was in this plan and was not built.**
> The column appears in the approved shape below *and* in the Phase 0 sketch above it, and
> the Slice 4 implementation shipped `revenue_entries` **without** it. The omission was
> invisible for six slices, and was found by the Phase 3 expense corrective asking whether
> revenue carried the same provenance (D-140).
>
> So the §8.0-versus-§9 disagreement that decision recorded was really a three-way one, and
> two of the three documents already said yes. It is now built and approved (D-143), with
> two values — `derived` and `corrected` — and no `manual`, because no revenue surface
> offers a trading day at entry. Spec §8.0 is amended to match.
>
> **The rest of this section is still written as a plan, and is stale in that respect.**
> The revenue engine is built and running; `PROJECT_STATUS.md` is the record of what
> exists. The section is left as written rather than rewritten inside a corrective whose
> approved scope is two items.

Approved 2026-08-31 as the planning baseline (D-078 … D-087). **Nothing below existed when
this was written**: no table, no RPC, no migration. Phase 4 has since been implemented —
see the correction above and `PROJECT_STATUS.md`.

**The document and its components.** A revenue entry is a header with one or more
components, exactly as an expense is a header with one or more allocation lines (D-003).
A simple day is one component; a day carrying two tax treatments is two.

```sql
-- PLANNED, NOT BUILT
revenue_entries (
  id uuid pk,                               -- client-generated UUID v7 (D-008)
  org_id uuid not null,
  txn_number text not null,                 -- server-issued KI-REV-26-27-000001 (D-085)
  business_unit_id uuid not null,
  revenue_category_id uuid not null,
  business_date date not null,              -- derived under D-067, persisted
  business_date_source text not null,
  captured_at timestamptz not null,         -- device instant, forensic only
  pnl_period_key text not null,
  entry_kind text not null default 'daily_summary'
      check (entry_kind in ('daily_summary','shift','import','correction')),
  source_reference text, notes text,
  status text not null default 'active',
  voided_at timestamptz, voided_by uuid, void_reason text,
  created_by uuid not null, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  row_version int not null default 1, change_seq bigint not null,
  unique (org_id, txn_number)
)

-- PLANNED, NOT BUILT
revenue_components (
  id uuid pk, org_id uuid not null,
  revenue_entry_id uuid not null references revenue_entries(id) on delete cascade,

  -- What the operator actually typed, and as what (D-080).
  --
  -- `entered_basis` describes THIS application's input, not how the source invoice
  -- presents tax (D-088). The restaurant POS bill adds CGST and SGST to a subtotal and
  -- the management figure is nonetheless the tax-inclusive grand total. The basis comes
  -- from the configured rule, never from the shape of a source document.
  entered_amount_minor bigint not null check (entered_amount_minor >= 0),
  entered_basis text not null
      check (entered_basis in ('inclusive_total','pre_tax')),

  -- what was derived from it, once, half-up, and stored
  gross_amount_minor bigint not null check (gross_amount_minor >= 0),
  tax_amount_minor   bigint not null default 0 check (tax_amount_minor >= 0),
  net_amount_minor   bigint not null,

  -- the rule that produced them, snapshotted (D-017, D-080)
  tax_rule_id uuid not null references revenue_tax_rules(id),
  tax_rate_bp int not null,
  tax_treatment text not null
      check (tax_treatment in ('inclusive','exclusive','none')),

  -- the facts that selected that rule, so the choice is explainable (D-079)
  value_band_min_minor bigint, value_band_max_minor bigint,
  supply_subtype_id uuid references revenue_supply_subtypes(id),
  premises_status_code text,

  check (net_amount_minor = gross_amount_minor - tax_amount_minor),
  check (tax_amount_minor <= gross_amount_minor)
)
```

`SUM(components.gross) = header total` is enforced by a **deferred constraint trigger**,
the same mechanism that holds `SUM(allocations) = expense.amount`. No paisa may disappear
or be duplicated.

**Conditional tax rules (D-079).** `revenue_tax_rates` is extended — or replaced by
`revenue_tax_rules` — with nullable discriminators. A null means the rule does not depend
on that dimension — which means it matches every value of it, so a wildcard and a
specific rule over the same dates are a **conflict**. Resolution is
**zero-or-exactly-one**, deterministic, and **refuses
ambiguity rather than tiebreaking it**:

```sql
-- PLANNED, NOT BUILT
revenue_tax_rules (
  id uuid pk, org_id uuid not null,
  revenue_category_id uuid not null,
  effective_from date not null, effective_to date,

  rate_bp int not null,
  treatment text not null check (treatment in ('inclusive','exclusive','none')),
  -- Not coupled to `treatment` (D-097): inclusive needs the customer total, exclusive
  -- needs the pre-tax figure, and `none` accepts either, because with no tax they are the
  -- same number. There is no third `none` basis.
  input_basis text not null
      check (input_basis in ('inclusive_total','pre_tax')),

  -- nullable discriminators: null = this rule does not depend on that dimension
  value_band_min_minor bigint, value_band_max_minor bigint,
  supply_subtype_id uuid references revenue_supply_subtypes(id),
  premises_status_code text,

  created_by uuid not null, created_at timestamptz not null default now(),
  row_version int not null default 1
)
```

An exclusion constraint refuses two rules that could both match the same facts on the same
date, so ambiguity is impossible to configure rather than merely unlikely to be hit.

**One row per category, always.** Resolution is by `revenue_category_id`; there is no
inheritance between categories and no row shared by two of them. Restaurant and Nandbhog
currently carry the same 5% inclusive treatment and still hold **two independent rows**
(D-089), so a later change to one cannot move the other's Net Sales. A "copy from"
convenience in the Tax screen may create a second row; it must never create a reference.

**Three supporting masters** — `revenue_value_bands` exists because rule identity cannot
serve as band identity: rules are superseded by date and a band is not (D-098). All three
ship empty.

```sql
-- PLANNED, NOT BUILT. Ships EMPTY (D-083).
revenue_supply_subtypes (
  id uuid pk, org_id uuid not null,
  revenue_category_id uuid not null,
  code text not null, label text not null,
  archived_at timestamptz,
  unique (org_id, revenue_category_id, code)
)

-- PLANNED, NOT BUILT. Configured business data, never inferred (D-082).
business_unit_tax_status (
  id uuid pk, org_id uuid not null,
  business_unit_id uuid not null,
  effective_from date not null,
  status_code text not null,
  note text,
  created_by uuid not null, created_at timestamptz not null default now()
)
```

**No rate, band, subtype or status is seeded.** D-043 is unchanged and now covers all four:
the timelines start empty, both applications show *"No rule configured"*, and an
unresolvable or ambiguous rule refuses the save (D-084).

**The reporting projection (D-087). BUILT — Phase 4 Slice 12.** One row per component, so
tax buckets survive into reporting rather than being flattened:

```sql
-- public.revenue_period_contributions — a security_barrier VIEW, not a table (D-157)
create view public.revenue_period_contributions with (security_barrier = true) as
select c.id, c.org_id, c.revenue_entry_id,
       e.business_unit_id, e.revenue_category_id,
       c.supply_subtype_id, c.value_band_id,
       c.value_band_floor_minor   as value_band_min_minor,
       c.value_band_ceiling_minor as value_band_max_minor,
       c.premises_status_code,
       e.business_date, e.business_date as pnl_date, e.pnl_period_key,
       c.gross_amount_minor as gross_minor,
       c.tax_amount_minor   as tax_minor,
       c.net_amount_minor   as net_minor,
       c.tax_rule_id, c.tax_rate_bp, c.tax_treatment, c.entered_basis,
       e.entry_kind, e.txn_number, e.business_date_source, e.voided_at
  from public.revenue_components c
  join public.revenue_entries e on e.id = c.revenue_entry_id
 where e.org_id = public.current_org_id()
   and public.has_capability('revenue.view', e.business_unit_id);
```

**The mirror of `expense_period_contributions` (D-060) — which is itself a view.** The
*physical* table on the expense side is `expense_period_allocations`, and it exists because
a cross-period split is a decision a person made that exists nowhere else (D-034): remove
it and the information is gone.

**A revenue contribution carries no such decision.** Its period is the entry's own stored
`pnl_period_key`, under a CHECK that ties it to the business date; its money is the
component's own stored gross, tax and net. Every field is already canonical somewhere, so
storing a copy would add nothing but the obligation to maintain it — and each of the four
mutations is a way for two copies to disagree. Derived instead, a correction moves the
period because the entry moved, a void removes the effect because the entry is voided, an
edit replaces the figures because the components were replaced, and a replayed mutation has
nothing extra to be idempotent about (D-157).

The same view exists in SQLite at local schema **v15**, column for column, so a report
written against one runs against the other. Neither is writable.

`voided_at` is carried and **not** filtered: the row stays inspectable for audit and every
aggregate excludes it, exactly as the expense projection does (D-006). Phase 4 defines and
exposes this interface; **Phase 5 consumes it**, and Phase 4 builds no P&L.

**Server boundary, following Phase 2/3 exactly.** `authenticated` gets no `SELECT` on
`revenue_entries`; reads go through a `revenue_document` projection. Writes go through
reviewed `SECURITY DEFINER` RPCs — `revenue_create`, `revenue_update`, `revenue_void` —
each re-checking capability, business-unit scope, period lock, edit window and
`base_row_version`, each resolving tax **server-side as the authority**, and each added to
the declared API surface the migration invariant asserts in both directions (D-044).

**Corrected 2026-09-05.** An earlier draft of this paragraph named a fourth RPC,
`revenue_correct_business_date`. No such function exists and none is planned: correcting a
revenue entry's business date is an ordinary `revenue_update`, which re-resolves the tax
against the new date and checks **both** the source and the target period. The expense
side had the same phantom endpoint named in three documents (D-127) and has been corrected
to say the same thing. **One documented contract, one shipped contract.**

## 7. Period control

**Corrected by D-042 (2026-08-28).** The sketch below keyed a lock by a `period_start` /
`period_end` date pair. What is built keys it by `period_key text` in `'YYYY-MM'` form,
matching `BusinessDate.periodKey`, the local SQLite mirror and `PeriodRegistry`. Two
representations of one concept have to be converted at every boundary, and a conversion is
a place to be wrong; the key is also what the authoriser actually asks for, so keying on it
removes a translation from the hot path of every financial write. A month is the only
granularity V1 closes. A non-monthly close would be a new column and a migration, not a
redesign — the lock is still one row per (org, unit, period).

```sql
period_locks (
  id uuid pk, org_id uuid not null,
  business_unit_id uuid null references business_units(id),  -- null = all units
  period_key text not null check (period_key ~ '^[0-9]{4}-[0-9]{2}$'),
  state text not null check (state in ('open','closed')),
  closed_by uuid, closed_at timestamptz,
  reopened_by uuid, reopened_at timestamptz, reopen_reason text,
  row_version int not null default 1, change_seq bigint not null,
  unique nulls not distinct (org_id, business_unit_id, period_key),
  check (state = 'open' or (closed_by is not null and closed_at is not null))
)

period_lock_events (        -- append-only history; a period may close and reopen repeatedly
  id uuid pk, org_id uuid not null,
  period_lock_id uuid not null references period_locks(id),
  action text not null check (action in ('close','reopen')),
  reason text,                     -- MANDATORY for reopen, enforced by trigger
  actor_id uuid not null, occurred_at timestamptz not null default now()
)
```

Enforcement (spec §13.4) lives in the same server-side write path as every other financial
mutation, never in the UI:

- Any create, update, void or business-date correction whose **`pnl_period_key` falls in a
  closed period** is rejected with a distinct `period_closed` error — regardless of the
  caller's row version, so the UI can explain the real reason rather than showing a
  spurious conflict.
- Only `period.reopen` (Owner) can reopen, and the RPC **requires a non-empty reason**.
  Reopening writes a `period_lock_events` row and an `audit_logs` row.
- **No code path reopens a period implicitly.** There is no "auto-unlock on edit", no
  cascade, no silent bypass.

Edit window (spec §13.3), evaluated only while the period is open:

```
allowed if  period is open
        and caller has the operation capability for the row's business unit
        and (   today - business_date <= org_settings.edit_window_days
             or caller has 'transaction.correct.beyond_window' )
```

**`today` is the property's current business date, never `current_date`** (D-067). This
database's session timezone is UTC and the properties are `Asia/Kolkata` with an 05:00
cut-off, so `current_date` lagged the property's own date for half an hour every night and
granted an eighth day it had not been asked to grant. It is derived by
`app.business_date_at(now(), unit.timezone, unit.business_day_cutoff)` — the same rule
`BusinessDate.fromInstant` applies on the client — and for a shared document
`app.expense_window_today` takes the **greatest** such date across the units it charges, so
the window must still be open for every property the bill touches.

The comparison is inclusive of its last day: a business date of D is editable on **D+7**
and refused on **D+8** (D-065). `transaction.correct.beyond_window` lifts the *age* rule
and nothing else — the period lock is checked afterwards and is never bypassed.

## 8. Audit and sync infrastructure

```sql
audit_logs (
  id uuid pk, org_id uuid not null,
  entity_type text not null, entity_id uuid not null,
  action text not null,      -- created | updated | voided | business_date_corrected
                             -- | archived | tax_rate_changed | period_closed
                             -- | period_reopened | role_granted | settings_changed
  before_state jsonb, after_state jsonb, changed_fields text[],
  reason text,
  actor_id uuid not null, actor_name_snapshot text,
  occurred_at timestamptz not null default now(),
  client_platform text, client_version text, device_label text,
  mutation_id uuid
)

processed_mutations (                   -- the idempotency ledger
  mutation_id uuid pk,
  org_id uuid not null, actor_id uuid not null,
  entity_type text not null, entity_id uuid not null, op text not null,
  result jsonb not null,                -- replayed verbatim on duplicate delivery
  processed_at timestamptz not null default now()
)
-- retention: 90 days, purged by scheduled job; far longer than any client retry window
```

`audit_logs`, `period_lock_events` and `processed_mutations` are **append-only**: no
UPDATE or DELETE grant exists for any client role.

Optimistic concurrency (`row_version`) governs update, void, business-date correction and
master archive — see `ARCHITECTURE.md` §5.3. Idempotency (`mutation_id`) and concurrency
(`row_version`) are separate mechanisms and are tested separately.

Deferred, modelled but not enabled in V1: `approval_requests`.

## 9. Indexes

```
expense_allocations  (org_id, pnl_period_key) where status = 'active'
expense_allocations  (org_id, pnl_date) where status = 'active'
expense_allocations  (org_id, business_unit_id, pnl_date)
expense_allocations  (org_id, category_id, pnl_date)
expense_allocations  (org_id, business_date)          -- ledger / edit window
expense_allocations  (expense_id)
expense_period_allocations (expense_allocation_id)
expense_period_allocations (org_id, pnl_period_key)
expenses             (org_id, business_date desc), (org_id, pnl_period_key)
expenses             (org_id, payment_status, payment_date)   -- cash view, unpaid list
expenses             (org_id, vendor_id, business_date), (org_id, status)
revenue_entries      (org_id, business_date), (org_id, pnl_period_key)
revenue_entries      (org_id, business_unit_id, revenue_category_id, business_date)
revenue_tax_rates    (revenue_category_id, effective_from)
period_locks         (org_id, business_unit_id, period_start, period_end)
audit_logs           (org_id, entity_type, entity_id, occurred_at desc)
every synced table   (org_id, change_seq)     -- drives incremental pull
```

The same indexes exist in the local SQLite schema.

## 10. Row Level Security

RLS is enabled on **every** table. Baseline policy shape:

```sql
-- read
using ( org_id = auth_org_id() and has_capability('<entity>.view', business_unit_id) )
-- write: no direct client INSERT/UPDATE on financial tables at all
```

- Financial writes go exclusively through `SECURITY DEFINER` RPCs (`sync_push`), which
  re-check capability, **business-unit scope**, period state, edit window and row version.
  Clients hold no direct write grant on `expenses`, `expense_allocations`,
  `revenue_entries`, `period_locks`, `audit_logs` or `processed_mutations`.
- `auth_org_id()` and `has_capability(text, uuid)` are `STABLE SECURITY DEFINER` helpers
  reading `user_roles` / `role_permissions`.
- **Unit scoping is enforced at allocation-line level.** A manager scoped to CCR sees CCR
  lines only — including only CCR's share of a shared electricity bill, never HKI's.
  Header visibility follows from having at least one visible line.
- Storage buckets are private; object paths embed `org_id` and access is granted by a
  policy matching the caller's org.
- The RLS test suite asserts **both** directions: the permitted user can, and the
  unpermitted user cannot. A policy without a passing deny-test is not considered done.

## 11. Reporting surface

**Corrected 2026-09-07 (Phase 5 Slice 1, finding E4).** This section used to describe two
relations, `v_expense_period_lines` and `v_revenue_lines`, and called the first *"THE
expense reporting surface"*. **Neither has ever existed** — not on `krishna-mis-dev`, not
in any migration, not in `lib/`. The SQL sketched for it referenced an
`expense_allocation_id` column (the real one is `allocation_id`) and an
`a.status = 'active'` predicate on a table that has no status column, so it could not have
run as written. It was a Phase 0 sketch that the built system diverged from, and it sat
here reading like a description of something shipped.

That is the D-127 class — a canonical document naming a surface with nothing behind it —
and this is what actually exists.

### The two reporting projections

```
public.expense_period_contributions   one row per allocation line per accounting period
public.revenue_period_contributions   one row per accepted revenue component
```

Both are `security_barrier` **views**, both are `SELECT`-granted to `authenticated`, and
the base tables under them are ungranted — the projection is the only way in (D-062,
D-116). Locally the same two names exist as SQLite views, column for column, so a report
written against one runs against the other.

Neither performs business arithmetic. No tax extraction, no netting, no margin: engines
return summed paise and everything derived is computed once, in shared Dart (D-020,
spec §21.2).

### They share one vocabulary

| | Expense | Revenue |
|---|---|---|
| Grain | allocation line × accounting period | revenue component |
| Money | `amount_minor` — gross cost, GST included (D-018) | `gross_minor`, `tax_minor`, `net_minor` |
| Period | `pnl_period_key` `YYYY-MM`, `pnl_date` | `pnl_period_key` `YYYY-MM`, `pnl_date` |
| Property | `business_unit_id` | `business_unit_id` |
| Classification | `department_id`, `section_id`, `category_id`, `vendor_id` | `revenue_category_id`, band, subtype |
| Void | `voided_at` — carried, never filtered by the view | `voided_at` — the same |
| Read authority | `may_read_expense` ∧ `expense_visible_units()` | `has_capability('revenue.view', unit)` |

`voided_at` is deliberately carried and not filtered on either side: the aggregate
excludes a voided document and the row stays inspectable (D-006).

### Where the two genuinely differ, and why

**Revenue is derived; expenses are stored.** `revenue_period_contributions` is a view over
the components because a revenue contribution carries no decision of its own — its period
is the entry's stored `pnl_period_key` and its money is the component's own snapshot
(D-157). `expense_period_allocations` is a physical table because a cross-period split
*is* a decision somebody made and exists nowhere else (D-034, D-060);
`expense_period_contributions` is the view over it.

So D-034 is resolved in one place and no report carries a special case: every allocation
line has **at least one** period contribution, generated by the server as a single derived
row when nobody split it, and the sum invariant is enforced at write time. There is no
`pnl_date` on the expense document at all, which is what makes double counting structurally
unavailable rather than avoided by careful queries.

### The canonical-only rule (D-168)

On the **server** every row of both projections is canonical by construction — the tables
hold only what the server accepted. **Corrected 2026-09-08:** the server projections now say
so rather than resting on that observation. `revenue_period_contributions` always carried
`txn_number`; `expense_period_contributions` gained it in `20260907201332`, appended after
`change_seq` because `create or replace view` may only grow at the end. The reporting
boundary filters on it explicitly, so the canonical rule is expressed on the server in the
same words the client uses.

On a **device** the rule is not automatic: a local database legitimately holds documents
this device recorded and the server has never seen, and work retained over a property the
user has lost. The two local views therefore carry `scope_revoked_at` as well, and every
local reporting read applies one shared predicate:

```
voided_at IS NULL  AND  scope_revoked_at IS NULL  AND  txn_number IS NOT NULL
```

Pending, rejected, conflicted and quarantined work contributes **zero** and stays visible in
the transaction surfaces where somebody can act on it. There is no provisional P&L in V1
(D-167).

### Drill-down

`aggregate → expense_period_contributions / revenue_period_contributions → source document`,
through `expense_document` and `revenue_document`. Read-only: reporting navigates to the
transaction surfaces that already exist and reimplements no correction or void path (D-166).

### The reporting boundary (Phase 5 Slice 5, D-184, corrected by D-187)

```
public.reporting_primitives(p_business_unit_ids uuid[], p_from date, p_to date,
                            p_breakdown boolean default false) returns jsonb
        language sql · stable · SECURITY INVOKER · set search_path = public, pg_temp
```

The authoritative primitive sums a P&L is built from, and the comparison point the D-020
parity suite measures the offline cache against. It reads the two projections above and
**nothing else**.

`SECURITY INVOKER` keeps it from returning any row the caller could not already have
selected row by row and added up, so it grants no new **data** access. Two invariants assert
`prosecdef = false`. That is necessary and it is not the authorization contract: D-164 is a
statement about who may read a **report**, and the corrective in `20260908050614` enforces
all three of its capabilities here rather than two (D-187).

| | |
|---|---|
| Reporting authority | `has_capability('reports.view', unit)` — required before either side is considered |
| Revenue side | `reports.view` **and** `has_capability('revenue.view', unit)` |
| Expense side | `reports.view` **and** `has_capability('expense.view.all', unit)` — `expense.view.own` never qualifies (D-164) |
| Consolidated request | more than one property named is the organisation report, and needs the **unscoped** form of all three; two scoped grants do not add up to it |
| Unauthorised side | comes back **null, never zero**, so no caller can render a P&L from a side it may not read (D-163). Missing `reports.view` removes both sides together, so no combination yields half a P&L |
| Snapshot | **one SQL statement**, so both sides come from one snapshot; an invariant refuses a second statement or a `plpgsql` rewrite |
| Date basis | `pnl_date` on both sides, always; an invariant refuses `captured_at`, `payment_date`, `created_at` and `business_date` |
| Arithmetic | summed integer paise cast to `bigint`; no rate, no tax rule, no derived P&L figure |
| Scope | `unnest(coalesce(p_business_unit_ids, '{}'))` — no branch in which an omitted set means the whole organisation |

Returned shape, per requested property: `reports_authorised`, `revenue_authorised`,
`expense_authorised`,
`revenue {gross_minor, tax_minor, net_minor, contributions}`,
`expense {amount_minor, contributions}`, and — when `p_breakdown` — `revenue_by_category`
carrying `tax_treatment`, and `expense_by_hierarchy` carrying department, section and
category. Each side is grouped once at its finest grain and the headline rolls up from those
subtotals, so a breakdown costs no second pass (D-186).

### What does not exist yet

**No P&L screen**, on either platform, and no export, chart or freshness presentation —
Slices 6 to 9. **No `reports.export` or `reports.print` evaluator** — Phase 7, and both stay
on D-139's exemption list; `reports.view` came off it here, because the surface it governs
now exists. **No general reporting pull beyond
the Slice 4 delta**: `ExpensePull.pullOne(expenseId)` still fetches one document by id for
the Review-latest path only.

## 12. Seed and fixture data

Seeded at first run: the organisation, two business units (with timezone and 05:00
cut-off), their departments/sections/categories, revenue categories including Nandbhog
under Crystal Canopy, standard payment methods, and the four system roles with their
capability grants and `requires_unit_scope` flags. Seeds are idempotent, re-runnable, and
carry no credentials.

**No tax configuration row is seeded (D-043, project-lead decision).** No default rate, no assumed
5%, no assumed 18%, no inheritance from another category, property or period, and no fake
production rule. Each revenue category's timeline starts empty and the Tax screen says so
explicitly — *"No rule in force today"* against the category, and *"No tax rule configured.
Revenue recorded for this category will have no tax extracted until one is set."* A
configured zero rate and no configured rule are different facts and are kept apart.

**The client-side seed does not run against a configured backend (D-052).** It exists so
the application is usable with no server at all. With a server, the server is the source of
master data and RLS decides what each user may hold locally.

**No production financial history is seeded, imported, or committed to source control**
(spec §32). Development and tests use sanitised, anonymised fixtures only. A future
Excel/CSV import is a separate controlled workflow writing through the same integrity
rules, marked `entry_kind = 'import'` so it is distinguishable in the audit trail forever.

---

## 13. The API surface, and the boundary around it (as built, 2026-08-28)

### 13.1 What a signed-in client may call

Direct table writes are granted to nobody. Every mutation goes through a
`SECURITY DEFINER` RPC that re-checks capability, unit scope, period state, edit window and
row version, in a transaction. Twenty-four functions are callable by `authenticated`, and
**nothing at all is callable by `anon`**:

| Group | Functions |
|---|---|
| Authority | `my_authority`, `current_org_id`, `has_capability`, `has_capability_anywhere`, `scoped_units_for` |
| Masters | `master_create`, `master_rename`, `master_archive`, `master_restore`, `master_usage` |
| Vendors | `vendor_create`, `vendor_update` |
| Tax | `tax_rule_create`, `tax_rule_supersede`, `tax_rule_archive`, `tax_rule_for` |
| Periods | `period_state`, `period_close`, `period_reopen` |
| Users | `user_provision`, `user_deactivate`, `user_reactivate`, `user_role_grant`, `user_role_revoke` |

The list is declared in exactly one migration and **asserted in both directions**: nothing
unreviewed may be callable, and nothing reviewed may have quietly stopped being callable.
A function that becomes reachable when it should not be is a security defect; one that
silently stops working breaks the application just as completely and is far easier to ship
unnoticed. Adding a function fails the migration until the list names it (D-044).

`app.bootstrap_owner` is checked by name: it hands out ownership, and it must never be
client-reachable.

### 13.2 The RLS helper boundary (D-045)

A policy expression is evaluated with the **querying user's** privileges. `authenticated`
has no `USAGE` on the `app` schema — that is the point of the schema — so a policy calling
`app.current_org_id()` fails for every signed-in user and every table returns 403. It did.
No data was exposed; the application was simply unusable, and no static review had shown
it.

So: `public.current_org_id()` is published and granted to `authenticated`, and policies use
it. `app.current_org_id()` remains for use *inside* `SECURITY DEFINER` functions, which run
as the owner. A migration asserts that no policy references `app.`.

### 13.3 Refusal codes

Every refusal carries a stable code, a machine-readable kind and plain language. The client
maps the kind; it never parses the message, and the message never contains SQL.

| Code | Kind | Meaning |
|---|---|---|
| `KM001` | `missingCapability` | no permission at all |
| `KM002` | `outOfUnitScope` | not for this property |
| `KM003` | `versionConflict` | the record moved — a person resolves this |
| `KM004` | `periodClosed` | the period is closed |
| `KM005` | `editWindowExpired` | beyond the edit window |
| `KM015` | `unknownEntity` | no such record *in this organisation* |
| `KM016` | `appendOnly` | audit and event rows are written once |
| `KM017` | `acknowledgementRequired` | D-038: the rename touches recorded history |

`KM003` is the only one a person can resolve by looking at the record; every other refusal
needs permission, acknowledgement, or abandonment. None is automatically retried — a
refusal is the server's considered answer, and repeating the identical request can only
spin.

### 13.4 Ordering: permission before existence (D-046)

A mutation RPC checks organisation-wide capability **before** it loads the target row.
Seeded master ids are UUID v5 values derived from public code paths (D-040), so anyone can
compute them; loading first would have let an unauthorised caller distinguish
"unknown entity" from "no permission" and enumerate what exists. The precise unit-scoped
check still runs afterwards, because it has to know which property the row belongs to — so
an administrator can still tell the two apart, which is appropriate.

This is the same order the Dart `Authorizer` has always used: permission, then ownership,
then state. The two layers give the same answer for the same reason.

### 13.5 Migration integrity

Every migration the server has applied must exist as a committed file (D-056). This is not
a convention: `my_authority()` was applied to the development project and never committed,
and for a day the repository could not have rebuilt the environment. The live suite now
asserts that every RPC the server exposes is created by a file in `supabase/migrations/`.

---

## Phase 3 — the expense engine, as built (2026-08-29)

Four server tables, four local ones, and a deliberate difference between them.

### Server

```
expenses                     the document: dates, vendor, payment, total, void state
expense_allocations          one line per (business unit → department → section → category)
expense_period_allocations   one row per accounting period per line — the ONLY reporting source
expense_attachments          bill images and invoices, complete-document-only
document_number_counters     one row per (org, kind, financial year); locked while a number is issued
```

**One composite foreign key validates a whole classification.** A line names
`(category_id, section_id, department_id, business_unit_id)` and resolves it against
`expense_categories (id, section_id, department_id, business_unit_id)` — the anchor D-040
put there for exactly this. A Hotel Krishna section under a Crystal Canopy department is
not rejected by a trigger; it does not resolve.

**Two sums, both deferred to COMMIT.** `SUM(lines) = total` and
`SUM(contributions) = line amount` are constraint triggers, so a multi-statement write is
legal in flight and illegal to finish unbalanced. A modified client cannot produce an
expense that does not reconcile, because the transaction will not close.

**Period contributions are always present (D-060).** No deliberate split produces one
derived row covering the whole amount; a split produces one row per period. There is no
document-level `pnl_date` column at all, so nothing can count an amount twice.

**Numbering** is issued by `app.allocate_expense_number` under a row lock on the counter,
after the write is accepted. `max(txn_number) + 1` is the pattern that looks correct and
issues duplicates under load. Clients never reserve a number.

### Reading it back

No client role holds `SELECT` on `public.expenses`. The header is reachable only through
`public.expense_document`, a `security_barrier` view carrying its own scope predicate,
which returns `visible_amount_minor`, `is_complete`, and `total_amount_minor` **only when
every line is visible**. On a two-property bill `total − own share` is the other share, so
the total is withheld rather than hidden (D-062).

`public.expense_period_contributions` is the named projection reporting consumes, so
"what do I sum?" has exactly one answer.

### Local (Drift v7)

A sibling schema, not a copy. `visibility ∈ {complete, scoped}`, a nullable
`document_total_minor` under a check constraint that refuses a scoped row carrying one, and
a non-null `visible_amount_minor`. Withheld lines are absent rather than filtered.
Divergences and their reasons are tabulated in D-062 and in
`lib/data/local/expense_tables.dart`.

### Error vocabulary added

```
KM018 allocation_imbalance    the lines do not add up to the total
KM019 period_imbalance        a period split does not add up to its line
KM020 record_voided           the document is finished and immutable
KM021 edit_window_expired     older than the window, and no beyond-window capability
```

---

## Phase 4 Slice 11 — evidence for a sale, as built (2026-09-06)

### Server

```sql
revenue_attachments (
  id               uuid primary key,          -- client-generated, the identity (D-008)
  org_id           uuid not null,
  revenue_entry_id uuid not null references revenue_entries (id) on delete restrict,

  file_name        text   not null,           -- display metadata only
  content_type     text   not null,
  byte_size        bigint not null check (byte_size > 0),
  content_hash     text   not null,           -- SHA-256; "uploaded" means these matched
  storage_path     text   not null,           -- derived by the server, never accepted

  uploaded_by      uuid not null references profiles (id),
  uploaded_at      timestamptz not null default now(),

  created_at, updated_at, row_version, change_seq,
  constraint revenue_attachments_path_unique unique (storage_path)
)
```

Column for column the expense table, **minus the removal trio**. `removed_at`,
`removed_by` and `remove_reason` are deliberately absent and their absence is asserted by
the migration: V1 ships no attachment removal for either document (D-072a, D-151), and a
second constraint with no writer is what D-145 had to reason about.

**No financial column exists on it.** No amount, no tax, no period key — an attachment
supports a document and is never a source of truth about one, and the local schema is
asserted to carry none either, so the mistake is unavailable rather than avoided.

### The read boundary

```
public.may_read_revenue_attachments(entry_id)   security definer
  = attachment.view held anywhere
  + the entry is in this organisation
  + revenue.view for the entry's own business_unit_id
```

One predicate, three consumers: the `revenue_attachments` read policy, and the Storage
read and write policies for the `revenue/` prefix. The object and its metadata row
therefore cannot disagree about who may have them — the defect 0036 had to fix for
expenses.

**It is not `may_read_expense_attachments`.** That one carries D-063's complete-document
arithmetic because an expense can be partly visible. A revenue entry names one business
unit on its header and has no allocation lines, so there is nothing to be outside anybody's
scope, and copying the arithmetic would have been cargo cult (D-148).

`authenticated` holds `SELECT` and no write grant. `public.revenue_attachment_register` is
the only writer, and the migration asserts that.

### Storage

One private bucket, `expense-attachments` — a historical id for where financial evidence
physically lives — under two path prefixes decided by two independent policy sets:

```
org/{org}/expenses/{expense}/{attachment}.{ext}   → storage_expense_id + may_read_expense_attachments
org/{org}/revenue/{entry}/{attachment}.{ext}      → storage_revenue_id  + may_read_revenue_attachments
```

The two parsers are asserted mutually exclusive at deploy time. No `delete` policy exists
for either prefix: nobody removes evidence through the object API.

A user-supplied file name reaches the object path only as its lower-cased extension, so a
name carrying `../` or a slash cannot become part of the path. The path is **derived** by
the RPC and compared against the caller's, which is refused `KM010` on disagreement.

### The API surface gains three

```
revenue_attachment_register     the only writer of the metadata table
may_read_revenue_attachments    a Storage policy predicate, so it must be reachable (D-045)
storage_revenue_id              the other half of that predicate
```

### Local (Drift v14)

`revenue_attachments`, mirroring `expense_attachments` with the parent pointer changed and
the removal columns absent. Two narrow tables rather than one polymorphic table with an
`owner_id` and a discriminator: the foreign key that makes an orphan impossible is what a
cascade and a purge both rely on.

The shared lifecycle is `AttachmentUploadState`, including `waitingForExpense`, which means
*the parent financial document has not been accepted yet* and keeps its name because it is
a stored value on every device in the field (D-147).

### Refusals reused, none added

`KM002` out of unit scope · `KM009` immutable field · `KM010` impossible structure ·
`KM015` unknown entity · `KM020` record voided · `KM022` attachment limit. The limits are
the product's attachment policy — 5 per document, 10 MB each, 25 MB together — and are the
same numbers for both documents, because they are not a per-document decision.

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260905210226 | `revenue_attachments` |
| 20260905210332 | `api_surface_invariant_revenue_attachments` |

Both verified byte-for-byte by hash against
`supabase_migrations.schema_migrations.statements`.

---

## Phase 4 — the Revenue Engine, as built (2026-09-07)

**Authoritative for revenue.** Where §4, §6 or §6.1 disagree with this section, this section
is what ships. Those sections are retained as the record of what was proposed.

### The canonical model

```
Revenue Entry  (one business unit, one revenue category, one business date)
  └── Revenue Component  (1..n)   the accepted financial facts
        entered amount + basis  ->  gross · tax · net
        the tax rule actually resolved, snapshotted onto the component
        the conditional facts that selected it

Revenue Period Contributions     a DERIVED view over accepted components
                                 never a second writable financial truth source
```

A routine day is **one** component. A day that genuinely carries two treatments is two.
Header totals are **not stored** on either side: Postgres derives them in
`revenue_document`, SQLite in `revenue_entry_totals`, so there is no second copy to drift
(D-078).

### `revenue_tax_rates`, as shipped

The Phase 2 shape in §4 plus the four v1.2 columns, and **without** the exclusion constraint
that section shows:

```sql
revenue_tax_rates (
  id, org_id, business_unit_id, revenue_category_id,
  rate_bp int not null check (rate_bp between 0 and 10000),
  treatment text not null check (treatment in ('inclusive','exclusive','none')),
  input_basis text not null check (input_basis in ('inclusive_total','pre_tax')),  -- A1
  effective_from date not null, effective_to date null,
  value_band_id        uuid null,   -- the four conditional discriminators;
  supply_subtype_id    uuid null,   -- a NULL means "this rule does not depend
  premises_status_code text null,   -- on that dimension", i.e. it matches every value
  note, archived_at, created_by, created_at, updated_at, row_version, change_seq
)
```

**The `EXCLUDE USING gist` constraint in §4 is gone.** D-093 found it would refuse two live
Room bands — which is by construction two rules for one category over the same dates, and
therefore the approved feature. It is replaced by a collision function comparing **tariff
ranges rather than band ids**, a validating trigger, and a transaction-level advisory lock
keyed on `(org, category)` so two concurrent writers cannot commit an ambiguous pair
(D-095). `=` treats two NULLs as non-conflicting, which is the opposite of what a wildcard
means, so one exclusion constraint could never have expressed the doctrine.

### Resolution — five bounded dimensions, zero-or-exactly-one

| Dimension | Where the fact comes from |
|---|---|
| revenue category | the entry |
| effective date | the entry's **business date** (D-067) |
| value band | **selected** by the operator on the component, never derived from its amount (D-094) |
| supply subtype | chosen on the component where a category invoices more than one kind of supply |
| premises tax status | configured per business unit, date-effective, never inferred |

Zero matches refuses. Exactly one resolves. **More than one is a configuration defect and
is refused** — there is no specificity ranking, and a wildcard *collides* with a specific
rule rather than losing to it. A missing rule is never a zero rate, and *"no rule
configured"* stays permanently distinct from a configured `0%` and from a treatment of
`none`.

**Not a general expression language.** A sixth dimension is a migration and a recorded
decision.

### `revenue_entries` and `revenue_components`, as shipped

```sql
revenue_entries (
  id, org_id, txn_number, financial_year,          -- KI-REV-…, server-issued on acceptance
  business_unit_id, revenue_category_id,
  business_date date not null,
  pnl_period_key text not null
      check (pnl_period_key = to_char(business_date, 'YYYY-MM')),
  business_date_source text not null
      check (business_date_source in ('derived','corrected')),   -- D-143, server-owned
  captured_at, entry_kind, source_reference, notes,
  created_by, created_at, updated_by, updated_at,
  voided_at, voided_by, void_reason, row_version, change_seq
)

revenue_components (
  id, org_id, revenue_entry_id,
  entered_amount_minor, entered_basis,             -- what the operator typed, and as what
  gross_amount_minor, tax_amount_minor, net_amount_minor
      check (net_amount_minor = gross_amount_minor - tax_amount_minor),
  tax_rule_id, tax_rate_bp, tax_treatment,         -- the snapshot
  value_band_id, value_band_label,
  value_band_floor_minor, value_band_ceiling_minor,
  supply_subtype_id, supply_subtype_label, premises_status_code,
  created_at
)
```

**There is no `business_date_source` value `manual` for revenue** — no revenue surface
offers a trading day at entry, so the value would have no producer. Expenses have all three.

### `revenue_period_contributions` — derived, not stored

A `security_barrier` **view**, one row per component, scoped by `revenue.view` per business
unit, with the base tables ungranted. The full definition and the reasoning are in §6.1's
successor above and in `ARCHITECTURE.md` §26; what matters here is why it is not a table:

> `expense_period_allocations` is a table because a cross-period split is a **decision a
> person made** that exists nowhere else (D-034). A revenue contribution carries no such
> decision — its period is the entry's stored `pnl_period_key` under a CHECK, its money the
> component's stored gross, tax and net. Storing a copy would add nothing but the
> obligation to maintain it through every correction, edit, void and replay (D-157).

Three exclusions are applied before any filter: `voided_at IS NULL`,
`scope_revoked_at IS NULL`, and **`txn_number IS NOT NULL`** — an unaccepted sale is an
attempt, not revenue (D-158).

### The write boundary

`authenticated` holds **no `SELECT`** on `revenue_entries` or `revenue_components`, and no
write grant on either. Every financial write goes through a reviewed `SECURITY DEFINER`
RPC — and there are exactly three:

```
        revenue_create      revenue_update      revenue_void
```

There is **no** `revenue_correct_business_date` and no fourth endpoint. A business-date
correction is an ordinary `revenue_update` that the server detects by comparing dates,
which then requires `transaction.correct.business_date`, requires a non-blank reason,
writes `business_date_source = 'corrected'` and emits its own audit action. Both the
**source** and the **target** period must be open.

### Local mirror

Drift **v15** — the version that completed it; the schema is at **v17** since Slice 4
added the reporting cache (§13). `revenue_entries`, `revenue_components`,
`revenue_attachments`, the three
reference caches (`revenue_value_bands`, `revenue_supply_subtypes`,
`business_unit_tax_statuses`), `revenue_config_snapshots`, the `revenue_entry_totals` and
`revenue_period_contributions` views, and `ix_revenue_entries_reporting`. Header totals and
contributions are derived on this side too; neither view is writable.

---

## 13. The canonical reporting cache — local schema v17 (Phase 5 Slice 4)

Three **local** tables. Nothing is added to Postgres by this slice: the two contribution
projections gained `change_seq` in `20260907121017` and are otherwise unchanged, and there
is no reporting RPC, no new relation and no new grant (D-177).

These tables are a **different authority class** from the transaction tables beside them
(D-171). Every row is a canonical accepted figure the server returned; nothing local
authors one, nothing local edits one, and a host test over `lib/` asserts that the
synchroniser is the only writer.

```
reporting_revenue_contributions     one accepted revenue component, as reporting received it
  PK (owner_user_id, contribution_id)
  owner_user_id      whose cache this is — never null, never inferred (D-074)
  org_id
  contribution_id    the component's own id on the server; what makes a re-pull idempotent
  revenue_entry_id   the DOCUMENT — the delta unit (D-178)
  business_unit_id · revenue_category_id
  pnl_date · pnl_period_key            stored, never re-derived (D-019, D-067)
  gross_minor · tax_minor · net_minor  integer paise, never recomputed (D-080)
  tax_treatment · tax_rate_basis_points · entered_basis
  value_band_id? · supply_subtype_id?  the conditional identities, where the rule used them
  financial_year     the FY of pnl_date, so a marker and a row match without parsing a date
  document_generation                  the effective generation this row synchronised at
  synced_at

reporting_expense_contributions     one accepted expense period contribution
  PK (owner_user_id, contribution_id)
  expense_id         the DOCUMENT — the delta unit
  allocation_id · business_unit_id · department_id · section_id · category_id · vendor_id?
  pnl_date · pnl_period_key · amount_minor    gross cost incl. GST, no ITC (D-018)
  financial_year · document_generation · synced_at

reporting_coverage_markers          proof that a scope's dataset was completely synchronised
  PK (owner_user_id, business_unit_id, dataset, financial_year)
  dataset            CHECK IN ('revenue', 'expense')
  generation         the DELTA CURSOR this scope resumes from — not a moment (D-188)
  snapshot_id?       WHICH authoritative snapshot these facts jointly represent (v18)
  server_confirmed_at?   that snapshot's own server time, from the same statement
  on_demand          fetched outside normal retention, so pruning can tell the two apart
  updated_at
```

**`snapshot_id` and `generation` are different facts and neither substitutes for the
other** (D-188). The cursor says where the next delta resumes; the snapshot identity says
what moment these facts are. A `change_seq` is allocated when a row is written and becomes
visible when its transaction commits, so it orders work and dates nothing — which is why
`min(generation)` is prohibited as a coherence rule and a permanent regression holds the
prohibition.

Both new columns are **nullable, and that is the honest type**: a marker written before the
Slice 6 corrective cannot prove membership of any snapshot, and null is refused rather than
read as coherent by default.

**Six indexes, every one leading with `owner_user_id`** — two per contribution table for
the period and date reads, and one per table on the document, which is what the
year-bounded delete uses.

### What is deliberately absent

No notes, no attachments, no editable payload, no outbox state, no row version, no mutation
id. This is reporting data, not transaction replication: a device that has synchronised a
colleague's sale can **report** it and cannot open it — the distinction Slice 4 exists to
draw.

There is also **no money-shaped column a client could author**: the amounts arrive from the
projections and the synchroniser is the only writer, so "cache rows must not accept
client-authored financial amounts" is structural rather than remembered.

### Ownership and the purge

`CacheClassification` gains `CacheOwnership.canonicalReportingCache`, its own kind rather
than `businessUnitScoped`, because the two differ on the question a reader actually asks:
*is this financial data?* A cached department is not, and losing it costs a pull. These are
a property's takings and costs.

A confirmed revocation purges all three tables for the revoked property, **unconditionally**
— unlike `scopedFinancialHistory` there is no unsent work to retain, because nothing here
is anybody's attempt. The **marker is deleted first**: a coverage claim standing over rows
about to be removed would tell the reporting engine a property is complete while its
figures disappear underneath.

### Local schema v18 — the smallest change that expresses membership (Slice 6 corrective)

`reporting_coverage_markers.snapshot_id`, and nothing else. The v18 step adds the one column
under the D-144 range guard `from >= 17 && from < 18`, because the table itself is created
at v17 from the current definition.

A **separate snapshot table** was the alternative and was rejected: coherence then needs a
join on every report, the aggregate stops being one comparison, and the saving is bounded
duplication across units × datasets × years, which at this scale is a handful of rows.

The property the column exists to support, stated as the invariant it is: **for one report,
every required business unit × dataset × financial year must prove membership of the same
snapshot before the envelope claims synchronised evidence.** Anything else — including a
set assembled from two successful runs — produces a report with **no** freshness claim and
unchanged figures.

### The migration

The `from < 17` step creates the three tables and their indexes and does nothing else. They
arrive **empty and uncertified**: a migration synchronises nothing, and a device that
upgrades reports `notDownloaded` until it has actually asked the server. Certifying a year
because a schema step ran is exactly the false claim the marker exists to prevent (D-108).

The step is written *before* the `from < 16` step in source order and both still run — the
ordering hazard D-144 records, pinned by a v15 fixture rather than argued.

---

## Phase 5 OA-1 — the Owner Ledger, as built (2026-09-10)

Five server tables — four of them the domain, plus `owner_number_counters` behind the
KI-OWN sequence — and four local ones. A **second financial subsystem**, beside the P&L
rather than inside it: nothing here reaches `expense_period_contributions` or
`revenue_period_contributions`, and there is no path from one to the other (D-190 … D-203,
`ARCHITECTURE.md` §33).

### The tables

```
owners
  id uuid pk (client UUID) · org_id · code (immutable, unique per org) · display_name
  active bool · archived_at
  created_by · created_at · updated_by · updated_at · row_version · change_seq

ownership_shares
  id uuid pk · org_id · owner_id -> owners
  share_basis_points int        -- CHECK between 1 and 10000
  effective_from date           -- CHECK: the FIRST of a month
  effective_to   date null      -- inclusive; CHECK: the LAST of a month
  note text · audit + row_version + change_seq
  EXCLUDE USING gist (org_id =, owner_id =, daterange(from, to, '[]') &&)

owner_family_members
  id uuid pk (client UUID) · org_id · owner_id -> owners
  display_name · relationship_label · is_self bool · may_use_nc bool
  effective_from date · effective_to date null · active bool
  audit + row_version + change_seq
  UNIQUE (org_id, owner_id) WHERE is_self AND active   -- one 'self' per owner
  TRIGGER app.refuse_family_owner_reassignment  -- owner_id is immutable

owner_ledger_entries
  id uuid pk (client UUID v7) · org_id
  txn_number text null · financial_year text null   -- KI-OWN-26-27-000001, server-issued
  owner_id -> owners                 -- the owner the SERVER resolved, snapshotted
  business_unit_id                   -- composite FK to business_units(org_id, id)
  business_date date                 -- derived under D-067, persisted
  pnl_period_key text                -- CHECK: agrees with business_date
  business_date_source text          -- derived | corrected
  captured_at timestamptz            -- device instant, forensic only
  movement_type text                 -- opening_balance | withdrawal | nc_consumption
                                     --  | settlement_paid | manual_adjustment
  direction text                     -- credit | debit
  amount_minor bigint                -- CHECK > 0; the TYPE decides the sign
  family_member_id null              -- who consumed
  collected_by_family_member_id null -- who collected, when that is not the owner
  nc_bill_reference · payment_method_id · reference_number · remarks · reason
  voided_at · voided_by · void_reason
  audit + row_version + change_seq
  UNIQUE (org_id, txn_number)
```

**No balance column anywhere**, on either side. The position is derived from the movements
(D-190), and a structural guard asserts the owner layer computes none.

**No `nature`-style label was added to `expense_categories`**, and its four values are
unchanged. Owner movements belong here, not to a category label.

### The constraints that carry a rule

| | |
|---|---|
| `share_basis_points` between 1 and 10000 | integer basis points; two owners at 5000 total exactly 10000, with no `double` anywhere near it |
| `effective_from` is the first of a month, `effective_to` the last | a settlement period is never split into two ratios |
| the share exclusion constraint | one ratio per owner at a time — no gap, no overlap |
| `amount_minor > 0` | the movement type decides the sign; a negative amount is refused rather than reinterpreted |
| `movement_type <> 'manual_adjustment' OR length(trim(coalesce(reason,''), char(32,9,10,13))) > 0` | an adjustment states why, and **a tab is not a reason** — the explicit whitespace set, because SQLite's one-argument `trim()` strips spaces alone (D-202) |
| `voided_at IS NULL OR (voided_by IS NOT NULL AND` the same trimmed-reason test `)` | a void states why, under the canonical rule (spec §14.1) |
| `pnl_period_key` agrees with `business_date` | the same tie the expense and revenue tables carry |

### RLS and the boundary

Every table is RLS-enabled and **default deny**. No client role holds INSERT, UPDATE, DELETE
or TRUNCATE on any of them — all four privileges, restated rather than the three that let
TRUNCATE through in D-162 — and the only way in is the reviewed RPC set.

Reads are gated on `has_capability_anywhere('owner_ledger.view')` for the two sensitive
tables and are **all-or-nothing**: the policies carry no `business_unit_id` predicate, and a
deploy-time assertion refuses one that acquires it, because an owner's current account spans
both properties and a per-property slice is misleading rather than narrower (D-196).

They were first written `has_unscoped_capability`, which D-025 makes satisfiable by the Owner
and by nobody else — so the Accountant could write and read nothing. That is D-110 and D-116
a third time, closed by `20260909112045` and by a catalogue assertion covering policies and
functions alike (D-200).

### Numbering

`KI-OWN-…` on its own organisation-wide sequence, issued by the server on canonical
acceptance and shared with neither the expense nor the revenue sequence. Offline movements
carry their client-generated UUID v7 until the server accepts them, exactly as expenses and
sales do (D-008, D-085).

### The local half — Drift v19

The same four tables, minus the server-only columns, plus four indexes:
`ix_owner_ledger_owner_period`, `ix_owner_ledger_unit_date`, `ix_owner_family_owner`,
`ix_ownership_shares_owner`.

Classified explicitly (D-070, D-074): the three masters are `organizationGlobal`;
`owner_ledger_entries` is `scopedFinancialHistory` keyed on `business_unit_id` — purged on a
confirmed revocation, sparing the actor's own unsent work. Every table is classified, because
an unclassified one is a decision nobody made.

The v19 step carries the D-144 range guard, and the fresh-database path creates the indexes
too — the omission D-159 caught once already.
