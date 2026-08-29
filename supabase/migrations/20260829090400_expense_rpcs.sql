-- ─────────────────────────────────────────────────────────────────────────────
-- 0029 · The expense mutation boundary
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.1 · Phase 3
--
-- Three functions, and no other way to write a financial row. Each runs in one
-- transaction and re-decides, server-side, everything the client decided for its own
-- interface: capability, scope over **every** unit named, the cross-unit and
-- cross-period privileges, hierarchy validity, archive state, the period lock on
-- **every** period touched, the edit window, and the row version. The client's opinion is
-- never sent as an authorisation claim and never trusted (D-037).
--
-- Check order is the same everywhere in this project, and it is deliberate: permission,
-- then ownership, then record state, then period, then version. Somebody with no
-- permission learns nothing about whether a document exists (D-046) or whether a month is
-- closed.
--
-- Idempotency and concurrency are separate mechanisms and are never conflated (D-021).
-- `p_mutation_id` replays a stored result; `p_base_row_version` refuses a stale intent.
-- ─────────────────────────────────────────────────────────────────────────────

-- Period lock, as its own refusal. `KM004` is distinct from a conflict and from a
-- permission problem so the interface can say the true thing (D-026).
create or replace function app.require_period_open(
  p_period_key       text,
  p_business_unit_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.period_locks pl
     where pl.org_id = app.current_org_id()
       and pl.period_key = p_period_key
       and (pl.business_unit_id is null
            or pl.business_unit_id = p_business_unit_id)
       and pl.state = 'closed') then
    perform app.refuse('KM004', 'period_closed',
      format('The accounting period %s is closed.', p_period_key),
      jsonb_build_object('period_key', p_period_key,
                         'business_unit_id', p_business_unit_id));
  end if;
end;
$$;

