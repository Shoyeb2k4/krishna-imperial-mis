-- ─────────────────────────────────────────────────────────────────────────────
-- 0012 · Vendor, tax and period RPCs
--
-- Same contract as 0011: caller → capability → scope → state → version, all re-decided
-- here, none of it taken from the request. Archiving and restoring a vendor go through
-- `master_archive` / `master_restore`, and renaming one goes through `master_rename`, so
-- a vendor obeys the same D-038 acknowledgement and D-039 archive rules as every other
-- master rather than a parallel set that could drift.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Vendors (owner requirement §12) ──────────────────────────────────────────
-- Name is the only requirement. GSTIN, phone, address, notes and the two defaults are
-- optional and stay optional — a supplier without a GSTIN is an ordinary supplier, not a
-- validation failure.
create or replace function public.vendor_create(
  p_code        text,
  p_name        text,
  p_attributes  jsonb default '{}'::jsonb,
  p_mutation_id uuid  default null,
  p_id          uuid  default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  v_id     uuid := coalesce(p_id, extensions.gen_random_uuid());
  v_unit   uuid := nullif(p_attributes->>'default_business_unit_id', '')::uuid;
  v_cat    uuid := nullif(p_attributes->>'default_category_id', '')::uuid;
  v_replay jsonb;
  v_result jsonb;
  v_name   text := btrim(coalesce(p_name, ''));
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  if length(v_name) = 0 then
    perform app.refuse('KM012', 'name_required', 'A vendor needs a name.');
  end if;
  if p_code !~ '^[A-Z0-9_]{2,32}$' then
    perform app.refuse('KM009', 'invalid_code',
      'A permanent code must be 2 to 32 characters of A-Z, 0-9 and underscore.',
      jsonb_build_object('code', p_code));
  end if;

  -- A vendor pinned to one property is administered by someone scoped to it; an
  -- unpinned, company-wide supplier needs the permission anywhere.
  if v_unit is null then
    perform app.require_capability_anywhere('masters.manage');
  else
    perform app.require_capability('masters.manage', v_unit);
  end if;

  begin
    insert into public.vendors (id, org_id, code, name, gstin, phone, address, notes,
                                default_business_unit_id, default_category_id)
    values (v_id, v_org, p_code, v_name,
            nullif(btrim(coalesce(p_attributes->>'gstin', '')), ''),
            nullif(btrim(coalesce(p_attributes->>'phone', '')), ''),
            nullif(btrim(coalesce(p_attributes->>'address', '')), ''),
            nullif(btrim(coalesce(p_attributes->>'notes', '')), ''),
            v_unit, v_cat);
  exception when unique_violation then
    perform app.refuse('KM012', 'duplicate_name',
      format('A vendor called %L already exists. Use the existing record, or archive it '
             'first if it is no longer in use.', v_name),
      jsonb_build_object('name', v_name));
  end;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'vendor', 'entity_id', v_id,
    'code', p_code, 'name', v_name, 'row_version', 1);

  perform app.write_audit(v_org, 'vendor', v_id, 'created', v_actor,
    null::jsonb, v_result, null, v_unit, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'vendor', v_id,
                               'create', v_result);
end;
$$;

-- Editing the optional detail. The **name** is not changed here: it goes through
-- `master_rename`, which carries the D-038 acknowledgement a vendor with history needs.
create or replace function public.vendor_update(
  p_id               uuid,
  p_base_row_version integer,
  p_attributes       jsonb,
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
  v        record;
  v_replay jsonb;
  v_result jsonb;
  v_before jsonb;
  v_unit   uuid;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  select * into v from public.vendors where id = p_id and org_id = v_org;
  if v.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That vendor does not exist.',
      jsonb_build_object('entity_id', p_id));
  end if;

  if v.default_business_unit_id is null then
    perform app.require_capability_anywhere('masters.manage');
  else
    perform app.require_capability('masters.manage', v.default_business_unit_id);
  end if;
  perform app.require_version('vendor', p_id, v.row_version, p_base_row_version);

  v_unit := case when p_attributes ? 'default_business_unit_id'
                 then nullif(p_attributes->>'default_business_unit_id', '')::uuid
                 else v.default_business_unit_id end;

  -- Moving a vendor to a property also needs permission over the destination, or a
  -- scoped administrator could quietly claim a company-wide supplier.
  if v_unit is distinct from v.default_business_unit_id and v_unit is not null then
    perform app.require_capability('masters.manage', v_unit);
  end if;

  v_before := to_jsonb(v) - 'created_at' - 'updated_at' - 'change_seq';

  update public.vendors set
    gstin                    = case when p_attributes ? 'gstin'
                                    then nullif(btrim(coalesce(p_attributes->>'gstin', '')), '')
                                    else gstin end,
    phone                    = case when p_attributes ? 'phone'
                                    then nullif(btrim(coalesce(p_attributes->>'phone', '')), '')
                                    else phone end,
    address                  = case when p_attributes ? 'address'
                                    then nullif(btrim(coalesce(p_attributes->>'address', '')), '')
                                    else address end,
    notes                    = case when p_attributes ? 'notes'
                                    then nullif(btrim(coalesce(p_attributes->>'notes', '')), '')
                                    else notes end,
    default_business_unit_id = v_unit,
    default_category_id      = case when p_attributes ? 'default_category_id'
                                    then nullif(p_attributes->>'default_category_id', '')::uuid
                                    else default_category_id end
  where id = p_id;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'vendor', 'entity_id', p_id,
    'row_version', v.row_version + 1);

  perform app.write_audit(v_org, 'vendor', p_id, 'updated', v_actor,
    v_before,
    (select to_jsonb(x) - 'created_at' - 'updated_at' - 'change_seq'
       from public.vendors x where x.id = p_id),
    null, v_unit, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'vendor', p_id,
                               'update', v_result);
