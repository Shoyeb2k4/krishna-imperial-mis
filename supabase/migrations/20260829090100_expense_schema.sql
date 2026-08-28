-- ─────────────────────────────────────────────────────────────────────────────
-- 0026 · The expense document, its allocation lines, and their period contributions
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.1 · Phase 3
--
-- Four structural commitments, each of which removes a class of error rather than
-- guarding against it.
--
-- 1 · CLASSIFICATION LIVES ON THE LINES (D-003). The document is what the vendor gave
--     you: a date, a supplier, a total, a payment, an attachment. Where the money is
--     charged is a property of each line. A ₹200 grocery bill has one line; a shared
--     electricity bill has two. One model, one reporting path, and no expense that can
--     fall outside the hierarchy.
--
-- 2 · ONE COMPOSITE KEY VALIDATES A WHOLE CLASSIFICATION (D-040). A line names
--     (business_unit, department, section, category) and a single foreign key resolves
--     the entire tuple against `expense_categories`. A section from Hotel Krishna under a
--     Crystal Canopy department is not rejected by a trigger — it does not resolve.
--
-- 3 · PERIOD CONTRIBUTIONS ARE THE ONLY REPORTING SOURCE (D-060). Every line has at
--     least one, always. An ordinary line gets a single derived row for its whole amount;
--     a cost that genuinely spans months gets one row per month, and an authorised person
--     put them there. Reporting sums `expense_period_allocations` and nothing else, so a
--     ₹60,000 line split ₹30,000 May / ₹30,000 June contributes exactly that and cannot
--     also contribute ₹60,000 against a document-level date. There is no second place the
--     amount lives, so double counting is not a query mistake anyone can make.
--
-- 4 · THE TWO SUMS ARE DEFERRED CONSTRAINTS, NOT VALIDATION. `SUM(lines) = total` and
--     `SUM(contributions) = line amount` are checked at COMMIT, so a multi-statement
--     write is legal in flight and illegal to finish unbalanced. A modified client cannot
--     produce an expense that does not reconcile, because the transaction will not close.
--
-- Immutability: financial history is corrected by void and re-entry, never by deletion
-- (D-006). No client role is granted DELETE on anything here, and a voided document is
-- refused every further update by trigger.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── The document ─────────────────────────────────────────────────────────────
create table if not exists public.expenses (
  id                       uuid primary key,   -- client-generated UUID v7 (D-008)
  org_id                   uuid        not null references public.organizations (id),

  -- Allocated by the server, once, after the record is accepted. Never reserved by a
  -- client: two devices offline for a week would both claim the same number.
  txn_number               text,
  financial_year           smallint,           -- the opening year, e.g. 2026 for 26-27

  business_date            date        not null,
  business_date_source     text        not null default 'derived'
                             check (business_date_source in ('derived','manual','corrected')),

  -- The optional service period the cost covers. Both ends or neither.
  accounting_period_start  date,
  accounting_period_end    date,

  total_amount_minor       bigint      not null check (total_amount_minor > 0),

  vendor_id                uuid references public.vendors (id) on delete restrict,
  payment_status           text        not null default 'unpaid'
                             check (payment_status in ('unpaid','paid')),
  payment_date             date,
  payment_method_id        uuid references public.payment_methods (id) on delete restrict,
  reference_number         text,
  notes                    text,

  -- Informational only (D-018). Never reduces the expense, never enters a calculation,
  -- never implies recoverability.
  tax_amount_minor         bigint check (tax_amount_minor is null or tax_amount_minor >= 0),

  created_by               uuid        not null references public.profiles (id),
  captured_at              timestamptz not null,   -- device instant; forensic only (§9)

  voided_at                timestamptz,
  voided_by                uuid references public.profiles (id),
  void_reason              text,

  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  row_version              integer     not null default 1,
  change_seq               bigint      not null default nextval('app.global_change_seq'),

  constraint expenses_period_both_or_neither
    check ((accounting_period_start is null) = (accounting_period_end is null)),
  constraint expenses_period_ordered
    check (accounting_period_start is null
           or accounting_period_start <= accounting_period_end),
  -- Paid states when and by what means; unpaid states neither (spec §5.4).
  constraint expenses_payment_complete
    check ((payment_status = 'paid'
            and payment_date is not null and payment_method_id is not null)
        or (payment_status = 'unpaid'
            and payment_date is null and payment_method_id is null)),
  constraint expenses_void_has_reason
    check (voided_at is null
           or (voided_by is not null and length(btrim(coalesce(void_reason,''))) > 0)),
  -- Issued together or not at all, and unique within the organisation's financial year.
  constraint expenses_number_complete
    check ((txn_number is null) = (financial_year is null)),
  constraint expenses_number_unique unique (org_id, txn_number)
);