-- ── Shared validation ────────────────────────────────────────────────────────
-- Everything an allocation payload must satisfy before a single row is written. Factored
-- out because create and update must apply *identical* rules — an edit that could
-- introduce something a create refuses would be a hole shaped exactly like a feature.
create or replace function app.validate_expense_allocations(
  p_org_id        uuid,
  p_business_date date,
  p_period_start  date,
  p_period_end    date,
  p_total_minor   bigint,
  p_allocations   jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line        jsonb;
  v_part        jsonb;
  v_units       uuid[] := '{}';
  v_unit        uuid;
  v_sum         bigint := 0;
  v_line_sum    bigint;
  v_line_amount bigint;
  v_category    record;
  v_deliberate  boolean := false;
  v_period_key  text;
begin
  if p_allocations is null or jsonb_array_length(p_allocations) = 0 then
    perform app.refuse('KM018', 'allocation_imbalance',
      'An expense needs at least one allocation line.', '{}'::jsonb);
  end if;

  for v_line in select * from jsonb_array_elements(p_allocations) loop
    v_line_amount := (v_line->>'amount_minor')::bigint;
    if v_line_amount is null or v_line_amount <= 0 then
      perform app.refuse('KM018', 'allocation_imbalance',
        'Every allocation line carries a positive amount.', v_line);
    end if;
    v_sum := v_sum + v_line_amount;

    -- The classification must resolve as one tuple, must belong to this organisation,
    -- and must not be archived. An archived master stays valid for entries already
    -- recorded and is refused for new ones (D-035).
    select ec.id, ec.name, ec.archived_at, ec.business_unit_id
      into v_category
      from public.expense_categories ec
     where ec.id            = (v_line->>'category_id')::uuid
       and ec.section_id    = (v_line->>'section_id')::uuid
       and ec.department_id = (v_line->>'department_id')::uuid
       and ec.business_unit_id = (v_line->>'business_unit_id')::uuid
       and ec.org_id        = p_org_id;

    if v_category.id is null then
      perform app.refuse('KM010', 'hierarchy_violation',
        'That category does not belong to the department and property given.', v_line);
    end if;
    if v_category.archived_at is not null then
      perform app.refuse('KM006', 'archived_master',
        format('%s has been archived and cannot be used for new entries.',
               v_category.name),
        v_line);
    end if;

    v_unit := v_category.business_unit_id;
    if not (v_unit = any(v_units)) then
      v_units := v_units || v_unit;
      -- Scope over this unit, checked per unit rather than once for the document.
      perform app.require_capability('expense.create', v_unit);
    end if;

    -- Period contributions. Absent, the default rule fills in one covering the whole
    -- amount; present, they must reconcile to the line exactly and each period is
    -- checked against its own lock.
    if v_line ? 'periods' and jsonb_array_length(v_line->'periods') > 0 then
      v_line_sum := 0;
      for v_part in select * from jsonb_array_elements(v_line->'periods') loop
        v_line_sum := v_line_sum + (v_part->>'amount_minor')::bigint;
        if (v_part->>'amount_minor')::bigint <= 0 then
          perform app.refuse('KM019', 'period_imbalance',
            'Every accounting-period share carries a positive amount.', v_part);
        end if;
        if (v_part->>'period_start')::date > (v_part->>'period_end')::date then
          perform app.refuse('KM019', 'period_imbalance',
            'An accounting period cannot end before it starts.', v_part);
        end if;
        if coalesce((v_part->>'is_derived')::boolean, false) = false then
          v_deliberate := true;
        end if;
        v_period_key := to_char((v_part->>'period_end')::date, 'YYYY-MM');
        perform app.require_period_open(v_period_key, v_unit);
      end loop;

      if jsonb_array_length(v_line->'periods') > 1 then
        v_deliberate := true;
      end if;

      if v_line_sum <> v_line_amount then
        perform app.refuse('KM019', 'period_imbalance',
          'The accounting-period split does not add up to the line amount.',
          jsonb_build_object('line_minor', v_line_amount,
                             'allocated_minor', v_line_sum));
      end if;
    else
      -- The default: one contribution, whole amount, in the document's own period.
      perform app.require_period_open(
        to_char(coalesce(p_period_end, p_business_date), 'YYYY-MM'), v_unit);
    end if;
  end loop;

  if v_sum <> p_total_minor then
    perform app.refuse('KM018', 'allocation_imbalance',
      'The allocation lines do not add up to the expense total.',
      jsonb_build_object('total_minor', p_total_minor, 'allocated_minor', v_sum));
  end if;

  -- The two shape privileges, once the shape is known.
  if array_length(v_units, 1) > 1 then
    -- Scope on every unit is necessary and not sufficient (D-061).
    foreach v_unit in array v_units loop
      perform app.require_capability('expense.allocate_cross_unit', v_unit);
    end loop;
  end if;

  if v_deliberate then
    perform app.require_capability_anywhere('expense.allocate_periods');
  end if;
end;
$$;

-- Writes the lines and their contributions for an already-validated payload.
create or replace function app.write_expense_allocations(
  p_org_id        uuid,
  p_expense_id    uuid,
  p_business_date date,
  p_period_start  date,
  p_period_end    date,
  p_allocations   jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line    jsonb;
  v_part    jsonb;
  v_line_id uuid;
  v_unit    uuid;
  v_label   text;
  v_index   integer := 0;
begin
  for v_line in select * from jsonb_array_elements(p_allocations) loop
    v_line_id := coalesce((v_line->>'id')::uuid, extensions.gen_random_uuid());
    v_unit    := (v_line->>'business_unit_id')::uuid;

    -- The transaction-time label (D-035), read from the master rather than taken from
    -- the client, so the snapshot records what the category was actually called.
    select ec.name into v_label
      from public.expense_categories ec
     where ec.id = (v_line->>'category_id')::uuid;

    insert into public.expense_allocations (
      id, org_id, expense_id, business_unit_id, department_id, section_id,
      category_id, amount_minor, category_label, sort_order)
    values (
      v_line_id, p_org_id, p_expense_id, v_unit,
      (v_line->>'department_id')::uuid, (v_line->>'section_id')::uuid,
      (v_line->>'category_id')::uuid, (v_line->>'amount_minor')::bigint,
      v_label, v_index);

    if v_line ? 'periods' and jsonb_array_length(v_line->'periods') > 0 then
      for v_part in select * from jsonb_array_elements(v_line->'periods') loop
        insert into public.expense_period_allocations (
          id, org_id, expense_id, allocation_id, business_unit_id,
          accounting_period_start, accounting_period_end,
          amount_minor, pnl_date, pnl_period_key, is_derived)
        values (
          coalesce((v_part->>'id')::uuid, extensions.gen_random_uuid()),
          p_org_id, p_expense_id, v_line_id, v_unit,
          (v_part->>'period_start')::date, (v_part->>'period_end')::date,
          (v_part->>'amount_minor')::bigint,
          (v_part->>'period_end')::date,
          to_char((v_part->>'period_end')::date, 'YYYY-MM'),
          coalesce((v_part->>'is_derived')::boolean, false));
      end loop;
    else
      -- The default rule, materialised. Every line reports through a contribution row
      -- and never through its own amount, so no query can count it twice (D-060).
      insert into public.expense_period_allocations (
        id, org_id, expense_id, allocation_id, business_unit_id,
        accounting_period_start, accounting_period_end,
        amount_minor, pnl_date, pnl_period_key, is_derived)
      values (
        extensions.gen_random_uuid(), p_org_id, p_expense_id, v_line_id, v_unit,
        coalesce(p_period_start, p_business_date),
        coalesce(p_period_end, p_business_date),
        (v_line->>'amount_minor')::bigint,
        coalesce(p_period_end, p_business_date),
        to_char(coalesce(p_period_end, p_business_date), 'YYYY-MM'),
        true);
    end if;

    -- The O(1) usage counter a rename or archive decision reads (D-041). Its first
    -- callers, at last.
    perform app.record_master_usage(
      p_org_id, 'expense_category', (v_line->>'category_id')::uuid, p_business_date, 1);

    v_index := v_index + 1;
  end loop;
end;
$$;

-- ── Create ───────────────────────────────────────────────────────────────────
create or replace function public.expense_create(
  p_id            uuid,
  p_business_date date,
  p_total_minor   bigint,
  p_allocations   jsonb,
  p_business_date_source text default 'derived',
  p_period_start  date default null,
  p_period_end    date default null,
  p_vendor_id     uuid default null,
  p_payment_status text default 'unpaid',
  p_payment_date  date default null,
  p_payment_method_id uuid default null,
  p_reference_number text default null,
  p_notes         text default null,
  p_tax_amount_minor bigint default null,
  p_captured_at   timestamptz default null,
  p_mutation_id   uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  v_replay jsonb;
  v_result jsonb;
  v_number text;
  v_year   smallint;
begin
  -- Idempotency first. A redelivery replays the stored answer and writes nothing.
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Everything about the payload, before a row exists.
  perform app.validate_expense_allocations(
    v_org, p_business_date, p_period_start, p_period_end,
    p_total_minor, p_allocations);

  insert into public.expenses (
    id, org_id, business_date, business_date_source,
    accounting_period_start, accounting_period_end,
    total_amount_minor, vendor_id, payment_status, payment_date,
    payment_method_id, reference_number, notes, tax_amount_minor,
    created_by, captured_at)
  values (
    p_id, v_org, p_business_date, p_business_date_source,
    p_period_start, p_period_end,
    p_total_minor, p_vendor_id, p_payment_status, p_payment_date,
    p_payment_method_id, p_reference_number, p_notes, p_tax_amount_minor,
    v_actor, coalesce(p_captured_at, now()));

  perform app.write_expense_allocations(
    v_org, p_id, p_business_date, p_period_start, p_period_end, p_allocations);

  -- The number is issued only now, once the write has been accepted. A number is a
  -- claim that a document exists.
  select n.issued_number, n.issued_year into v_number, v_year
    from app.allocate_expense_number(v_org, p_business_date) n;

  update public.expenses
     set txn_number = v_number, financial_year = v_year
   where id = p_id;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'expense', 'entity_id', p_id,
    'txn_number', v_number,
    'financial_year', v_year,
    'row_version', (select row_version from public.expenses where id = p_id));

  perform app.write_audit(v_org, 'expense', p_id, 'expense_created', v_actor,
    null, v_result, null, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'expense', p_id,
                               'create', v_result);
end;
$$;

-- ── Update ───────────────────────────────────────────────────────────────────
-- Replaces the lines wholesale rather than diffing them. A financial document's
-- classification is one decision, and half-applied edits are how totals stop matching.
create or replace function public.expense_update(
  p_id              uuid,
  p_base_row_version integer,
  p_business_date   date,
  p_total_minor     bigint,
  p_allocations     jsonb,
  p_period_start    date default null,
  p_period_end      date default null,
  p_vendor_id       uuid default null,
  p_payment_status  text default 'unpaid',
  p_payment_date    date default null,
  p_payment_method_id uuid default null,
  p_reference_number text default null,
  p_notes           text default null,
  p_tax_amount_minor bigint default null,
  p_mutation_id     uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor   uuid;
  v_org     uuid;
  v_replay  jsonb;
  v_result  jsonb;
  v_before  jsonb;
  e         record;
  v_window  integer;
  v_unit    uuid;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Permission before existence (D-046): a caller who may edit nothing anywhere learns
  -- nothing about which documents exist.
  perform app.require_capability_anywhere('expense.edit.own');

  select * into e from public.expenses where id = p_id and org_id = v_org;
  if e.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That expense does not exist.',
      jsonb_build_object('expense_id', p_id));
  end if;

  if e.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This expense has been voided. Corrections are made by entering a new expense.',
      jsonb_build_object('expense_id', p_id));
  end if;

  -- Ownership, per unit, and the edit window.
  for v_unit in
    select distinct a.business_unit_id from public.expense_allocations a
     where a.expense_id = p_id
  loop
    if not public.has_capability('expense.edit.all', v_unit) then
      perform app.require_capability('expense.edit.own', v_unit);
      if e.created_by <> v_actor then
        perform app.refuse('KM001', 'missing_capability',
          'You may only change entries you recorded yourself.',
          jsonb_build_object('expense_id', p_id));
      end if;
    end if;
  end loop;

  -- Configuration, not a constant (spec §13.3). Absent, the seeded default applies.
  select coalesce((os.value)::text::integer, 7) into v_window
    from public.org_settings os
   where os.org_id = v_org and os.key = 'edit_window_days';

  if (current_date - e.business_date) > coalesce(v_window, 7)
     and not public.has_capability_anywhere('transaction.correct.beyond_window') then
    perform app.refuse('KM021', 'edit_window_expired',
      format('This entry is more than %s days old and can no longer be changed here.',
             coalesce(v_window, 7)),
      jsonb_build_object('business_date', e.business_date));
  end if;

  -- Concurrency, after authority and state, so a caller without permission never learns
  -- the current version (D-021, D-046).
  if e.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'Somebody else changed this expense while you were working on it.',
      jsonb_build_object('expected', p_base_row_version, 'actual', e.row_version));
  end if;

  perform app.validate_expense_allocations(
    v_org, p_business_date, p_period_start, p_period_end,
    p_total_minor, p_allocations);

  v_before := to_jsonb(e);

  -- The old lines stop being live. Their historical usage is untouched (see 0032).
  perform app.record_master_usage(v_org, 'expense_category', a.category_id,
                                  e.business_date, 0, -1)
     from public.expense_allocations a where a.expense_id = p_id;

  delete from public.expense_period_allocations where expense_id = p_id;
  delete from public.expense_allocations        where expense_id = p_id;

  update public.expenses
     set business_date = p_business_date,
         accounting_period_start = p_period_start,
         accounting_period_end   = p_period_end,
         total_amount_minor = p_total_minor,
         vendor_id = p_vendor_id,
         payment_status = p_payment_status,
         payment_date = p_payment_date,
         payment_method_id = p_payment_method_id,
         reference_number = p_reference_number,
         notes = p_notes,
         tax_amount_minor = p_tax_amount_minor
   where id = p_id;

  perform app.write_expense_allocations(
    v_org, p_id, p_business_date, p_period_start, p_period_end, p_allocations);

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'expense', 'entity_id', p_id,
    'row_version', (select row_version from public.expenses where id = p_id));

  perform app.write_audit(v_org, 'expense', p_id, 'expense_edited', v_actor,
    v_before, to_jsonb((select e2 from public.expenses e2 where e2.id = p_id)),
    null, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'expense', p_id,
                               'update', v_result);
