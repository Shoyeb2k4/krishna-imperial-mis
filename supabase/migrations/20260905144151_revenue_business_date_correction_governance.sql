-- Moving a sale's business date is a correction on the revenue side too
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.2 · Phase 4 corrective, after Slice 10
--
-- Not a mirror of the expense fix. `revenue_update` was audited against the corrected
-- expense contract point by point, against the shipped function on this project, and it
-- already did four of the seven things — so those are not touched:
--
--     source AND target period checked      already correct (D-124)
--     tax re-resolved on the NEW date       already correct (D-124)
--     KI-REV preserved across a correction  already correct
--     base_row_version concurrency          already correct
--
-- Three were missing, and a probe proved it rather than a reading of the SQL. A Manager —
-- who holds `revenue.edit` and does **not** hold `transaction.correct.business_date` —
-- recorded a sale, then moved its business date from 2026-09-04 to 2026-09-03. The call
-- returned `status: updated`. No capability was asked for, no reason was collected, and
-- the audit trail held one row reading `edited` with a null reason.
--
-- Spec §9 requires that a business date correction be "subject to permission" and
-- "audited with before and after values, actor, timestamp and reason", and spec §14 lists
-- **business date corrected** among the actions the audit trail covers. Neither section is
-- scoped to expenses, and a revenue entry carries a business date like any other financial
-- row. So this is a governance gap in the revenue engine, not a symmetry argument.
--
--     1 · the move is DETECTED from canonical state, by comparing dates rather than
--         period keys — the previous comparison could not see a move within one month,
--         which is most of them;
--     2 · it requires `transaction.correct.business_date` for the entry's property;
--     3 · it requires a reason, non-empty after ALL whitespace is stripped;
--     4 · it writes a distinct `business_date_corrected` audit action carrying both dates
--         and the reason, beside the ordinary `edited` row.
--
-- **What is deliberately NOT done here.** The expense engine also stamps
-- `business_date_source = 'corrected'` (D-019). `revenue_entries` has no such column and
-- never has: spec §8.0 enumerates what a revenue entry carries and does not include one,
-- while spec §9 says the record notes how its date was arrived at. Those two readings
-- disagree, and adding a column to the revenue document because the expense document has
-- one would be settling a product question by symmetry. It is raised for the project lead
-- instead, and this migration adds no column.
--
-- Also recorded and not changed: `revenue_void` and `expense_void` test their mandatory
-- reasons with one-argument `btrim`, which strips spaces and not tabs, so a single tab
-- satisfies both. Same defect class, different reviewed scope.

