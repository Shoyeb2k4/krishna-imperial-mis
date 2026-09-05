-- ─────────────────────────────────────────────────────────────────────────────
-- Expense business-date correction: one contract, both periods, a first-class act
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.2 · Phase 3 corrective
--
-- `expense_update` stays the single authoritative Expense correction boundary. There is
-- no `expense_correct_business_date`, there never was one, and this migration does not
-- create one: three canonical documents named an endpoint the server has never exposed,
-- and the answer is to correct the documents, not to grow a second write path for one
-- document (D-127). Two write paths for one financial document is the thing this project
-- keeps paying for.
--
-- Four findings, all evidenced against the shipped function on this project before a line
-- was changed, and all fixed here.
--
-- 1 · THE SOURCE PERIOD WAS NOT PROTECTED. `app.validate_expense_allocations` only ever
--     sees the periods in the **incoming** payload, so it can say where an amount is
--     going and never where it is being taken *from*. Proven by probe: an expense of
--     ₹45,000 contributing to a **closed** 2026-03 was moved to an open 2026-04, the call
--     returned `applied`, and the closed month's contribution went from ₹45,000 to ₹0.
--     Spec §13.4 rejects "every create, edit, void and business-date correction
--     **affecting** that period", and removing an amount from a closed month affects it
--     as surely as adding one. `expense_void` has always understood this;
--     `revenue_update` applies it (D-124). The source periods are read from
--     `expense_period_allocations` — the one reporting source (D-060) — so this reuses
--     the established contribution logic rather than re-deriving attribution for a lock
--     check.
--
-- 2 · THE DATE MOVE WAS NOT AN ACT. It was an ordinary field write. It now requires
--     `transaction.correct.business_date`, which until today was granted to two roles and
--     evaluated by **nothing** anywhere in `public` or `app` — a rule that nothing
--     evaluates is a comment (D-068, D-071, D-077), arriving as a grant rather than as a
--     check. Whether the date moved is decided **here**, by comparing the canonical row
--     against the request. No client boolean says "this is a correction": a caller that
--     could declare its own act would be deciding its own authority.
--
-- 3 · IT COLLECTED NO REASON. Spec §9 requires every business-date correction to be
--     audited with before and after values, actor, timestamp **and reason**. The reason
--     is required only on the branch where the date actually moves, so an ordinary amount
--     or notes correction gains no field and the fast path is untouched. It is stored
--     where this schema already keeps a mutation's reason — `audit_logs.reason`,
--     append-only, the same place `expense_void` puts its own — rather than in a new
--     column that would be a second source of truth for one fact.
--
-- 4 · A CORRECTED DATE DID NOT SAY SO. `expenses.business_date_source` exists, and
--     `expense_create` sets it; `expense_update` never wrote it, so every row on this
--     project reads `derived` including the ones the acceptance suite had moved. D-019
--     requires the record to note whether a date was `derived`, `manual` or `corrected`.
--     It is now written on that branch and **only** on that branch: an ordinary metadata
--     edit to an already-corrected row does not restate it, because provenance that
--     re-fires on every later save stops being provenance.
--
-- Nothing else about the contract moves. The edit window is still measured under the
-- property's own business date (D-067); `transaction.correct.beyond_window` still lifts
-- the age rule and nothing else; `base_row_version` still refuses a stale intent;
-- `mutation_id` still replays; the transaction number is still never restated.
-- `transaction.correct.business_date` authorises the **kind** of act and grants no relief
-- from the window, the period locks, the scope or the version — capabilities compose,
-- they do not replace one another, and each of those guards is written separately below
-- so that no one of them can be satisfied by holding another.
--
-- The signature grows one argument, so the old overload is dropped rather than left
-- beside the new one: two functions of the same name would make every call ambiguous.
-- ─────────────────────────────────────────────────────────────────────────────