end;
$$;

-- ── Tax rules (D-017, owner requirement §10) ─────────────────────────────────
create or replace function public.tax_rule_create(
  p_revenue_category_id uuid,
  p_rate_bp             integer,
  p_treatment           text,
  p_effective_from      date,
  p_effective_to        date default null,
  p_note                text default null,
  p_mutation_id         uuid default null,
  p_id                  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  v_unit   uuid;
  v_id     uuid := coalesce(p_id, extensions.gen_random_uuid());
  v_replay jsonb;
  v_result jsonb;
  -- `none` means no tax applies; a rate alongside it would be a stored contradiction.
  v_rate   integer := case when p_treatment = 'none' then 0 else p_rate_bp end;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  select rc.business_unit_id into v_unit
    from public.revenue_categories rc
   where rc.id = p_revenue_category_id and rc.org_id = v_org;
  if v_unit is null then
    perform app.refuse('KM015', 'unknown_entity', 'That revenue category does not exist.',
      jsonb_build_object('revenue_category_id', p_revenue_category_id));
  end if;

  perform app.require_capability('tax.manage', v_unit);

  if v_rate < 0 or v_rate > 10000 then
    perform app.refuse('KM007', 'rate_out_of_range', 'The rate must be between 0 and 100 percent.',
      jsonb_build_object('rate_bp', v_rate));
  end if;
  if p_effective_to is not null and p_effective_to <= p_effective_from then
    perform app.refuse('KM007', 'ends_before_it_starts',
      'The end date must be after the start date.',
      jsonb_build_object('effective_from', p_effective_from, 'effective_to', p_effective_to));
  end if;

  begin
    insert into public.revenue_tax_rates (
      id, org_id, business_unit_id, revenue_category_id, rate_bp, treatment,
      effective_from, effective_to, note, created_by)
    values (v_id, v_org, v_unit, p_revenue_category_id, v_rate, p_treatment,
            p_effective_from, p_effective_to, p_note, v_actor);
  exception when exclusion_violation then
    -- The half-open range constraint fired: some live rule already claims part of this
    -- period for this category.
    perform app.refuse('KM007', 'tax_period_overlap',
      'Another tax rule already covers part of that period for this category. Close the '
      'existing period first, or choose different dates.',
      jsonb_build_object('revenue_category_id', p_revenue_category_id,
                         'effective_from', p_effective_from,
                         'effective_to', p_effective_to));
  end;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'revenue_tax_rate', 'entity_id', v_id,
    'rate_bp', v_rate, 'treatment', p_treatment,
    'effective_from', p_effective_from, 'effective_to', p_effective_to,
    'row_version', 1);

  perform app.write_audit(v_org, 'revenue_tax_rate', v_id, 'tax_rule_created', v_actor,
    null::jsonb, v_result, p_note, v_unit, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'revenue_tax_rate', v_id,
                               'create', v_result);
end;
$$;

