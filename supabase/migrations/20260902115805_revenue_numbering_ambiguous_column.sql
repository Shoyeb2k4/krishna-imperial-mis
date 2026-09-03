-- `revenue_create` has never successfully created a revenue entry.
--
-- `app.next_revenue_number` was declared `returns table(number text, financial_year text)`.
-- Those are OUT parameters, and inside the body `on conflict (org_id, financial_year)`
-- names the same identifier as the table column it targets, so plpgsql refuses the
-- statement outright:
--
--     column reference "financial_year" is ambiguous
--
-- Every call failed at the point a number is issued -- which is after every validation has
-- passed and after the entry and its components are inserted. The transaction rolls back,
-- so nothing was written and nothing was corrupted; the RPC simply could not work.
--
-- It survived Slice 4 because that slice proved the *boundary* -- RLS, grants, the
-- projection, the write-skew doctrine -- and never created a revenue entry through it. The
-- same shape as D-104: two correct halves and no test crossing between them, found the
-- first time something actually exercised the path.
--
-- A conflict target cannot be table-qualified, and plpgsql substitutes the variable before
-- the planner sees it, so the collision is removed by renaming the output columns. The
-- caller changes in the same migration, because those names are the contract between them.

drop function if exists app.next_revenue_number(uuid, date);

create or replace function app.next_revenue_number(p_org uuid, p_date date)
returns table (issued_number text, issued_financial_year text)
language plpgsql security definer set search_path = '' as $$
declare
  v_fy   text := app.revenue_financial_year(p_date);
  v_next bigint;
begin
  -- Concurrency-safe by construction: the upsert takes a row lock on exactly this
  -- (org, financial year), so two concurrent acceptances serialise on the counter and
  -- neither can read the same last_value. Gaps are avoided because the number is issued
  -- only after every validation has passed.
  insert into public.revenue_number_counters (org_id, financial_year, last_value)
       values (p_org, v_fy, 1)
  on conflict (org_id, financial_year)
    do update set last_value = public.revenue_number_counters.last_value + 1
  returning public.revenue_number_counters.last_value into v_next;

  return query select
    'KI-REV-' || v_fy || '-' || lpad(v_next::text, 6, '0'),
    v_fy;
end;
$$;

revoke all on function app.next_revenue_number(uuid, date) from public, anon, authenticated;