create or replace function public.revenue_update(
  p_id                uuid,
  p_base_row_version  integer,
  p_business_date     date,
  p_components        jsonb,
  p_entry_kind        text default 'daily_summary',
  p_source_reference  text default null,
  p_notes             text default null,
  p_correction_reason text default null,
  p_mutation_id       uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_replay jsonb; v_comp jsonb;
  v_entry public.revenue_entries;
  v_rule public.revenue_tax_rates; v_calc record;
  v_band public.revenue_value_bands; v_subtype public.revenue_supply_subtypes;
  v_before jsonb; v_window integer; v_today date;
  v_dg bigint; v_dt bigint; v_dn bigint;
  v_gross bigint := 0; v_tax bigint := 0; v_net bigint := 0;
  v_count integer := 0;
  v_target_period text;
  v_date_moved boolean;
  v_reason text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  perform app.require_any_revenue_edit_capability();

  select * into v_entry from public.revenue_entries
   where id = p_id and org_id = v_org;
  if v_entry.id is null then
    perform app.refuse('KM015', 'unknown_entity',
      'That revenue entry does not exist.', '{}'::jsonb);
  end if;

  -- A voided document is immutable. Correction after a void is a new document, which is
  -- what void-and-re-enter means (spec §14, D-006).
  if v_entry.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This revenue entry has been voided. Corrections are made by recording a new entry.',
      '{}'::jsonb);
  end if;

  -- Ownership. Without `revenue.edit.all` for this property, a caller may correct only
  -- what they recorded themselves.
  if not public.has_capability('revenue.edit.all', v_entry.business_unit_id) then
    perform app.require_capability('revenue.edit', v_entry.business_unit_id);
    if v_entry.created_by <> v_actor then
      perform app.refuse('KM001', 'missing_capability',
        'You may only change entries you recorded yourself.', '{}'::jsonb);
    end if;
  end if;

  -- ── Moving the date is its own act (spec §9) ────────────────────────────────
  --
  -- Decided from canonical state, by comparing **dates**. The period-key comparison
  -- below decides which locks to check and is a different question: 15 June to 20 June
  -- is a business-date correction and stays inside one period, so a guard keyed on the
  -- period would have missed most real corrections.
  v_date_moved := p_business_date is distinct from v_entry.business_date;

  if v_date_moved then
    perform app.require_capability('transaction.correct.business_date',
                                   v_entry.business_unit_id);

    -- Every kind of whitespace. `btrim` with one argument strips spaces alone, which
    -- would let a single tab stand in for a stated reason.
    v_reason := regexp_replace(coalesce(p_correction_reason, ''),
                               '^\s+|\s+$', '', 'g');
    if length(v_reason) = 0 then
      perform app.refuse('KM008', 'reason_required',
        'Changing the business date of a recorded sale always states why. '
        'The reason is kept with the correction.',
        jsonb_build_object('revenue_entry_id', p_id,
                           'from', v_entry.business_date,
                           'to',   p_business_date));
    end if;
  end if;

  -- Configuration, not a constant (spec §13.3).
  select coalesce((os.value)::text::integer, 7) into v_window
    from public.org_settings os
   where os.org_id = v_org and os.key = 'edit_window_days';

  v_today := app.revenue_window_today(p_id);

  -- Inclusive of its last day: a business date of D is editable on D+7 and refused on
  -- D+8 (D-065). `transaction.correct.beyond_window` lifts the *age* rule and nothing
  -- else — every period check below still runs, and it authorises no date move.
  if (v_today - v_entry.business_date) > coalesce(v_window, 7)
     and not public.has_capability_anywhere('transaction.correct.beyond_window') then
    perform app.refuse('KM021', 'edit_window_expired',
      format('This entry is more than %s days old and can no longer be changed here.',
             coalesce(v_window, 7)),
      jsonb_build_object('business_date', v_entry.business_date,
                         'days_elapsed', v_today - v_entry.business_date,
                         'window_days', coalesce(v_window, 7)));
  end if;

  -- **Both** periods. The one the entry is in, and the one it would move to (D-124).
  perform app.require_period_open(v_entry.pnl_period_key, v_entry.business_unit_id);
  v_target_period := to_char(p_business_date, 'YYYY-MM');
  if v_target_period <> v_entry.pnl_period_key then
    perform app.require_period_open(v_target_period, v_entry.business_unit_id);
  end if;

  -- Concurrency, after authority and state, so a caller without permission never learns
  -- the current version (D-021, D-046).
  if v_entry.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'Somebody else changed this revenue entry while you were working on it.',
      jsonb_build_object('expected', p_base_row_version,
                         'actual', v_entry.row_version));
  end if;

  if jsonb_array_length(coalesce(p_components, '[]'::jsonb)) = 0 then
    perform app.refuse('KM024', 'revenue_without_components',
      'A revenue entry must have at least one component.', '{}'::jsonb);
  end if;

  v_before := to_jsonb(v_entry);

  -- The old components stop being the explanation of this document. The audit row below
  -- carries them, so the pre-edit figures remain evidence (spec §14).
  delete from public.revenue_components where revenue_entry_id = p_id;

  for v_comp in select * from jsonb_array_elements(p_components)
  loop
    -- The server resolves, against the **new** business date. A correction that moves an
    -- entry to a date where another rule applies gets that rule, not the old snapshot.
    v_rule := app.resolve_revenue_rule(
      v_entry.revenue_category_id, p_business_date,
      nullif(v_comp->>'value_band_id', '')::uuid,
      nullif(v_comp->>'supply_subtype_id', '')::uuid,
      nullif(v_comp->>'premises_status_code', ''));

    select * into v_calc from app.revenue_compute(
      (v_comp->>'entered_amount_minor')::bigint, v_rule.rate_bp, v_rule.treatment);

    -- Compared, never used (D-114).
    v_dg := nullif(v_comp->>'declared_gross_minor', '')::bigint;
    v_dt := nullif(v_comp->>'declared_tax_minor', '')::bigint;
    v_dn := nullif(v_comp->>'declared_net_minor', '')::bigint;

    if (v_dg is not null and v_dg <> v_calc.gross)
       or (v_dt is not null and v_dt <> v_calc.tax)
       or (v_dn is not null and v_dn <> v_calc.net) then
      perform app.refuse('KM030', 'tax_configuration_mismatch',
        'The tax on this entry has changed since it was prepared. Review the current '
        'figures and record it again.',
        jsonb_build_object(
          'entered_amount_minor', (v_comp->>'entered_amount_minor')::bigint,
          'declared', jsonb_build_object('gross', v_dg, 'tax', v_dt, 'net', v_dn),
          'server',   jsonb_build_object('gross', v_calc.gross, 'tax', v_calc.tax,
                                         'net', v_calc.net),
          'tax_rule_id', v_rule.id, 'rate_bp', v_rule.rate_bp,
          'treatment', v_rule.treatment));
    end if;

    select * into v_band from public.revenue_value_bands where id = v_rule.value_band_id;
    select * into v_subtype from public.revenue_supply_subtypes
     where id = v_rule.supply_subtype_id;

    insert into public.revenue_components (
      id, org_id, revenue_entry_id, entered_amount_minor, entered_basis,
      gross_amount_minor, tax_amount_minor, net_amount_minor,
      tax_rule_id, tax_rate_bp, tax_treatment,
      value_band_id, value_band_label, value_band_floor_minor, value_band_ceiling_minor,
      supply_subtype_id, supply_subtype_label, premises_status_code)
    values (
      coalesce(nullif(v_comp->>'id','')::uuid, extensions.gen_random_uuid()),
      v_org, p_id,
      (v_comp->>'entered_amount_minor')::bigint,
      v_rule.input_basis,
      v_calc.gross, v_calc.tax, v_calc.net,
      v_rule.id, v_rule.rate_bp, v_rule.treatment,
      v_rule.value_band_id, v_band.label, v_band.floor_minor, v_band.ceiling_minor,
      v_rule.supply_subtype_id, v_subtype.label, v_rule.premises_status_code);

    v_gross := v_gross + v_calc.gross;
    v_tax   := v_tax   + v_calc.tax;
    v_net   := v_net   + v_calc.net;
    v_count := v_count + 1;
  end loop;

  -- The business unit, the category and the transaction number are **not** in this list.
  -- The number belongs to the document's identity and survives every correction; the unit
  -- and the category are not editable, because an edit that moved revenue between
  -- properties would be a scope transfer rather than a correction.
  update public.revenue_entries
     set business_date  = p_business_date,
         pnl_period_key = v_target_period,
         entry_kind     = p_entry_kind,
         source_reference = p_source_reference,
         notes          = p_notes,
         row_version    = row_version + 1,
         updated_at     = now(),
         updated_by     = v_actor
   where id = p_id;

  perform app.write_audit(v_org, 'revenue_entry', p_id, 'edited', v_actor,
    v_before,
    jsonb_build_object('business_date', p_business_date,
                       'components', v_count,
                       'gross_minor', v_gross, 'tax_minor', v_tax, 'net_minor', v_net),
    null, v_entry.business_unit_id, p_mutation_id);

  -- A distinct action, so "which trading days were moved, by whom, and why" is answerable
  -- by reading one action rather than by diffing every edited row. Written only on the
  -- moved branch, and after the replay guard, so a redelivery produces no second effect.
  if v_date_moved then
    perform app.write_audit(v_org, 'revenue_entry', p_id, 'business_date_corrected',
      v_actor,
      jsonb_build_object('business_date', v_entry.business_date,
                         'pnl_period_key', v_entry.pnl_period_key),
      jsonb_build_object('business_date', p_business_date,
                         'pnl_period_key', v_target_period),
      v_reason, v_entry.business_unit_id, p_mutation_id);
  end if;

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'update',
    jsonb_build_object('id', p_id,
                       'txn_number', v_entry.txn_number,
                       'financial_year', v_entry.financial_year,
                       'row_version', v_entry.row_version + 1,
                       'status', 'updated',
                       'business_date_corrected', v_date_moved,
                       'components', v_count,
                       'gross_minor', v_gross, 'tax_minor', v_tax, 'net_minor', v_net));