-- Changing a rate is never an edit to the old row. The current rule is closed on the day
-- the new one starts and a new row opens — **atomically**, in one transaction, so the
-- timeline is never briefly gapped, never briefly overlapped, and history is untouched.
create or replace function public.tax_rule_supersede(
  p_current_rule_id  uuid,
  p_base_row_version integer,
  p_rate_bp          integer,
  p_treatment        text,
  p_effective_from   date,
  p_note             text default null,
  p_mutation_id      uuid default null,
  p_new_id           uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  r        record;
  v_new    uuid := coalesce(p_new_id, extensions.gen_random_uuid());
  v_replay jsonb;
  v_result jsonb;
  v_rate   integer := case when p_treatment = 'none' then 0 else p_rate_bp end;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  select * into r from public.revenue_tax_rates
   where id = p_current_rule_id and org_id = v_org;
  if r.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That tax rule does not exist.',
      jsonb_build_object('entity_id', p_current_rule_id));
  end if;

  perform app.require_capability('tax.manage', r.business_unit_id);
  perform app.require_version('revenue_tax_rate', p_current_rule_id, r.row_version,
                              p_base_row_version);

  if r.archived_at is not null then
    perform app.refuse('KM006', 'archived_master',
      'That tax rule has been archived. Create a new rule for the period instead.',
      jsonb_build_object('entity_id', p_current_rule_id));
  end if;
  if p_effective_from <= r.effective_from then
    perform app.refuse('KM007', 'ends_before_it_starts',
      'The new rate must start after the rule it replaces begins.',
      jsonb_build_object('current_effective_from', r.effective_from,
                         'proposed_effective_from', p_effective_from));
  end if;
  if r.effective_to is not null and p_effective_from >= r.effective_to then
    perform app.refuse('KM007', 'tax_period_overlap',
      'That rule has already ended. Create a new rule rather than superseding it.',
      jsonb_build_object('current_effective_to', r.effective_to));
  end if;

  -- Close first, open second. The half-open boundary means the closing date and the
  -- opening date are the same day and still do not overlap.
  update public.revenue_tax_rates
     set effective_to = p_effective_from
   where id = p_current_rule_id;

  begin
    insert into public.revenue_tax_rates (
      id, org_id, business_unit_id, revenue_category_id, rate_bp, treatment,
      effective_from, effective_to, note, created_by)
    values (v_new, v_org, r.business_unit_id, r.revenue_category_id, v_rate, p_treatment,
            p_effective_from, null, p_note, v_actor);
  exception when exclusion_violation then
    perform app.refuse('KM007', 'tax_period_overlap',
      'Another tax rule already covers part of that period for this category.',
      jsonb_build_object('revenue_category_id', r.revenue_category_id,
                         'effective_from', p_effective_from));
  end;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'revenue_tax_rate',
    'entity_id', v_new, 'superseded_id', p_current_rule_id,
    'rate_bp', v_rate, 'treatment', p_treatment, 'effective_from', p_effective_from,
    'row_version', 1, 'superseded_row_version', r.row_version + 1);

  perform app.write_audit(v_org, 'revenue_tax_rate', p_current_rule_id,
    'tax_rule_superseded', v_actor,
    jsonb_build_object('rate_bp', r.rate_bp, 'treatment', r.treatment,
                       'effective_from', r.effective_from, 'effective_to', r.effective_to),
    jsonb_build_object('rate_bp', r.rate_bp, 'treatment', r.treatment,
                       'effective_from', r.effective_from, 'effective_to', p_effective_from),
    p_note, r.business_unit_id, p_mutation_id);
  perform app.write_audit(v_org, 'revenue_tax_rate', v_new, 'tax_rule_created', v_actor,
    null::jsonb, v_result, p_note, r.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'revenue_tax_rate', v_new,
                               'supersede', v_result);
end;
$$;

create or replace function public.tax_rule_archive(
  p_rule_id          uuid,
  p_base_row_version integer,
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
  r        record;
  v_replay jsonb;
  v_result jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  select * into r from public.revenue_tax_rates where id = p_rule_id and org_id = v_org;
  if r.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That tax rule does not exist.',
      jsonb_build_object('entity_id', p_rule_id));
  end if;

  perform app.require_capability('tax.manage', r.business_unit_id);
  perform app.require_version('revenue_tax_rate', p_rule_id, r.row_version, p_base_row_version);

  if r.archived_at is not null then
    v_result := jsonb_build_object('status', 'unchanged', 'entity_type', 'revenue_tax_rate',
                                   'entity_id', p_rule_id, 'row_version', r.row_version);
    return app.remember_mutation(p_mutation_id, v_org, v_actor, 'revenue_tax_rate',
                                 p_rule_id, 'archive', v_result);
  end if;

  -- Archiving takes the row out of the exclusion constraint, which is exactly what lets a
  -- corrected rule occupy the same period afterwards (owner requirement §10).
  update public.revenue_tax_rates set archived_at = now() where id = p_rule_id;

  v_result := jsonb_build_object('status', 'applied', 'entity_type', 'revenue_tax_rate',
                                 'entity_id', p_rule_id, 'row_version', r.row_version + 1);

  perform app.write_audit(v_org, 'revenue_tax_rate', p_rule_id, 'archived', v_actor,
    jsonb_build_object('archived_at', null), jsonb_build_object('archived_at', now()),
    null, r.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'revenue_tax_rate',
                               p_rule_id, 'archive', v_result);
