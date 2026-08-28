-- ─────────────────────────────────────────────────────────────────────────────
-- 0020 · Refuse on permission before revealing whether a record exists
--
-- Every mutation RPC loaded the target row first and refused with `unknown_entity` when
-- it was missing, only then checking capability. So a caller with no permission at all
-- could tell an existing id from a non-existent one by which refusal came back.
--
-- Normally that is a weak oracle, because ids are random. Here it is not: seeded master
-- ids are UUID v5 values derived from public code paths (D-040 / the seed), so anyone
-- can compute them and probe. The leak is small - it confirms the seeded structure, which
-- is in the repository anyway - but the fix is small too, and it makes the server agree
-- with the Dart `Authorizer`, which has always decided permission first.
--
-- The cheap organisation-wide check runs before the row is loaded; the precise
-- unit-scoped check still runs afterwards, because it needs to know which property the
-- row belongs to. An administrator can therefore still distinguish existence, which is
-- appropriate - they are entitled to.
--
-- The three master mutations and the two tax mutations are patched by rewriting their
-- stored definition rather than by restating them in full. That keeps this migration
-- honest about what it changes - one inserted line each - and the assertion at the end
-- fails the migration if the insertion did not take.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.master_usage(p_entity_type text, p_entity_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  m record;
  c record;
begin
  perform app.require_actor();
  perform app.require_capability_anywhere('masters.view');

  select * into m from app.master_locate(p_entity_type, p_entity_id);
  if m.table_name is null or m.org_id is distinct from app.current_org_id() then
    perform app.refuse('KM015', 'unknown_entity', 'That record does not exist.',
      jsonb_build_object('entity_type', p_entity_type, 'entity_id', p_entity_id));
  end if;
  perform app.require_master_capability('masters.view', m.is_org_level, m.business_unit_id);

  select * into c
    from public.master_usage_counters
   where entity_type = p_entity_type and entity_id = p_entity_id;

  return jsonb_build_object(
    'source',            'server',
    'entity_type',       p_entity_type,
    'entity_id',         p_entity_id,
    'transaction_count', coalesce(c.transaction_count, 0),
    'earliest',          c.earliest_business_date,
    'latest',            c.latest_business_date,
    'as_of',             now()
  );
end;
$$;

do $$
declare
  v_src text;
  v_fn  text;
begin
  foreach v_fn in array array['master_rename', 'master_archive', 'master_restore'] loop
    select pg_get_functiondef(p.oid) into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;

    v_src := replace(
      v_src,
      '  select * into m from app.master_locate(p_entity_type, p_entity_id);',
      '  perform app.require_capability_anywhere(''masters.manage'');' || chr(10) ||
      '  select * into m from app.master_locate(p_entity_type, p_entity_id);');

    if position('require_capability_anywhere' in v_src) = 0 then
      raise exception 'could not insert the guard into %', v_fn;
    end if;
    execute v_src;
  end loop;
end $$;

create or replace function public.user_role_revoke(
  p_grant_id    uuid,
  p_mutation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  g        record;
  v_replay jsonb;
  v_result jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_capability_anywhere('users.manage');

  select * into g from public.user_roles where id = p_grant_id and org_id = v_org;
  if g.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That grant does not exist.',
      jsonb_build_object('grant_id', p_grant_id));
  end if;

  if g.business_unit_id is null then
    perform app.require_unscoped_capability('users.manage');
  else
    perform app.require_capability('users.manage', g.business_unit_id);
  end if;

  update public.user_roles
     set revoked_at = now(), revoked_by = v_actor
   where id = p_grant_id and revoked_at is null;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'user_role', 'entity_id', p_grant_id,
    'revoked', true);

  perform app.write_audit(v_org, 'user_role', p_grant_id, 'role_revoked', v_actor,
    jsonb_build_object('revoked_at', null), jsonb_build_object('revoked_at', now()),
    null, g.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'user_role', p_grant_id,
                               'revoke', v_result);
end;
$$;

do $$
declare
  v_src text;
  v_fn  text;
begin
  foreach v_fn in array array['tax_rule_supersede', 'tax_rule_archive'] loop
    select pg_get_functiondef(p.oid) into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    v_src := replace(
      v_src,
      '  select * into r from public.revenue_tax_rates',
      '  perform app.require_capability_anywhere(''tax.manage'');' || chr(10) ||
      '  select * into r from public.revenue_tax_rates');
    if position('require_capability_anywhere' in v_src) = 0 then
      raise exception 'could not insert the guard into %', v_fn;
    end if;
    execute v_src;
  end loop;
end $$;

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
  perform app.require_capability_anywhere('masters.manage');

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

-- Confirm the guard really landed in the rewritten functions.
do $$
declare v_missing text;
begin
  select string_agg(p.proname, ', ')
    into v_missing
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('master_rename', 'master_archive', 'master_restore',
                       'tax_rule_supersede', 'tax_rule_archive', 'vendor_update',
                       'user_role_revoke', 'master_usage')
     and position('require_capability_anywhere' in pg_get_functiondef(p.oid)) = 0;
  if v_missing is not null then
    raise exception 'permission-before-existence guard missing from: %', v_missing;
  end if;
end $$;
