# Database Schema (Proposal)

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.1**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Status: **Proposed — Phase 0 revised.** No migration has been written or applied.
Last updated: 2026-08-30

This is the normalised proposal for review before implementation. Table and column names
may still change; the *shape* is what matters. Postgres is the system of record; the local
Drift/SQLite schema mirrors it with the same names, plus local-only sync columns.

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
> instructive. **Neither is implemented**: no revenue table exists in `krishna-mis-dev`.

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

### 6.1 The approved Phase 4 model — planned, not built

Approved 2026-08-31 as the planning baseline (D-078 … D-087). **Nothing below exists**:
no table, no RPC, no migration. Phase 4 is blocked on verified revenue tax and billing
configuration.

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

  -- what the operator actually typed, and as what (D-080)
  entered_amount_minor bigint not null check (entered_amount_minor >= 0),
  entered_basis text not null
      check (entered_basis in ('inclusive_total','pre_tax','none')),

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
on that dimension; resolution is most-specific-match, deterministic, and **refuses
ambiguity rather than tiebreaking it**:

```sql
-- PLANNED, NOT BUILT
revenue_tax_rules (
  id uuid pk, org_id uuid not null,
  revenue_category_id uuid not null,
  effective_from date not null, effective_to date,

  rate_bp int not null,
  treatment text not null check (treatment in ('inclusive','exclusive','none')),
  input_basis text not null
      check (input_basis in ('inclusive_total','pre_tax','none')),

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

**Two supporting masters.**

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

**The reporting projection (D-087).** One row per component, so tax buckets survive into
reporting rather than being flattened:

```sql
-- PLANNED, NOT BUILT
revenue_period_contributions (
  org_id, business_unit_id, revenue_category_id,
  supply_subtype_id, value_band_min_minor, value_band_max_minor,
  pnl_period_key,
  gross_minor, tax_minor, net_minor
)
```

The mirror of `expense_period_contributions` (D-060). Phase 4 populates it; **Phase 5
consumes it**, and Phase 4 builds no P&L.

**Server boundary, following Phase 2/3 exactly.** `authenticated` gets no `SELECT` on
`revenue_entries`; reads go through a `revenue_document` projection. Writes go through
reviewed `SECURITY DEFINER` RPCs — `revenue_create`, `revenue_update`, `revenue_void`,
`revenue_correct_business_date` — each re-checking capability, business-unit scope, period
lock, edit window and `base_row_version`, each resolving tax **server-side as the
authority**, and each added to the declared API surface the migration invariant asserts in
both directions (D-044).

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

Canonical primitives are defined once (see `ARCHITECTURE.md` §6). Both engines expose the
same shapes; **neither performs business arithmetic** — no tax extraction, no netting, no
margins. Those live in shared Dart.

```
v_expense_period_lines  -- THE expense reporting surface (see below)
v_revenue_lines         -- active revenue entries + unit + category + tax snapshot
-- primitive aggregate queries, parameterised by date basis, range, unit scope, grouping
```

`v_expense_period_lines` resolves D-034 in one place, so no report carries a special
case. Each active allocation line contributes either one row at its own period, or one
row per period allocation:

```sql
-- lines with no period allocations: wholly their own period
select a.*, a.pnl_period_key, a.pnl_date, a.amount_minor
  from expense_allocations a
 where a.status = 'active'
   and not exists (select 1 from expense_period_allocations p
                    where p.expense_allocation_id = a.id)
union all
-- lines split across periods: one row each, summing to the line exactly
select a.*, p.pnl_period_key, p.pnl_date, p.amount_minor
  from expense_allocations a
  join expense_period_allocations p on p.expense_allocation_id = a.id
 where a.status = 'active';
```

Because the sum invariant is enforced at write time, this view always totals to the
source expense — split or not.

Drill-down is always `aggregate → v_expense_lines / v_revenue_lines → source document`.

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