comment on column public.expenses.txn_number is
  'KI-EXP-26-27-000001. Organisation-wide and never prefixed with a property, because one '
  'expense may be allocated across both. Allocated server-side after acceptance.';

-- ── The allocation lines ─────────────────────────────────────────────────────
create table if not exists public.expense_allocations (
  id                uuid primary key,
  org_id            uuid   not null,
  expense_id        uuid   not null references public.expenses (id) on delete restrict,

  business_unit_id  uuid   not null,
  department_id     uuid   not null,
  section_id        uuid   not null,
  category_id       uuid   not null,

  amount_minor      bigint not null check (amount_minor > 0),

  -- The transaction-time label snapshot (D-035). Reports show the current name; the
  -- document and the audit trail can always show what was on screen when it was entered.
  category_label    text   not null,

  sort_order        integer not null default 0,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  row_version       integer     not null default 1,
  change_seq        bigint      not null default nextval('app.global_change_seq'),

  -- One key, the whole classification. Nothing else needs to be checked.
  constraint expense_allocations_classification_fk
    foreign key (category_id, section_id, department_id, business_unit_id)
    references public.expense_categories (id, section_id, department_id, business_unit_id)
    on delete restrict,

  -- The anchor a period contribution references, carrying the unit down with it so a
  -- contribution can be scoped without a join.
  constraint expense_allocations_chain_key unique (id, expense_id, business_unit_id)
);

-- ── The period contributions ─────────────────────────────────────────────────
create table if not exists public.expense_period_allocations (
  id                       uuid primary key,
  org_id                   uuid   not null,
  expense_id               uuid   not null,
  allocation_id            uuid   not null,
  business_unit_id         uuid   not null,

  accounting_period_start  date   not null,
  accounting_period_end    date   not null,
  amount_minor             bigint not null check (amount_minor > 0),

  -- The one date profitability indexes on, and its month. Computed once, stored, never
  -- re-derived at read time — a later configuration change must not restate history
  -- (D-019, spec §5.2).
  pnl_date                 date   not null,
  pnl_period_key           text   not null
                             check (pnl_period_key ~ '^[0-9]{4}-[0-9]{2}$'),

  -- Whether the default rule produced this, or a person decided it. The arithmetic does
  -- not care; the capability check, the interface and the audit trail all do.
  is_derived               boolean not null default true,

  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  row_version              integer     not null default 1,
  change_seq               bigint      not null default nextval('app.global_change_seq'),

  constraint expense_period_allocations_line_fk
    foreign key (allocation_id, expense_id, business_unit_id)
    references public.expense_allocations (id, expense_id, business_unit_id)
    on delete restrict,
  constraint expense_period_allocations_ordered
    check (accounting_period_start <= accounting_period_end),
  -- The stored attribution must agree with the period it claims. Belt and braces: the
  -- RPC computes both, and the database refuses a row where they disagree.
  constraint expense_period_allocations_pnl_consistent
    check (pnl_date = accounting_period_end
           and pnl_period_key = to_char(pnl_date, 'YYYY-MM'))
);