drop function if exists public.expense_update(
  uuid, integer, date, bigint, jsonb, date, date, uuid, text, date, uuid, text, text,
  bigint, uuid);

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
  p_correction_reason text default null,
  p_mutation_id     uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor      uuid;
  v_org        uuid;
  v_replay     jsonb;
  v_result     jsonb;
  v_before     jsonb;
  e            record;
  v_window     integer;
  v_unit       uuid;
  v_period     text;
  v_today      date;
  v_date_moved boolean;
  v_reason     text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Permission before existence (D-046): a caller who may edit nothing anywhere learns
  -- nothing about which documents exist.
  --
  -- **Either** form counts. An Accountant holds `expense.edit.all` and not
  -- `expense.edit.own`, so asking for the latter specifically refused the one role that
  -- exists to correct other people's entries. Caught by the live edit-window test.
  perform app.require_any_edit_capability();

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

  -- Whether this is a business-date correction is decided **here**, from canonical state.
  -- Not from a flag in the request: a caller able to say "this is not a correction" would
  -- be choosing which rules apply to it.
  v_date_moved := p_business_date is distinct from e.business_date;

  -- Ownership, per unit.
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

  -- ── Moving the date is its own act, with its own authority and its own reason ──
  --
  -- Scoped against the properties the document **currently** charges, because that is
  -- what identifies the document being corrected. Adding a property to it is separately
  -- gated by `expense.create` and `expense.allocate_cross_unit` on that property, inside
  -- the validator below (D-061).
  if v_date_moved then
    for v_unit in
      select distinct a.business_unit_id from public.expense_allocations a
       where a.expense_id = p_id
    loop
      perform app.require_capability('transaction.correct.business_date', v_unit);
    end loop;

    v_reason := btrim(coalesce(p_correction_reason, ''));
    if length(v_reason) = 0 then
      perform app.refuse('KM008', 'reason_required',
        'Changing the business date of a recorded expense always states why. '
        'The reason is kept with the correction.',
        jsonb_build_object('expense_id', p_id,
                           'from', e.business_date,
                           'to',   p_business_date));
    end if;
  end if;

  -- Configuration, not a constant (spec §13.3). Absent, the seeded default applies.
  select coalesce((os.value)::text::integer, 7) into v_window
    from public.org_settings os
   where os.org_id = v_org and os.key = 'edit_window_days';

  -- "Today" is the property's current **business date**, never the database session's
  -- calendar date. The session runs in UTC, so `current_date` lagged the property date
  -- for part of every night and quietly granted an extra day of window (D-067).
  v_today := app.expense_window_today(p_id);

  -- Inclusive of its last day: a business date of D is editable on D+7 and refused on
  -- D+8, counted in whole calendar days under the property's own business-date policy.
  -- `transaction.correct.beyond_window` lifts the *age* rule and nothing else. It is a
  -- separate capability from `transaction.correct.business_date` and neither implies the
  -- other: an old entry whose date is being corrected must satisfy both.
  if (v_today - e.business_date) > coalesce(v_window, 7)
     and not public.has_capability_anywhere('transaction.correct.beyond_window') then
    perform app.refuse('KM021', 'edit_window_expired',
      format('This entry is more than %s days old and can no longer be changed here.',
             coalesce(v_window, 7)),
      jsonb_build_object('business_date', e.business_date,
                         'days_elapsed', v_today - e.business_date,
                         'window_days', coalesce(v_window, 7)));
  end if;

  -- ── The SOURCE periods: where the money is now ───────────────────────────────
  --
  -- Read from `expense_period_allocations`, which is the only place an expense's period
  -- attribution lives (D-060), so every period a line contributes to is covered on both
  -- dimensions — a cross-unit split and a cross-period split alike (D-034, D-061). No
  -- P&L arithmetic is re-implemented for the lock check; the rows the reports read are
  -- the rows checked here. This is the same loop `expense_void` has always run, for the
  -- same reason: removing an amount from a closed month changes that month's Operating
  -- Profit.
  --
  -- The TARGET periods are checked inside `app.validate_expense_allocations` below, which
  -- create and update share, so an edit can never introduce a period placement a create
  -- would refuse.
  for v_unit, v_period in
    select distinct p.business_unit_id, p.pnl_period_key
      from public.expense_period_allocations p
     where p.expense_id = p_id
  loop
    perform app.require_period_open(v_period, v_unit);
  end loop;

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
         -- Written on this branch and only on this branch. A later metadata edit to a row
         -- that already reads `corrected` leaves it alone, so the provenance stays a
         -- statement about the date rather than about the last time anybody saved (D-019).
         business_date_source = case when v_date_moved
                                     then 'corrected' else e.business_date_source end,
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
    'business_date_corrected', v_date_moved,
    'row_version', (select row_version from public.expenses where id = p_id));

  perform app.write_audit(v_org, 'expense', p_id, 'expense_edited', v_actor,
    v_before, to_jsonb((select e2 from public.expenses e2 where e2.id = p_id)),
    null, null::uuid, p_mutation_id);

  -- A distinct action, so "which dates were moved, by whom, and why" is answerable by
  -- reading one action rather than by diffing every edited row's before/after state.
  -- Written only on the moved branch, and after the replay guard at the top, so an
  -- idempotent redelivery of the same mutation produces no second audit effect.
  if v_date_moved then
    perform app.write_audit(v_org, 'expense', p_id, 'expense_business_date_corrected',
      v_actor,
      jsonb_build_object('business_date', e.business_date,
                         'business_date_source', e.business_date_source),
      jsonb_build_object('business_date', p_business_date,
                         'business_date_source', 'corrected'),
      v_reason, null::uuid, p_mutation_id);
  end if;

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'expense', p_id,
                               'update', v_result);
end;
$$;

revoke all on function public.expense_update(
  uuid, integer, date, bigint, jsonb, date, date, uuid, text, date, uuid, text, text,
  bigint, text, uuid) from public, anon;
grant execute on function public.expense_update(
  uuid, integer, date, bigint, jsonb, date, date, uuid, text, date, uuid, text, text,
  bigint, text, uuid) to authenticated;

-- ── Invariants, asserted rather than described ───────────────────────────────
do $$
declare
  v_count   integer;
  v_leaked  text;
