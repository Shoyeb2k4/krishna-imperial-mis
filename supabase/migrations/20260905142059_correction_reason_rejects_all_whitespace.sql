-- A correction reason of one tab character is not a reason
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.2 · Phase 3 corrective, second finding
--
-- `20260905141738_expense_business_date_correction` tested the reason with
-- `length(btrim(coalesce(p_correction_reason, ''))) = 0`. **`btrim(text)` with one
-- argument strips spaces and nothing else** — not tabs, not newlines, not a carriage
-- return. So `'   <tab>  '` trimmed to a single tab, measured 1, and was accepted as a
-- stated reason. The audit row would have carried a tab where the reason belongs, and the
-- rule that a correction always says why would have been satisfiable by pressing one key.
--
-- Found by the live case that exists precisely to distinguish "empty" from "blank", which
-- is why it is written separately from the empty-string case rather than folded into it.
-- It is fixed in its own migration rather than by editing the applied one: the committed
-- file for 20260905141738 is byte-identical to the statements the server ran, and
-- rewriting it to look like something that never ran is the exact substitution of
-- resemblance for provenance that A0 and D-056 exist to prevent.
--
-- Nothing else about `expense_update` changes. The whole body is restated because that is
-- what `create or replace function` requires, and the assertion at the foot proves the
-- restatement disturbed neither the grant nor the guards.
--
-- **Recorded, not changed here:** `expense_void` and `revenue_void` test their own
-- mandatory reasons with the same one-argument `btrim`, so a tab satisfies them too. That
-- is the same defect in two functions outside this corrective's reviewed scope — one an
-- expense void, one a revenue void — and quietly widening a reviewed change is how a scope
-- stops being reviewable (D-127). It is reported rather than fixed in passing.

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
  -- nothing about which documents exist. **Either** form of the editing capability counts
  -- (D-065).
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

  -- Whether this is a business-date correction is decided **here**, from canonical state,
  -- never from a flag in the request.
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
  if v_date_moved then
    for v_unit in
      select distinct a.business_unit_id from public.expense_allocations a
       where a.expense_id = p_id
    loop
      perform app.require_capability('transaction.correct.business_date', v_unit);
    end loop;

    -- Every kind of whitespace, not merely the space character. `btrim` with one argument
    -- strips spaces alone, which let a single tab stand in for a stated reason.
    v_reason := regexp_replace(coalesce(p_correction_reason, ''),
                               '^\s+|\s+$', '', 'g');
    if length(v_reason) = 0 then
      perform app.refuse('KM008', 'reason_required',
        'Changing the business date of a recorded expense always states why. '
        'The reason is kept with the correction.',
        jsonb_build_object('expense_id', p_id,
                           'from', e.business_date,
                           'to',   p_business_date));
    end if;
  end if;

  -- Configuration, not a constant (spec §13.3).
  select coalesce((os.value)::text::integer, 7) into v_window
    from public.org_settings os
   where os.org_id = v_org and os.key = 'edit_window_days';

  -- "Today" is the property's current business date, never the session's calendar date
  -- (D-067).
  v_today := app.expense_window_today(p_id);

  -- D+7 permitted, D+8 refused. `transaction.correct.beyond_window` lifts the *age* rule
  -- and nothing else, and is a separate capability from
  -- `transaction.correct.business_date`: neither implies the other.
  if (v_today - e.business_date) > coalesce(v_window, 7)
     and not public.has_capability_anywhere('transaction.correct.beyond_window') then
    perform app.refuse('KM021', 'edit_window_expired',
      format('This entry is more than %s days old and can no longer be changed here.',
             coalesce(v_window, 7)),
      jsonb_build_object('business_date', e.business_date,
                         'days_elapsed', v_today - e.business_date,
                         'window_days', coalesce(v_window, 7)));
  end if;

  -- ── The SOURCE periods: where the money is now (D-060, D-034, D-061) ────────
  for v_unit, v_period in
    select distinct p.business_unit_id, p.pnl_period_key
      from public.expense_period_allocations p
     where p.expense_id = p_id
  loop
    perform app.require_period_open(v_period, v_unit);
  end loop;

  -- Concurrency, after authority and state (D-021, D-046).
  if e.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'Somebody else changed this expense while you were working on it.',
      jsonb_build_object('expected', p_base_row_version, 'actual', e.row_version));
  end if;

  -- The TARGET periods, and everything else a create must satisfy.
  perform app.validate_expense_allocations(
    v_org, p_business_date, p_period_start, p_period_end,
    p_total_minor, p_allocations);

  v_before := to_jsonb(e);

  perform app.record_master_usage(v_org, 'expense_category', a.category_id,
                                  e.business_date, 0, -1)
     from public.expense_allocations a where a.expense_id = p_id;

  delete from public.expense_period_allocations where expense_id = p_id;
  delete from public.expense_allocations        where expense_id = p_id;

  update public.expenses
     set business_date = p_business_date,
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

