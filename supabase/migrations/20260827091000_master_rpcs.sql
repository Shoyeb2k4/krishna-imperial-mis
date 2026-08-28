-- ─────────────────────────────────────────────────────────────────────────────
-- 0011 · Master mutation RPCs — the only way a master ever changes
--
-- Clients hold no INSERT, UPDATE or DELETE grant on any master table (0010). Every
-- administrative mutation arrives here, and every one of these functions independently
-- verifies:
--
--     authenticated caller → capability → business-unit scope → record state
--                          → row version → the rule specific to the operation
--
-- Nothing is trusted from the request. The organisation comes from the caller's profile;
-- the business unit comes from the row being changed, not from a parameter; the row
-- version comes from the stored row. A client that sends `is_owner: true` has sent a
-- meaningless string.
--
-- Each returns jsonb. Refusals raise with a distinct SQLSTATE and a machine-readable
-- DETAIL payload, so the transaction rolls back and the UI can state the real reason.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Locating a master of any kind ────────────────────────────────────────────
-- One resolver, so no RPC invents its own table mapping. `is_org_level` marks the two
-- masters that belong to the company rather than to a property.
create or replace function app.master_locate(p_entity_type text, p_entity_id uuid)
returns table (
  table_name       text,
  org_id           uuid,
  business_unit_id uuid,
  code             text,
  name             text,
  archived_at      timestamptz,
  row_version      integer,
  is_org_level     boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_table   text;
  v_bu_expr text;
  v_org_lvl boolean := false;
begin
  case p_entity_type
    when 'business_unit'    then v_table := 'business_units';      v_bu_expr := 'id';
    when 'department'       then v_table := 'departments';         v_bu_expr := 'business_unit_id';
    when 'section'          then v_table := 'sections';            v_bu_expr := 'business_unit_id';
    when 'expense_category' then v_table := 'expense_categories';  v_bu_expr := 'business_unit_id';
    when 'revenue_category' then v_table := 'revenue_categories';  v_bu_expr := 'business_unit_id';
    when 'vendor'           then v_table := 'vendors';             v_bu_expr := 'default_business_unit_id';
                                 v_org_lvl := true;
    when 'payment_method'   then v_table := 'payment_methods';     v_bu_expr := 'null::uuid';
                                 v_org_lvl := true;
    else
      perform app.refuse('KM015', 'unknown_entity',
        format('%L is not a kind of master record.', p_entity_type),
        jsonb_build_object('entity_type', p_entity_type));
  end case;

  return query execute format(
    'select %L::text, m.org_id, %s, m.code, m.name, m.archived_at, m.row_version, %L::boolean
       from public.%I m where m.id = $1',
    v_table, v_bu_expr, v_org_lvl, v_table)
    using p_entity_id;
end;
$$;

-- A capability held with no unit restriction at all. Creating a business unit, or
-- anything that is not *about* one property, needs this rather than a scoped grant.
create or replace function app.require_unscoped_capability(p_capability text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
      from public.user_roles ur
      join public.role_capabilities rc on rc.role_id = ur.role_id
     where ur.user_id = (select auth.uid())
       and ur.revoked_at is null
       and ur.business_unit_id is null
       and rc.capability_code = p_capability
  ) then
    perform app.refuse('KM001', 'missing_capability',
      'This action affects the whole organisation and needs an unrestricted permission.',
      jsonb_build_object('capability', p_capability));
  end if;
end;
$$;

-- The capability check appropriate to one master: scoped to its property, unscoped for
-- an organisation-level record.
create or replace function app.require_master_capability(
  p_capability   text,
  p_is_org_level boolean,
  p_unit_id      uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_is_org_level then
    -- A vendor pinned to one property is still administered by someone scoped to it.
    if p_unit_id is null then
      perform app.require_capability_anywhere(p_capability);
    else
      perform app.require_capability(p_capability, p_unit_id);
    end if;
  else
    perform app.require_capability(p_capability, p_unit_id);
  end if;
end;
$$;

-- ── master_usage · the authoritative figure (owner requirement §11) ──────────
-- Served from the maintained counter, so it is O(1) by primary key and stays O(1) when
-- there are years of history. It never runs count(*) over financial rows.
--
-- `source` is always 'server' here, and the client maps it to `UsageSource.server`. A
-- local cache figure is a *lower bound* and must never be promoted to this (D-041).
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

-- ── master_create ────────────────────────────────────────────────────────────
create or replace function public.master_create(
  p_entity_type  text,
  p_parent_id    uuid,
  p_code         text,
  p_name         text,
  p_attributes   jsonb default '{}'::jsonb,
  p_mutation_id  uuid  default null,
  p_id           uuid  default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor   uuid;
  v_org     uuid;
  v_id      uuid := coalesce(p_id, extensions.gen_random_uuid());
  v_replay  jsonb;
  v_unit    uuid;
  v_dept    uuid;
  v_section uuid;
  v_result  jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  if p_code !~ '^[A-Z0-9_]{2,32}$' then
    perform app.refuse('KM009', 'invalid_code',
      'A permanent code must be 2 to 32 characters of A-Z, 0-9 and underscore. It can '
      'never be changed afterwards, so it is worth getting right.',
      jsonb_build_object('code', p_code));
  end if;
  if length(btrim(coalesce(p_name, ''))) = 0 then
    perform app.refuse('KM012', 'name_required', 'A name is required.');
  end if;

  case p_entity_type
    when 'business_unit' then
      perform app.require_unscoped_capability('masters.manage');
      insert into public.business_units (id, org_id, code, name, kind, timezone,
                                         business_day_cutoff, sort_order)
      values (v_id, v_org, p_code, btrim(p_name),
              coalesce(p_attributes->>'kind', 'other'),
              coalesce(p_attributes->>'timezone', 'Asia/Kolkata'),
              coalesce((p_attributes->>'business_day_cutoff')::time, '05:00'::time),
              coalesce((p_attributes->>'sort_order')::integer, 0));
      v_unit := v_id;

    when 'department' then
      select bu.id into v_unit from public.business_units bu
        where bu.id = p_parent_id and bu.org_id = v_org;
      if v_unit is null then
        perform app.refuse('KM010', 'hierarchy_violation',
          'That business unit does not exist.', jsonb_build_object('parent_id', p_parent_id));
      end if;
      perform app.require_capability('masters.manage', v_unit);
      insert into public.departments (id, org_id, business_unit_id, code, name, sort_order)
      values (v_id, v_org, v_unit, p_code, btrim(p_name),
              coalesce((p_attributes->>'sort_order')::integer, 0));

    when 'section' then
      select d.business_unit_id, d.id into v_unit, v_dept
        from public.departments d where d.id = p_parent_id and d.org_id = v_org;
      if v_dept is null then
        perform app.refuse('KM010', 'hierarchy_violation',
          'That department does not exist.', jsonb_build_object('parent_id', p_parent_id));
      end if;
      perform app.require_capability('masters.manage', v_unit);
      insert into public.sections (id, org_id, business_unit_id, department_id, code, name, sort_order)
      values (v_id, v_org, v_unit, v_dept, p_code, btrim(p_name),
              coalesce((p_attributes->>'sort_order')::integer, 0));

    when 'expense_category' then
      select s.business_unit_id, s.department_id, s.id into v_unit, v_dept, v_section
        from public.sections s where s.id = p_parent_id and s.org_id = v_org;
      if v_section is null then
        perform app.refuse('KM010', 'hierarchy_violation',
          'That section does not exist.', jsonb_build_object('parent_id', p_parent_id));
      end if;
      perform app.require_capability('masters.manage', v_unit);
      insert into public.expense_categories (id, org_id, business_unit_id, department_id,
                                             section_id, code, name, nature,
                                             is_shared_by_default, sort_order)
      values (v_id, v_org, v_unit, v_dept, v_section, p_code, btrim(p_name),
              coalesce(p_attributes->>'nature', 'operating'),
              coalesce((p_attributes->>'is_shared_by_default')::boolean, false),
              coalesce((p_attributes->>'sort_order')::integer, 0));

    when 'revenue_category' then
      select bu.id into v_unit from public.business_units bu
        where bu.id = p_parent_id and bu.org_id = v_org;
      if v_unit is null then
        perform app.refuse('KM010', 'hierarchy_violation',
          'That business unit does not exist.', jsonb_build_object('parent_id', p_parent_id));
      end if;
      perform app.require_capability('masters.manage', v_unit);
      insert into public.revenue_categories (id, org_id, business_unit_id, code, name, sort_order)
      values (v_id, v_org, v_unit, p_code, btrim(p_name),
              coalesce((p_attributes->>'sort_order')::integer, 0));

    when 'payment_method' then
      perform app.require_unscoped_capability('masters.manage');
      insert into public.payment_methods (id, org_id, code, name, requires_reference, sort_order)
      values (v_id, v_org, p_code, btrim(p_name),
              coalesce((p_attributes->>'requires_reference')::boolean, false),
              coalesce((p_attributes->>'sort_order')::integer, 0));

    else
      perform app.refuse('KM015', 'unknown_entity',
        'Vendors are created with vendor_create; that is not a kind of master this '
        'function handles.', jsonb_build_object('entity_type', p_entity_type));
  end case;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', p_entity_type, 'entity_id', v_id,
    'code', p_code, 'name', btrim(p_name), 'row_version', 1);

  perform app.write_audit(v_org, p_entity_type, v_id, 'created', v_actor,
    null::jsonb, v_result, null, v_unit, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, p_entity_type, v_id,
                               'create', v_result);
end;
$$;

-- ── master_rename (D-038) ────────────────────────────────────────────────────
-- The backend cannot know whether a rename is semantically equivalent, and guessing
-- would be exactly the kind of invented business fact this project forbids. So it does
-- not guess: it refuses to rename a master that carries history until the caller has
-- explicitly acknowledged the cosmetic-versus-semantic rule.
--
-- That acknowledgement is checked **here**, against the authoritative counter — not only
-- in the dialog. A modified client that skips the checkbox is refused just the same.
create or replace function public.master_rename(
  p_entity_type      text,
  p_entity_id        uuid,
  p_new_name         text,
  p_base_row_version integer,
  p_acknowledged     boolean default false,
  p_mutation_id      uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m        record;
  v_actor  uuid;
  v_org    uuid;
  v_replay jsonb;
  v_usage  bigint;
  v_result jsonb;
  v_before jsonb;
  v_new    text := btrim(coalesce(p_new_name, ''));
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  select * into m from app.master_locate(p_entity_type, p_entity_id);
  if m.table_name is null or m.org_id is distinct from v_org then
    perform app.refuse('KM015', 'unknown_entity', 'That record does not exist.',
      jsonb_build_object('entity_type', p_entity_type, 'entity_id', p_entity_id));
  end if;

  perform app.require_master_capability('masters.manage', m.is_org_level, m.business_unit_id);
  perform app.require_version(p_entity_type, p_entity_id, m.row_version, p_base_row_version);

  if length(v_new) = 0 then
    perform app.refuse('KM012', 'name_required', 'A name is required.');
  end if;

  select coalesce(transaction_count, 0) into v_usage
    from public.master_usage_counters
   where entity_type = p_entity_type and entity_id = p_entity_id;
  v_usage := coalesce(v_usage, 0);

  if v_usage > 0 and not coalesce(p_acknowledged, false) then
    perform app.refuse('KM017', 'acknowledgement_required',
      format('This record is used by %s recorded transactions. Renaming is permitted only '
             'when the meaning is unchanged - correcting a spelling, not re-purposing the '
             'record. Confirm that before the rename can be applied.', v_usage),
      jsonb_build_object('entity_type', p_entity_type, 'entity_id', p_entity_id,
                         'transaction_count', v_usage,
                         'current_name', m.name, 'proposed_name', v_new));
  end if;

  v_before := jsonb_build_object('name', m.name, 'code', m.code,
                                 'row_version', m.row_version);

  -- `code` is untouched and untouchable: the immutable-code trigger would refuse it, and
  -- no statement here names it. Aggregation, joins and grants key on it, so a rename can
  -- never move a figure by a single paisa (D-035).
  execute format('update public.%I set name = $1 where id = $2', m.table_name)
    using v_new, p_entity_id;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', p_entity_type, 'entity_id', p_entity_id,
    'name', v_new, 'code', m.code, 'row_version', m.row_version + 1,
    'acknowledged', coalesce(p_acknowledged, false),
    'transaction_count', v_usage);

  perform app.write_audit(v_org, p_entity_type, p_entity_id, 'renamed', v_actor,
    v_before, jsonb_build_object('name', v_new, 'code', m.code,
                                 'row_version', m.row_version + 1),
    case when v_usage > 0 then 'acknowledged cosmetic rename' else null end,
    m.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, p_entity_type, p_entity_id,
                               'rename', v_result);
end;
$$;

-- ── master_archive (D-039) ───────────────────────────────────────────────────
-- Refuses while live children exist, and says how many, so the UI can print
-- "Archive the 4 expense categories underneath this one first."
--
-- No cascade. No orphaning. No silent reassignment. Being referenced by history is
-- deliberately **not** a refusal — archiving is exactly the right action for a master
-- that carries history, and the whole reason delete does not exist.
create or replace function public.master_archive(
  p_entity_type      text,
  p_entity_id        uuid,
  p_base_row_version integer,
  p_mutation_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m        record;
  ch       record;
  v_actor  uuid;
  v_org    uuid;
  v_replay jsonb;
  v_result jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  select * into m from app.master_locate(p_entity_type, p_entity_id);
  if m.table_name is null or m.org_id is distinct from v_org then
    perform app.refuse('KM015', 'unknown_entity', 'That record does not exist.',
      jsonb_build_object('entity_type', p_entity_type, 'entity_id', p_entity_id));
  end if;

  perform app.require_master_capability('masters.manage', m.is_org_level, m.business_unit_id);
  perform app.require_version(p_entity_type, p_entity_id, m.row_version, p_base_row_version);

  if m.archived_at is not null then
    -- Archiving something already archived is a no-op, not an error (ArchivePolicy).
    v_result := jsonb_build_object(
      'status', 'unchanged', 'entity_type', p_entity_type, 'entity_id', p_entity_id,
      'archived', true, 'row_version', m.row_version);
    return app.remember_mutation(p_mutation_id, v_org, v_actor, p_entity_type,
                                 p_entity_id, 'archive', v_result);
  end if;

  select * into ch from app.active_child_count(p_entity_type, p_entity_id);
  if ch.child_count > 0 then
    perform app.refuse('KM005', 'has_active_children',
      format('Archive the %s %s underneath this one first.', ch.child_count, ch.child_kind),
      jsonb_build_object('entity_type', p_entity_type, 'entity_id', p_entity_id,
                         'entity_name', m.name,
                         'child_count', ch.child_count, 'child_kind', ch.child_kind));
  end if;

  execute format('update public.%I set archived_at = now() where id = $1', m.table_name)
    using p_entity_id;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', p_entity_type, 'entity_id', p_entity_id,
    'archived', true, 'row_version', m.row_version + 1);

  perform app.write_audit(v_org, p_entity_type, p_entity_id, 'archived', v_actor,
    jsonb_build_object('archived_at', null, 'row_version', m.row_version),
    jsonb_build_object('archived_at', now(), 'row_version', m.row_version + 1),
    null, m.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, p_entity_type, p_entity_id,
                               'archive', v_result);
end;
$$;

-- ── master_restore ───────────────────────────────────────────────────────────
create or replace function public.master_restore(
  p_entity_type      text,
  p_entity_id        uuid,
  p_base_row_version integer,
  p_mutation_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m        record;
  v_actor  uuid;
  v_org    uuid;
  v_replay jsonb;
  v_result jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  select * into m from app.master_locate(p_entity_type, p_entity_id);
  if m.table_name is null or m.org_id is distinct from v_org then
    perform app.refuse('KM015', 'unknown_entity', 'That record does not exist.',
      jsonb_build_object('entity_type', p_entity_type, 'entity_id', p_entity_id));
  end if;

  perform app.require_master_capability('masters.manage', m.is_org_level, m.business_unit_id);
  perform app.require_version(p_entity_type, p_entity_id, m.row_version, p_base_row_version);

  if m.archived_at is null then
    v_result := jsonb_build_object(
      'status', 'unchanged', 'entity_type', p_entity_type, 'entity_id', p_entity_id,
      'archived', false, 'row_version', m.row_version);
    return app.remember_mutation(p_mutation_id, v_org, v_actor, p_entity_type,
                                 p_entity_id, 'restore', v_result);
  end if;

  -- The no-orphan-restore trigger refuses if the parent is still archived, so a live
  -- category can never end up hanging off a dead section.
  execute format('update public.%I set archived_at = null where id = $1', m.table_name)
    using p_entity_id;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', p_entity_type, 'entity_id', p_entity_id,
    'archived', false, 'row_version', m.row_version + 1);

  perform app.write_audit(v_org, p_entity_type, p_entity_id, 'restored', v_actor,
    jsonb_build_object('archived_at', m.archived_at, 'row_version', m.row_version),
    jsonb_build_object('archived_at', null, 'row_version', m.row_version + 1),
    null, m.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, p_entity_type, p_entity_id,
                               'restore', v_result);
end;
$$;

-- ── Grants ───────────────────────────────────────────────────────────────────
revoke all on function app.master_locate(text, uuid)                    from public;
revoke all on function app.require_unscoped_capability(text)            from public;
revoke all on function app.require_master_capability(text, boolean, uuid) from public;

grant execute on function public.master_usage(text, uuid) to authenticated;
grant execute on function public.master_create(text, uuid, text, text, jsonb, uuid, uuid) to authenticated;
grant execute on function public.master_rename(text, uuid, text, integer, boolean, uuid) to authenticated;
grant execute on function public.master_archive(text, uuid, integer, uuid) to authenticated;
grant execute on function public.master_restore(text, uuid, integer, uuid) to authenticated;