end;
$$;

-- ── Period close and reopen (spec §13.4, D-026) ──────────────────────────────
create or replace function public.period_close(
  p_period_key       text,
  p_business_unit_id uuid default null,
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
  v_lock   record;
  v_replay jsonb;
  v_result jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  if p_period_key !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    perform app.refuse('KM015', 'invalid_period',
      'A period is written as YYYY-MM.', jsonb_build_object('period_key', p_period_key));
  end if;

  -- Closing every property at once is an organisation-wide act and needs an
  -- organisation-wide grant. Closing one property needs the grant for that property.
  if p_business_unit_id is null then
    perform app.require_unscoped_capability('period.close');
  else
    perform app.require_capability('period.close', p_business_unit_id);
  end if;

  insert into public.period_locks (org_id, business_unit_id, period_key, state,
                                   closed_by, closed_at)
  values (v_org, p_business_unit_id, p_period_key, 'closed', v_actor, now())
  on conflict (org_id, period_key,
               coalesce(business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set state = 'closed', closed_by = v_actor, closed_at = now(),
                reopened_by = null, reopened_at = null, reopen_reason = null
  returning * into v_lock;

  insert into public.period_lock_events (org_id, period_lock_id, action, actor_id, mutation_id)
  values (v_org, v_lock.id, 'close', v_actor, p_mutation_id);

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'period_lock', 'entity_id', v_lock.id,
    'period_key', p_period_key, 'business_unit_id', p_business_unit_id,
    'state', 'closed', 'row_version', v_lock.row_version);

  perform app.write_audit(v_org, 'period_lock', v_lock.id, 'period_closed', v_actor,
    null::jsonb, v_result, null, p_business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'period_lock', v_lock.id,
                               'close', v_result);
end;
$$;

-- Reopening is deliberate, capability-gated and **always** carries a reason. There is no
-- path anywhere in this schema that reopens a period implicitly.
create or replace function public.period_reopen(
  p_period_key       text,
  p_reason           text,
  p_business_unit_id uuid default null,
  p_base_row_version integer default null,
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
  v_lock   record;
  v_replay jsonb;
  v_result jsonb;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  if p_business_unit_id is null then
    perform app.require_unscoped_capability('period.reopen');
  else
    perform app.require_capability('period.reopen', p_business_unit_id);
  end if;

  -- Checked after the capability, so somebody with no permission is not told how to
  -- phrase a request they cannot make anyway.
  if length(v_reason) = 0 then
    perform app.refuse('KM008', 'reason_required',
      'Reopening a closed period requires a reason. It is written to the audit trail.',
      jsonb_build_object('period_key', p_period_key));
  end if;

  select * into v_lock from public.period_locks
   where org_id = v_org and period_key = p_period_key
     and coalesce(business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(p_business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid);

  if v_lock.id is null or v_lock.state <> 'closed' then
    perform app.refuse('KM015', 'period_not_closed',
      'That period is not closed.',
      jsonb_build_object('period_key', p_period_key,
                         'business_unit_id', p_business_unit_id));
  end if;

  if p_base_row_version is not null then
    perform app.require_version('period_lock', v_lock.id, v_lock.row_version,
                                p_base_row_version);
  end if;

  update public.period_locks
     set state = 'open', reopened_by = v_actor, reopened_at = now(), reopen_reason = v_reason
   where id = v_lock.id;

  insert into public.period_lock_events (org_id, period_lock_id, action, reason,
                                         actor_id, mutation_id)
  values (v_org, v_lock.id, 'reopen', v_reason, v_actor, p_mutation_id);

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'period_lock', 'entity_id', v_lock.id,
    'period_key', p_period_key, 'business_unit_id', p_business_unit_id,
    'state', 'open', 'row_version', v_lock.row_version + 1);

  perform app.write_audit(v_org, 'period_lock', v_lock.id, 'period_reopened', v_actor,
    jsonb_build_object('state', 'closed'), jsonb_build_object('state', 'open'),
    v_reason, p_business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'period_lock', v_lock.id,
                               'reopen', v_result);
end;
$$;

grant execute on function public.vendor_create(text, text, jsonb, uuid, uuid) to authenticated;
grant execute on function public.vendor_update(uuid, integer, jsonb, uuid) to authenticated;
grant execute on function public.tax_rule_create(uuid, integer, text, date, date, text, uuid, uuid) to authenticated;
grant execute on function public.tax_rule_supersede(uuid, integer, integer, text, date, text, uuid, uuid) to authenticated;
grant execute on function public.tax_rule_archive(uuid, integer, uuid) to authenticated;
grant execute on function public.period_close(text, uuid, uuid) to authenticated;
grant execute on function public.period_reopen(text, text, uuid, integer, uuid) to authenticated;