-- ── The restatement changed nothing it was not meant to ─────────────────────
do $$
declare
  v_def   text;
  v_count integer;
begin
  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'expense_update';
  if v_count <> 1 then
    raise exception 'expense_update has % overloads; exactly one is the contract', v_count;
  end if;

  v_def := pg_get_functiondef('public.expense_update(uuid,integer,date,bigint,jsonb,'
             'date,date,uuid,text,date,uuid,text,text,bigint,text,uuid)'::regprocedure);

  -- The four guards this corrective exists for, each still present and each still its own
  -- separate test. Asserted by name because a restatement is exactly where one quietly
  -- goes missing.
  if v_def not like '%transaction.correct.business_date%' then
    raise exception 'the business-date correction capability is no longer evaluated';
  end if;
  if v_def not like '%transaction.correct.beyond_window%' then
    raise exception 'the edit-window capability is no longer evaluated';
  end if;
  if v_def not like '%expense_period_allocations p%' then
    raise exception 'the source-period guard is gone';
  end if;
  if v_def not like '%business_date_source = case when v_date_moved%' then
    raise exception 'a corrected date no longer records that it was corrected';
  end if;
  if v_def not like '%expense_business_date_corrected%' then
    raise exception 'the distinct correction audit action is gone';
  end if;
  if v_def like '%btrim(coalesce(p_correction_reason%' then
    raise exception 'the reason check still strips spaces only';
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
end $$;

-- ── And the rule the fix is about, proven on the values themselves ──────────
--
-- A deploy-time assertion rather than a comment, in the pattern 0033 established for the
-- business-date rule: the strings that must be refused, and one that must not.
do $$
declare v_case record;
begin
  for v_case in
    select * from (values
      (''                    , true , 'empty'),
      ('   '                 , true , 'spaces'),
      (E'\t'                 , true , 'one tab, the case that got through'),
      (E'   \t  '            , true , 'spaces around a tab'),
      (E'\n\r '              , true , 'newline and carriage return'),
      ('Wrong trading day'   , false, 'an actual reason'),
      (E'  Wrong day  '      , false, 'an actual reason, padded')
    ) as t(reason, must_refuse, why)
  loop
    if (length(regexp_replace(v_case.reason, '^\s+|\s+$', '', 'g')) = 0)
       <> v_case.must_refuse then
      raise exception 'the correction-reason rule is wrong for % (%)',
        quote_literal(v_case.reason), v_case.why;
    end if;
  end loop;

  -- The positive control: the rule that was there before fails this table, on the one
  -- row it was written for. If this ever stops raising, `btrim` has changed meaning.
  if length(btrim(E'   \t  ')) = 0 then
    raise exception
      'btrim(text) now strips tabs, so the finding this migration records no longer '
      'reproduces — re-read it before trusting either form';
  end if;
end $$;