begin
  -- Exactly one `expense_update`. The dropped overload must actually be gone: two
  -- functions of one name make every call ambiguous, and PostgREST would refuse them all.
  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'expense_update';
  if v_count <> 1 then
    raise exception 'expense_update has % overloads; exactly one is the contract', v_count;
  end if;

  if not has_function_privilege('authenticated', 'public.expense_update(uuid,integer,'
       'date,bigint,jsonb,date,date,uuid,text,date,uuid,text,text,bigint,text,uuid)',
       'EXECUTE') then
    raise exception 'expense_update lost its EXECUTE grant to authenticated';
  end if;
  if has_function_privilege('anon', 'public.expense_update(uuid,integer,'
       'date,bigint,jsonb,date,date,uuid,text,date,uuid,text,text,bigint,text,uuid)',
       'EXECUTE') then
    raise exception 'expense_update is reachable by anon';
  end if;

  -- And this migration invented no `expense_correct_business_date`. The documents that
  -- named one are corrected in the same change; the surface stays as it is.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'app')
                and p.proname = 'expense_correct_business_date') then
    raise exception
      'a second expense correction endpoint exists; expense_update is the one contract';
  end if;

  select string_agg(p.proname, ', ') into v_leaked
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_leaked is not null then
    raise exception 'a client role can execute functions in app: %', v_leaked;
  end if;
end $$;

-- ── The dead capability now has an evaluator, and it is asserted, not hoped ──
--
-- `transaction.correct.business_date` was granted to the accountant and owner bundles and
-- named by **0** functions and **0** policies on this project. A capability granted in
-- production and evaluated nowhere is a comment wearing a grant's clothes (D-068, D-071,
-- D-077, D-127 §3). This is the general form of that check: every capability the
-- catalogue grants to some role must be named by something that can actually evaluate it
-- — a function body or a policy expression.
--
-- `prokind = 'f'` is not decoration: `pg_get_functiondef` raises on an aggregate, and a
-- migration that fails for that reason would look exactly like a real finding.
--
-- Four capabilities are exempt, named individually rather than matched by a pattern, and
-- each for the same reason: **the surface they govern does not exist yet.** Reporting and
-- export are Phase 5 and Phase 7; there is no settings RPC. That is a different thing
-- from `transaction.correct.business_date`, whose surface was built, shipped and running
-- while the capability went unread — which is why it is not on this list and why this
-- migration exists. The exemption is a list a later phase has to delete a line from, not
-- a rule that quietly absorbs the next dead grant: adding a capability here is a
-- deliberate statement that nothing enforces it, and it belongs in `DECISIONS.md` if it
-- is ever true of a feature that has shipped.
do $$
declare
  v_dead text;
  v_unbuilt constant text[] := array[
    'reports.view',      -- Phase 5 · no reporting engine exists
    'reports.export',    -- Phase 7 · no export path exists
    'reports.print',     -- Phase 7 · no print path exists
    'settings.manage'];  -- no settings RPC exists
begin
  select string_agg(distinct rc.capability_code, ', ') into v_dead
    from public.role_capabilities rc
   where not (rc.capability_code = any(v_unbuilt))
     and not exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'app') and p.prokind = 'f'
              and pg_get_functiondef(p.oid) like '%' || rc.capability_code || '%')
     and not exists (
           select 1 from pg_policies pol
            where coalesce(pol.qual, '') like '%' || rc.capability_code || '%'
               or coalesce(pol.with_check, '') like '%' || rc.capability_code || '%');
  if v_dead is not null then
    raise exception
      'granted in production and evaluated nowhere: %. Either the check was never '
      'written or the grant was never meant (D-127 section 3)', v_dead;
  end if;

  -- The exemption list must itself stay honest: a capability named there that HAS
  -- acquired an evaluator is a stale excuse, and the line has to go.
  select string_agg(c, ', ') into v_dead
    from unnest(v_unbuilt) as c
   where exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'app') and p.prokind = 'f'
              and pg_get_functiondef(p.oid) like '%' || c || '%')
      or exists (
           select 1 from pg_policies pol
            where coalesce(pol.qual, '') like '%' || c || '%'
               or coalesce(pol.with_check, '') like '%' || c || '%');
  if v_dead is not null then
    raise exception
      'listed as not-yet-built but now enforced: %. Remove the exemption', v_dead;
  end if;

  -- And specifically, the one this migration exists to give an evaluator, named at the
  -- authoritative Expense mutation boundary itself rather than merely somewhere.
  if pg_get_functiondef('public.expense_update(uuid,integer,date,bigint,jsonb,date,date,'
       'uuid,text,date,uuid,text,text,bigint,text,uuid)'::regprocedure)
       not like '%transaction.correct.business_date%' then
    raise exception
      'expense_update does not evaluate transaction.correct.business_date';
  end if;

  -- The two correction capabilities are separate guards. Neither is spelled in terms of
  -- the other, so holding one can never satisfy the other's check.
  if pg_get_functiondef('public.expense_update(uuid,integer,date,bigint,jsonb,date,date,'
       'uuid,text,date,uuid,text,text,bigint,text,uuid)'::regprocedure)
       not like '%transaction.correct.beyond_window%' then
    raise exception 'expense_update no longer evaluates the edit window capability';
  end if;
end $$;