end; $$;

-- The old overload goes: two functions of one name make every call ambiguous, and
-- PostgREST would refuse them all.
drop function if exists public.revenue_update(
  uuid, integer, date, jsonb, text, text, text, uuid);

revoke all on function public.revenue_update(
  uuid, integer, date, jsonb, text, text, text, text, uuid) from public, anon;
grant execute on function public.revenue_update(
  uuid, integer, date, jsonb, text, text, text, text, uuid) to authenticated;

-- ── Invariants ───────────────────────────────────────────────────────────────
do $$
declare v_def text; v_count integer; v_leak text;
begin
  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'revenue_update';
  if v_count <> 1 then
    raise exception 'revenue_update has % overloads; exactly one is the contract', v_count;
  end if;

  v_def := pg_get_functiondef(
    'public.revenue_update(uuid,integer,date,jsonb,text,text,text,text,uuid)'::regprocedure);

  -- What this migration adds, and what it must not have disturbed. Asserted by name,
  -- because a restatement is exactly where a guard quietly goes missing.
  if v_def not like '%transaction.correct.business_date%' then
    raise exception 'the business-date correction capability is not evaluated';
  end if;
  if v_def not like '%business_date_corrected%' then
    raise exception 'the distinct correction audit action is missing';
  end if;
  if v_def not like '%p_business_date is distinct from v_entry.business_date%' then
    raise exception 'the date move is not detected from canonical state';
  end if;
  if v_def not like '%require_period_open(v_entry.pnl_period_key%' then
    raise exception 'the source-period guard is gone (D-124)';
  end if;
  if v_def not like '%resolve_revenue_rule%' then
    raise exception 'the server no longer re-resolves the tax (D-114)';
  end if;
  if v_def not like '%transaction.correct.beyond_window%' then
    raise exception 'the edit-window capability is no longer evaluated';
  end if;
  -- And the two things a correction must never touch.
  if v_def like '%set%txn_number =%' then
    raise exception 'the transaction number must survive every correction';
  end if;
  if v_def like '%p_business_unit_id%' or v_def like '%p_revenue_category_id%' then
    raise exception 'a correction may not move revenue between properties (D-124)';
  end if;

  if not has_function_privilege('authenticated',
        'public.revenue_update(uuid,integer,date,jsonb,text,text,text,text,uuid)',
        'EXECUTE') then
    raise exception 'revenue_update must be callable by authenticated';
  end if;
  if has_function_privilege('anon',
        'public.revenue_update(uuid,integer,date,jsonb,text,text,text,text,uuid)',
        'EXECUTE') then
    raise exception 'revenue_update is reachable by anon';
  end if;

  select string_agg(p.proname, ', ') into v_leak
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_leak is not null then
    raise exception 'a client role can execute functions in app: %', v_leak;
  end if;

  -- No second correction endpoint appeared on either side. One documented contract, one
  -- shipped contract (D-127).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'app')
                and p.proname in ('revenue_correct_business_date',
                                  'expense_correct_business_date')) then
    raise exception 'a second correction endpoint exists';
  end if;
end $$;