end;
$$;

-- ── Void ─────────────────────────────────────────────────────────────────────
-- The approved policy: Accountant and the Owner role, while the period is open, with a
-- mandatory reason, no age limit, and the period lock never bypassed. Attachments are
-- kept — the document remains, and so does its evidence.
create or replace function public.expense_void(
  p_id               uuid,
  p_base_row_version integer,
  p_reason           text,
  p_mutation_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  v_replay jsonb;
  v_result jsonb;
  v_before jsonb;
  e        record;
  v_unit   uuid;
  v_period text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  perform app.require_capability_anywhere('expense.void');

  if p_reason is null or length(btrim(p_reason)) = 0 then
    perform app.refuse('KM008', 'reason_required',
      'A void always states why. The reason is recorded against the document.',
      jsonb_build_object('expense_id', p_id));
  end if;

  select * into e from public.expenses where id = p_id and org_id = v_org;
  if e.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That expense does not exist.',
      jsonb_build_object('expense_id', p_id));
  end if;

  if e.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This expense has already been voided.',
      jsonb_build_object('expense_id', p_id));
  end if;

  -- Scope on every unit it charges, and every period it reports into still open. A
  -- closed month refuses the void; the way back is the audited reopen workflow, and the
  -- lock is never bypassed.
  for v_unit in
    select distinct a.business_unit_id from public.expense_allocations a
     where a.expense_id = p_id
  loop
    perform app.require_capability('expense.void', v_unit);
  end loop;

  for v_unit, v_period in
    select distinct p.business_unit_id, p.pnl_period_key
      from public.expense_period_allocations p
     where p.expense_id = p_id
  loop
    perform app.require_period_open(v_period, v_unit);
  end loop;

  if e.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'Somebody else changed this expense while you were working on it.',
      jsonb_build_object('expected', p_base_row_version, 'actual', e.row_version));
  end if;

  v_before := to_jsonb(e);

  -- The immutability trigger refuses updates to an already-voided row; this is the one
  -- update that sets voided_at, and it runs while the row is still live.
  update public.expenses
     set voided_at = now(), voided_by = v_actor, void_reason = p_reason
   where id = p_id;

  -- Active references go; historical usage stays. A voided expense still happened, and
  -- the D-038 rename warning is built on that history (see 0032). Attachments are
  -- untouched: the document and its evidence remain part of the record.
  perform app.record_master_usage(v_org, 'expense_category', a.category_id,
                                  e.business_date, 0, -1)
     from public.expense_allocations a where a.expense_id = p_id;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'expense', 'entity_id', p_id,
    'voided', true,
    'row_version', (select row_version from public.expenses where id = p_id));

  perform app.write_audit(v_org, 'expense', p_id, 'expense_voided', v_actor,
    v_before, to_jsonb((select e2 from public.expenses e2 where e2.id = p_id)),
    p_reason, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'expense', p_id,
                               'void', v_result);