create or replace function public.revenue_create(
  p_id uuid,
  p_business_unit_id uuid,
  p_revenue_category_id uuid,
  p_business_date date,
  p_components jsonb,
  p_entry_kind text default 'daily_summary',
  p_source_reference text default null,
  p_notes text default null,
  p_captured_at timestamptz default null,
  p_mutation_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_replay jsonb; v_comp jsonb;
  v_rule public.revenue_tax_rates; v_calc record;
  v_number text; v_fy text;
  v_band public.revenue_value_bands; v_subtype public.revenue_supply_subtypes;
  v_count integer := 0;
  v_dg bigint; v_dt bigint; v_dn bigint;
  v_gross bigint := 0; v_tax bigint := 0; v_net bigint := 0;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  perform app.require_capability_anywhere('revenue.create');
  perform app.require_capability('revenue.create', p_business_unit_id);

  if not exists (
    select 1 from public.revenue_categories
     where id = p_revenue_category_id and org_id = v_org
       and business_unit_id = p_business_unit_id and archived_at is null
  ) then
    perform app.refuse('KM015', 'unknown_entity',
      'That revenue category does not belong to that business unit, or is archived.', '{}'::jsonb);
  end if;

  perform app.require_period_open(to_char(p_business_date, 'YYYY-MM'), p_business_unit_id);

  if jsonb_array_length(coalesce(p_components, '[]'::jsonb)) = 0 then
    perform app.refuse('KM024', 'revenue_without_components',
      'A revenue entry must have at least one component.', '{}'::jsonb);
  end if;

  insert into public.revenue_entries (
    id, org_id, business_unit_id, revenue_category_id, business_date,
    pnl_period_key, captured_at, entry_kind, source_reference, notes, created_by)
  values (
    p_id, v_org, p_business_unit_id, p_revenue_category_id, p_business_date,
    to_char(p_business_date, 'YYYY-MM'), coalesce(p_captured_at, now()),
    p_entry_kind, p_source_reference, p_notes, v_actor);

  for v_comp in select * from jsonb_array_elements(p_components)
  loop
    -- The server resolves. Anything the caller sent about rate or tax is ignored, not
    -- trusted and then checked.
    v_rule := app.resolve_revenue_rule(
      p_revenue_category_id, p_business_date,
      nullif(v_comp->>'value_band_id', '')::uuid,
      nullif(v_comp->>'supply_subtype_id', '')::uuid,
      nullif(v_comp->>'premises_status_code', ''));

    select * into v_calc from app.revenue_compute(
      (v_comp->>'entered_amount_minor')::bigint, v_rule.rate_bp, v_rule.treatment);

    -- Compared, never used.
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
    select * into v_subtype from public.revenue_supply_subtypes where id = v_rule.supply_subtype_id;

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

  -- Numbering only after every validation has passed, so a refused attempt burns no
  -- number.
  select issued_number, issued_financial_year into v_number, v_fy
    from app.next_revenue_number(v_org, p_business_date);

  update public.revenue_entries
     set txn_number = v_number, financial_year = v_fy
   where id = p_id;

  perform app.write_audit(v_org, 'revenue_entry', p_id, 'created', v_actor, null,
    jsonb_build_object('txn_number', v_number, 'business_date', p_business_date,
                       'components', v_count),
    null, p_business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'create',
    jsonb_build_object('id', p_id, 'txn_number', v_number,
                       'financial_year', v_fy, 'row_version', 1, 'status', 'created',
                       'components', v_count,
                       'gross_minor', v_gross, 'tax_minor', v_tax, 'net_minor', v_net));
end; $$;

revoke all on function public.revenue_create(uuid, uuid, uuid, date, jsonb, text, text, text, timestamptz, uuid) from public, anon;
grant execute on function public.revenue_create(uuid, uuid, uuid, date, jsonb, text, text, text, timestamptz, uuid) to authenticated;

-- The numbering helper works. Asserted here rather than discovered by a client again.
do $$
declare
  v_org uuid; v_num text; v_fy text;
  v_before bigint; v_after bigint; v_existed boolean;
begin
  select id into v_org from public.organizations limit 1;
  v_fy := app.revenue_financial_year(date '2026-06-15');

  select last_value into v_before
    from public.revenue_number_counters
   where org_id = v_org and financial_year = v_fy;
  v_existed := v_before is not null;

  select issued_number, issued_financial_year into v_num, v_fy
    from app.next_revenue_number(v_org, date '2026-06-15');

  if v_num is null or v_num !~ '^KI-REV-[0-9]{2}-[0-9]{2}-[0-9]{6}$' then
    raise exception 'next_revenue_number produced %', coalesce(v_num, '<null>');
  end if;

  select last_value into v_after
    from public.revenue_number_counters
   where org_id = v_org and financial_year = v_fy;
  if v_after <> coalesce(v_before, 0) + 1 then
    raise exception 'the counter did not advance exactly once (% -> %)', v_before, v_after;
  end if;

  -- Put the sequence back exactly as it was: this assertion must not consume a number a
  -- real entry would otherwise have carried, and must not leave a counter row behind if
  -- there was none.
  if v_existed then
    update public.revenue_number_counters
       set last_value = v_before
     where org_id = v_org and financial_year = v_fy;
  else
    delete from public.revenue_number_counters
     where org_id = v_org and financial_year = v_fy;
  end if;
end $$;

do $$
declare v_leak text;
begin
  select string_agg(p.proname, ', ') into v_leak
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_leak is not null then
    raise exception 'a client role can execute functions in app: %', v_leak;
  end if;
end $$;