-- ── Attachments ──────────────────────────────────────────────────────────────
create table if not exists public.expense_attachments (
  id             uuid primary key,
  org_id         uuid   not null,
  expense_id     uuid   not null references public.expenses (id) on delete restrict,

  file_name      text   not null,
  content_type   text   not null,
  byte_size      bigint not null check (byte_size > 0),

  -- SHA-256 of the bytes. The upload is confirmed only when the server's copy hashes to
  -- the same value; "the request returned 200" is a weaker claim.
  content_hash   text   not null,
  storage_path   text   not null,

  uploaded_by    uuid   not null references public.profiles (id),
  uploaded_at    timestamptz not null default now(),

  -- A void does not delete attachments (project-lead decision): the document remains,
  -- and so does its evidence. Removing one is its own audited act.
  removed_at     timestamptz,
  removed_by     uuid references public.profiles (id),
  remove_reason  text,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  row_version    integer     not null default 1,
  change_seq     bigint      not null default nextval('app.global_change_seq'),

  constraint expense_attachments_removal_has_reason
    check (removed_at is null
           or (removed_by is not null
               and length(btrim(coalesce(remove_reason,''))) > 0)),
  constraint expense_attachments_path_unique unique (storage_path)
);

-- ── The two sums, deferred to COMMIT ─────────────────────────────────────────
create or replace function app.assert_expense_balances()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense uuid := coalesce(new.expense_id, old.expense_id);
  v_header  bigint;
  v_lines   bigint;
begin
  select e.total_amount_minor into v_header
    from public.expenses e where e.id = v_expense;
  -- The document may have gone in the same transaction; nothing left to balance.
  if v_header is null then return null; end if;

  select coalesce(sum(a.amount_minor), 0) into v_lines
    from public.expense_allocations a where a.expense_id = v_expense;

  if v_lines <> v_header then
    perform app.refuse('KM018', 'allocation_imbalance',
      'The allocation lines do not add up to the expense total.',
      jsonb_build_object('expense_id', v_expense,
                         'total_minor', v_header,
                         'allocated_minor', v_lines));
  end if;
  return null;
end;
$$;

create or replace function app.assert_line_periods_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line   uuid := coalesce(new.allocation_id, old.allocation_id);
  v_amount bigint;
  v_parts  bigint;
begin
  select a.amount_minor into v_amount
    from public.expense_allocations a where a.id = v_line;
  if v_amount is null then return null; end if;

  select coalesce(sum(p.amount_minor), 0) into v_parts
    from public.expense_period_allocations p where p.allocation_id = v_line;

  -- Zero means the line has no contributions at all, which is its own failure: every
  -- line reports somewhere, or its amount is invisible to every report (D-060).
  if v_parts <> v_amount then
    perform app.refuse('KM019', 'period_imbalance',
      'The accounting-period split does not add up to the line amount.',
      jsonb_build_object('allocation_id', v_line,
                         'line_minor', v_amount,
                         'allocated_minor', v_parts));
  end if;
  return null;
end;
$$;

-- The same assertion, entered from the document rather than from a line. Editing a
-- total from ₹58,000 to ₹59,000 has to be caught even though no line row changed.
create or replace function app.assert_expense_balances_header()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lines bigint;
begin
  select coalesce(sum(a.amount_minor), 0) into v_lines
    from public.expense_allocations a where a.expense_id = new.id;

  if v_lines <> new.total_amount_minor then
    perform app.refuse('KM018', 'allocation_imbalance',
      'The allocation lines do not add up to the expense total.',
      jsonb_build_object('expense_id', new.id,
                         'total_minor', new.total_amount_minor,
                         'allocated_minor', v_lines));
  end if;
  return null;
end;
$$;

-- Deferred, so a multi-statement write is legal in flight and illegal to finish
-- unbalanced. Row-level and INITIALLY DEFERRED: the check runs once per changed row at
-- COMMIT, after every statement in the transaction has had its say.
drop trigger if exists expense_allocations_balance on public.expense_allocations;
create constraint trigger expense_allocations_balance
  after insert or update or delete on public.expense_allocations
  deferrable initially deferred
  for each row execute function app.assert_expense_balances();

drop trigger if exists expenses_balance on public.expenses;
create constraint trigger expenses_balance
  after insert or update on public.expenses
  deferrable initially deferred
  for each row execute function app.assert_expense_balances_header();

drop trigger if exists expense_period_allocations_balance on public.expense_period_allocations;
create constraint trigger expense_period_allocations_balance
  after insert or update or delete on public.expense_period_allocations
  deferrable initially deferred
  for each row execute function app.assert_line_periods_balance();

-- A line changing its amount must re-check its own contributions too, not only the
-- header — otherwise editing ₹25,000 to ₹26,000 would leave a ₹25,000 split behind.
create or replace function app.assert_line_periods_from_line()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount bigint;
  v_parts  bigint;
