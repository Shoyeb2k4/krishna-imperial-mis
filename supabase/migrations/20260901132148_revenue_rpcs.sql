-- Server migration ledger: 20260901132148  revenue_rpcs
--
-- One file per ledger version (A0). The previous Slice 4 commit collapsed seven
-- ledger versions into two files, which is not provenance.
--
-- 4 · The mutation boundary
-- ═════════════════════════════════════════════════════════════════════════════
--
-- The caller supplies FACTS and ENTERED AMOUNTS. It does not get to dictate the rate, the
-- tax, the net or the rule snapshot: the server resolves and computes those, and its
-- answer is canonical (D-037).

create or replace function public.revenue_tax_rule_create(
  p_revenue_category_id uuid,
  p_rate_bp             integer,
  p_treatment           text,
  p_effective_from      date,
  p_input_basis         text,
  p_effective_to        date default null,
  p_value_band_id       uuid default null,
  p_supply_subtype_id   uuid default null,
  p_premises_status_code text default null,
  p_note                text default null,
  p_mutation_id         uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_unit uuid; v_replay jsonb; v_id uuid;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Capability before existence (D-046): an unauthorised caller must not be able to use
  -- "unknown category" versus "no permission" to discover what exists.
  perform app.require_capability_anywhere('tax.manage');

  select business_unit_id into v_unit
    from public.revenue_categories
   where id = p_revenue_category_id and org_id = v_org;
  if v_unit is null then
    perform app.refuse('KM015', 'unknown_entity', 'That revenue category does not exist.', '{}'::jsonb);
  end if;
  perform app.require_capability('tax.manage', v_unit);

  -- Serialise configuration for this category BEFORE validating, so two concurrent
  -- writers cannot each validate against a state that does not yet contain the other's
  -- row and jointly create an ambiguous set (D-095).
  perform app.lock_revenue_category(v_org, p_revenue_category_id);

  insert into public.revenue_tax_rates (
    org_id, business_unit_id, revenue_category_id, rate_bp, treatment,
    effective_from, effective_to, input_basis, value_band_id,
    supply_subtype_id, premises_status_code, note, created_by)
  values (
    v_org, v_unit, p_revenue_category_id, p_rate_bp, p_treatment,
    p_effective_from, p_effective_to, p_input_basis, p_value_band_id,
    p_supply_subtype_id, p_premises_status_code, p_note, v_actor)
  returning id into v_id;

  -- The trigger validates too; calling it here means the refusal happens inside this
  -- function, where the lock is provably already held.
  perform app.assert_revenue_rules_unambiguous(v_id);

  perform app.write_audit(v_org, 'revenue_tax_rate', v_id, 'created', v_actor, null,
    jsonb_build_object('rate_bp', p_rate_bp, 'treatment', p_treatment,
                       'input_basis', p_input_basis, 'effective_from', p_effective_from,
                       'value_band_id', p_value_band_id,
                       'supply_subtype_id', p_supply_subtype_id,
                       'premises_status_code', p_premises_status_code),
    null, v_unit, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_tax_rate', v_id, 'create',
    jsonb_build_object('id', v_id, 'status', 'created'));
end; $$;

create or replace function public.revenue_tax_rule_end_date(
  p_rule_id uuid, p_effective_to date, p_mutation_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_rule public.revenue_tax_rates; v_replay jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_capability_anywhere('tax.manage');

  select * into v_rule from public.revenue_tax_rates where id = p_rule_id and org_id = v_org;
  if not found then
    perform app.refuse('KM015', 'unknown_entity', 'That tax rule does not exist.', '{}'::jsonb);
  end if;
  perform app.require_capability('tax.manage', v_rule.business_unit_id);

  -- End-dating changes applicability, so it takes the same lock.
  perform app.lock_revenue_category(v_org, v_rule.revenue_category_id);

  update public.revenue_tax_rates
     set effective_to = p_effective_to, updated_at = now(), row_version = row_version + 1
   where id = p_rule_id;

  perform app.write_audit(v_org, 'revenue_tax_rate', p_rule_id, 'end_dated', v_actor,
    to_jsonb(v_rule), jsonb_build_object('effective_to', p_effective_to),
    null, v_rule.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_tax_rate', p_rule_id, 'end_date',
    jsonb_build_object('id', p_rule_id, 'status', 'ended'));
end; $$;

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
    v_count := v_count + 1;
  end loop;

  -- Numbering only after every validation has passed, so a refused attempt burns no
  -- number.
  select number, financial_year into v_number, v_fy
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
                       'financial_year', v_fy, 'row_version', 1, 'status', 'created'));
