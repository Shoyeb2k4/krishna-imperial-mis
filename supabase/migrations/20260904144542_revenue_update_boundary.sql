-- Correcting revenue: the authoritative boundary.
--
-- Modelled on `expense_update`, which is the proven correction path, and differing from it
-- in exactly three places — each of them deliberate and recorded.
--
-- 1. **The server re-resolves the tax.** An expense's total is a fact the operator
--    supplies; a revenue figure's is not. So the caller sends entered amounts and the
--    facts that select a rule, and the server resolves and computes gross, tax and net
--    itself. Declared figures are compared and never used, exactly as `revenue_create`
--    does since D-114, so a rate that changed between opening the form and saving surfaces
--    as KM030 rather than as a document quietly holding different money.
--
-- 2. **Both the source and the target period are checked.** `expense_update` checks only
--    the period the document is moving *to*. Spec §13.4 says a closed period rejects
--    "every create, edit, void and business-date correction affecting that period", and a
--    correction that lifts a figure *out* of a closed month affects it. Checking only the
--    destination would make an edit a way to reopen a period nobody reopened.
--
-- 3. **The business unit and the revenue category are immutable.** Nothing in the binding
--    specification authorises moving recorded revenue between properties, and an edit that
--    could would be a scope transfer wearing a correction's clothes. Correct by void and
--    re-enter, which is what spec §14 says financial correction is.

-- ── The capability an accountant needs to correct somebody else's entry ──────
--
-- Revenue shipped with a single `revenue.edit`, where expenses have `expense.edit.own`
-- and `expense.edit.all`. Without the split there is no configured basis for "a Manager
-- corrects their own, an Accountant corrects anybody's" — the distinction spec §13.2
-- draws between the roles and D-072a already implements for expenses.
--
-- `revenue.edit` keeps its meaning: correct entries you recorded. `revenue.edit.all` is
-- added beside it, granted to exactly the roles that hold `expense.edit.all`.
--
-- Stated as a literal row rather than copied from `revenue.edit` with a select. The
-- catalogue is what the client's capability enum is checked against, and a reviewer -- or
-- the parity assertion -- has to be able to read the category here rather than infer it
-- from another row.
insert into public.capabilities (code, category, description) values
  ('revenue.edit.all', 'revenue',
   'Correct revenue recorded by anybody, within the same period and window rules.')
on conflict (code) do nothing;

insert into public.role_capabilities (role_id, capability_code)
select r.id, 'revenue.edit.all'
  from public.roles r
 where r.code in ('accountant', 'owner')
on conflict do nothing;

-- ── The date the edit window is measured against ─────────────────────────────
--
-- The property's current **business date**, never the database session's calendar date.
-- The session runs in UTC, and D-067 records the half hour a night in which the two
-- disagreed and quietly granted an extra day of window.
create or replace function app.revenue_window_today(p_entry_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select app.business_date_at(now(), bu.timezone, bu.business_day_cutoff)
    from public.revenue_entries e
    join public.business_units bu on bu.id = e.business_unit_id
   where e.id = p_entry_id;
$$;

comment on function app.revenue_window_today(uuid) is
  'The property business date a revenue edit window is measured against (D-067). A revenue entry charges exactly one property, so unlike an expense there is no greatest-of to take.';

revoke all on function app.revenue_window_today(uuid) from public, anon, authenticated;

-- ── Either form of edit capability, checked before existence ─────────────────
--
-- Permission before existence (D-046): a caller who may correct nothing anywhere learns
-- nothing about which documents exist. Either form counts, for the reason D-065 records —
-- asking for the own-scope form specifically refused the one role that exists to correct
-- other people's entries.
create or replace function app.require_any_revenue_edit_capability()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.has_capability_anywhere('revenue.edit')
     or public.has_capability_anywhere('revenue.edit.all') then
    return;
  end if;
  perform app.refuse('KM001', 'missing_capability',
    'You do not have permission to correct revenue.', '{}'::jsonb);
end;
$$;

revoke all on function app.require_any_revenue_edit_capability()
  from public, anon, authenticated;

create or replace function public.revenue_update(
  p_id                uuid,
  p_base_row_version  integer,
  p_business_date     date,
  p_components        jsonb,
  p_entry_kind        text default 'daily_summary',
  p_source_reference  text default null,
  p_notes             text default null,
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

  -- Configuration, not a constant (spec §13.3).
  select coalesce((os.value)::text::integer, 7) into v_window
    from public.org_settings os
   where os.org_id = v_org and os.key = 'edit_window_days';

  v_today := app.revenue_window_today(p_id);

  -- Inclusive of its last day: a business date of D is editable on D+7 and refused on
  -- D+8 (D-065). `transaction.correct.beyond_window` lifts the *age* rule and nothing
  -- else — every period check below still runs.
  if (v_today - v_entry.business_date) > coalesce(v_window, 7)
     and not public.has_capability_anywhere('transaction.correct.beyond_window') then
    perform app.refuse('KM021', 'edit_window_expired',
      format('This entry is more than %s days old and can no longer be changed here.',
             coalesce(v_window, 7)),
      jsonb_build_object('business_date', v_entry.business_date,
                         'days_elapsed', v_today - v_entry.business_date,
                         'window_days', coalesce(v_window, 7)));
  end if;

  -- **Both** periods. The one the entry is in, and the one it would move to.
  --
  -- Checking only the destination would make an edit a way to lift a figure out of a
  -- closed month — reopening a period nobody reopened, which spec §13.4 refuses and only
  -- the Owner may do deliberately. `expense_update` checks the target alone; that is
  -- recorded as a finding rather than copied.
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

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'update',
    jsonb_build_object('id', p_id,
                       'txn_number', v_entry.txn_number,
                       'financial_year', v_entry.financial_year,
                       'row_version', v_entry.row_version + 1,
                       'status', 'updated',
                       'components', v_count,
                       'gross_minor', v_gross, 'tax_minor', v_tax, 'net_minor', v_net));
end; $$;

revoke all on function public.revenue_update(uuid, integer, date, jsonb, text, text, text, uuid)
  from public, anon;
grant execute on function public.revenue_update(uuid, integer, date, jsonb, text, text, text, uuid)
  to authenticated;

-- ── Invariants, asserted rather than described ───────────────────────────────
do $$
declare v_leak text; v_holders integer;
begin
  -- The new capability is actually granted to somebody, or it is the unsatisfiable
  -- policy D-116 records in a new place.
  select count(*) into v_holders
    from public.role_capabilities where capability_code = 'revenue.edit.all';
  if v_holders = 0 then
    raise exception 'revenue.edit.all is granted to no role';
  end if;

  -- The internal helpers stay internal. Postgres grants EXECUTE to PUBLIC on every new
  -- function, and an explicit revoke is the only thing that undoes it (D-044, D-101).
  select string_agg(p.proname, ', ') into v_leak
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_leak is not null then
    raise exception 'a client role can execute functions in app: %', v_leak;
  end if;

  if not has_function_privilege('authenticated',
        'public.revenue_update(uuid,integer,date,jsonb,text,text,text,uuid)', 'EXECUTE') then
    raise exception 'revenue_update must be callable by authenticated';
  end if;
  if has_function_privilege('anon',
        'public.revenue_update(uuid,integer,date,jsonb,text,text,text,uuid)', 'EXECUTE') then
    raise exception 'revenue_update is reachable by anon';
  end if;
end $$;