end;
$$;

-- ── Grants ───────────────────────────────────────────────────────────────────
revoke all on function app.validate_expense_allocations(
  uuid, date, date, date, bigint, jsonb) from public, anon, authenticated;
revoke all on function app.write_expense_allocations(
  uuid, uuid, date, date, date, jsonb) from public, anon, authenticated;
revoke all on function app.require_period_open(text, uuid)
  from public, anon, authenticated;

revoke all on function public.expense_create(
  uuid, date, bigint, jsonb, text, date, date, uuid, text, date, uuid, text, text,
  bigint, timestamptz, uuid) from public, anon;
revoke all on function public.expense_update(
  uuid, integer, date, bigint, jsonb, date, date, uuid, text, date, uuid, text, text,
  bigint, uuid) from public, anon;
revoke all on function public.expense_void(uuid, integer, text, uuid)
  from public, anon;

grant execute on function public.expense_create(
  uuid, date, bigint, jsonb, text, date, date, uuid, text, date, uuid, text, text,
  bigint, timestamptz, uuid) to authenticated;
grant execute on function public.expense_update(
  uuid, integer, date, bigint, jsonb, date, date, uuid, text, date, uuid, text, text,
  bigint, uuid) to authenticated;
grant execute on function public.expense_void(uuid, integer, text, uuid)
  to authenticated;