end; $$;

create or replace function public.revenue_void(
  p_id uuid, p_base_row_version integer, p_reason text, p_mutation_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_entry public.revenue_entries; v_replay jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_capability_anywhere('revenue.void');

  if coalesce(trim(p_reason), '') = '' then
    perform app.refuse('KM008', 'reason_required', 'A void must state why.', '{}'::jsonb);
  end if;

  select * into v_entry from public.revenue_entries where id = p_id and org_id = v_org;
  if not found then
    perform app.refuse('KM015', 'unknown_entity', 'That revenue entry does not exist.', '{}'::jsonb);
  end if;

  perform app.require_capability('revenue.void', v_entry.business_unit_id);
  perform app.require_period_open(v_entry.pnl_period_key, v_entry.business_unit_id);

  -- A different mutation voiding an already-voided document with a matching version is an
  -- audited no-op; a stale one is a conflict (D-021).
  if v_entry.voided_at is not null and v_entry.row_version = p_base_row_version then
    return app.remember_mutation(p_mutation_id, v_org, v_actor,
      'revenue_entry', p_id, 'void',
      jsonb_build_object('id', p_id, 'row_version', v_entry.row_version,
                         'status', 'already_voided'));
  end if;

  if v_entry.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'This revenue entry changed since you loaded it. Review the latest version before voiding.',
      jsonb_build_object('expected', p_base_row_version, 'actual', v_entry.row_version));
  end if;

  update public.revenue_entries
     set voided_at = now(), voided_by = v_actor, void_reason = p_reason,
         row_version = row_version + 1, updated_at = now(), updated_by = v_actor
   where id = p_id;

  perform app.write_audit(v_org, 'revenue_entry', p_id, 'voided', v_actor,
    to_jsonb(v_entry), jsonb_build_object('void_reason', p_reason),
    p_reason, v_entry.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'void',
    jsonb_build_object('id', p_id, 'row_version', v_entry.row_version + 1, 'status', 'voided'));
end; $$;

-- Nothing is callable that has not been reviewed (D-044).
revoke all on function public.revenue_tax_rule_create(uuid, integer, text, date, text, date, uuid, uuid, text, text, uuid) from public, anon;
revoke all on function public.revenue_tax_rule_end_date(uuid, date, uuid) from public, anon;
revoke all on function public.revenue_create(uuid, uuid, uuid, date, jsonb, text, text, text, timestamptz, uuid) from public, anon;
revoke all on function public.revenue_void(uuid, integer, text, uuid) from public, anon;

grant execute on function public.revenue_tax_rule_create(uuid, integer, text, date, text, date, uuid, uuid, text, text, uuid) to authenticated;
grant execute on function public.revenue_tax_rule_end_date(uuid, date, uuid) to authenticated;
grant execute on function public.revenue_create(uuid, uuid, uuid, date, jsonb, text, text, text, timestamptz, uuid) to authenticated;
grant execute on function public.revenue_void(uuid, integer, text, uuid) to authenticated;

-- The internal helpers stay in `app`, which `authenticated` cannot reach.
revoke all on function app.resolve_revenue_rule(uuid, date, uuid, uuid, text) from public, anon, authenticated;
revoke all on function app.revenue_compute(bigint, integer, text) from public, anon, authenticated;
revoke all on function app.next_revenue_number(uuid, date) from public, anon, authenticated;
revoke all on function app.lock_revenue_category(uuid, uuid) from public, anon, authenticated;
revoke all on function app.revenue_financial_year(date) from public, anon, authenticated;
revoke all on function app.assert_revenue_rules_unambiguous(uuid) from public, anon, authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