begin
  select coalesce(sum(p.amount_minor), 0) into v_parts
    from public.expense_period_allocations p where p.allocation_id = new.id;
  v_amount := new.amount_minor;
  if v_parts <> v_amount then
    perform app.refuse('KM019', 'period_imbalance',
      'The accounting-period split does not add up to the line amount.',
      jsonb_build_object('allocation_id', new.id,
                         'line_minor', v_amount,
                         'allocated_minor', v_parts));
  end if;
  return null;
end;
$$;

drop trigger if exists expense_allocations_period_balance on public.expense_allocations;
create constraint trigger expense_allocations_period_balance
  after insert or update on public.expense_allocations
  deferrable initially deferred
  for each row execute function app.assert_line_periods_from_line();

-- ── A voided document is immutable ───────────────────────────────────────────
create or replace function app.refuse_voided_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- The void itself is the one update allowed to set voided_at.
  if old.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This expense has been voided. Corrections are made by entering a new expense.',
      jsonb_build_object('expense_id', old.id));
  end if;
  return new;
end;
$$;

drop trigger if exists expenses_voided_immutable on public.expenses;
create trigger expenses_voided_immutable
  before update on public.expenses
  for each row execute function app.refuse_voided_mutation();

-- ── Server-authoritative stamping ────────────────────────────────────────────
drop trigger if exists expenses_touch on public.expenses;
create trigger expenses_touch before insert or update on public.expenses
  for each row execute function app.touch_row();

drop trigger if exists expense_allocations_touch on public.expense_allocations;
create trigger expense_allocations_touch
  before insert or update on public.expense_allocations
  for each row execute function app.touch_row();

drop trigger if exists expense_period_allocations_touch on public.expense_period_allocations;
create trigger expense_period_allocations_touch
  before insert or update on public.expense_period_allocations
  for each row execute function app.touch_row();

drop trigger if exists expense_attachments_touch on public.expense_attachments;
create trigger expense_attachments_touch
  before insert or update on public.expense_attachments
  for each row execute function app.touch_row();

-- ── Grants ───────────────────────────────────────────────────────────────────
-- Postgres grants EXECUTE on every new function to PUBLIC. A trigger function is not a
-- client-callable thing, and "it would not be useful to call" is a weaker claim than
-- "it cannot be called" — which is what the API-surface invariant insists on, and what
-- it caught here (D-044).
revoke all on function app.assert_expense_balances()        from public, anon, authenticated;
revoke all on function app.assert_expense_balances_header() from public, anon, authenticated;
revoke all on function app.assert_line_periods_balance()    from public, anon, authenticated;
revoke all on function app.assert_line_periods_from_line()  from public, anon, authenticated;
revoke all on function app.refuse_voided_mutation()         from public, anon, authenticated;

-- ── Indexes ──────────────────────────────────────────────────────────────────
-- Shaped for the queries that will actually run (ARCHITECTURE §9): the ledger by
-- business date, profitability by period, and drill-down by category.
create index if not exists expenses_org_business_date_idx
  on public.expenses (org_id, business_date desc) where voided_at is null;
create index if not exists expenses_org_payment_idx
  on public.expenses (org_id, payment_status, payment_date)
  where voided_at is null;
create index if not exists expenses_vendor_idx
  on public.expenses (vendor_id) where voided_at is null;

create index if not exists expense_allocations_expense_idx
  on public.expense_allocations (expense_id);
create index if not exists expense_allocations_unit_idx
  on public.expense_allocations (org_id, business_unit_id);
create index if not exists expense_allocations_category_idx
  on public.expense_allocations (org_id, category_id);

create index if not exists expense_period_allocations_period_idx
  on public.expense_period_allocations (org_id, pnl_period_key, business_unit_id);
create index if not exists expense_period_allocations_category_period_idx
  on public.expense_period_allocations (org_id, business_unit_id, pnl_date);
create index if not exists expense_period_allocations_line_idx
  on public.expense_period_allocations (allocation_id);

create index if not exists expense_attachments_expense_idx
  on public.expense_attachments (expense_id) where removed_at is null;
