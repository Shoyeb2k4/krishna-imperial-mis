-- ─────────────────────────────────────────────────────────────────────────────
-- 0004 · Master integrity: immutable codes, D-039 archiving, no orphans
--
-- These are database guarantees, not application conventions. Clients hold no write
-- grant on any master table (0010), so every mutation already arrives through a
-- SECURITY DEFINER RPC — but a rule that lives only inside an RPC is one refactor away
-- from being forgotten. The triggers here hold even for a privileged path that gets it
-- wrong, which is what "database-authoritative" has to mean.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── The code is assigned once and never moves (D-035, D-038) ─────────────────
-- History, joins and capability grants key on `code`. Re-purposing a master is done by
-- archiving it and creating a new one — never by editing this column. There is no RPC
-- that changes it and now no possible path that does.
create or replace function app.refuse_code_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.code is distinct from old.code then
    perform app.refuse(
      'KM009', 'immutable_code',
      format('The permanent code of a %s cannot be changed once it is created.',
             replace(tg_table_name, '_', ' ')),
      jsonb_build_object('entity_type', tg_table_name, 'entity_id', old.id));
  end if;
  return new;
end;
$$;

-- ── A master never changes property (D-040) ──────────────────────────────────
-- The composite foreign keys already make a cross-property tuple unresolvable. This
-- refuses the move outright, so the failure names the real problem instead of surfacing
-- as a foreign-key violation on a row nobody was looking at.
create or replace function app.refuse_reparent_across_units()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.business_unit_id is distinct from old.business_unit_id then
    perform app.refuse(
      'KM010', 'hierarchy_violation',
      'A master cannot be moved to a different business unit. Archive it and create the '
      'equivalent record under the correct property, so history keeps its meaning.',
      jsonb_build_object('entity_type', tg_table_name, 'entity_id', old.id,
                         'from_business_unit_id', old.business_unit_id,
                         'to_business_unit_id', new.business_unit_id));
  end if;
  return new;
end;
$$;

-- ── How many live children a master has ──────────────────────────────────────
-- One function, used by the archive trigger for the guarantee and by the archive RPC for
-- the structured reason the UI shows. Two implementations of this count would eventually
-- disagree about whether a record may be archived.
create or replace function app.active_child_count(p_entity_type text, p_entity_id uuid)
returns table (child_count integer, child_kind text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case p_entity_type
    when 'business_unit' then
      return query
        select ((select count(*)::integer from public.departments d
                  where d.business_unit_id = p_entity_id and d.archived_at is null)
              + (select count(*)::integer from public.revenue_categories r
                  where r.business_unit_id = p_entity_id and r.archived_at is null))::integer,
               'departments and revenue categories'::text;
    when 'department' then
      return query
        select count(*)::integer, 'sections'::text
          from public.sections s
         where s.department_id = p_entity_id and s.archived_at is null;
    when 'section' then
      return query
        select count(*)::integer, 'expense categories'::text
          from public.expense_categories c
         where c.section_id = p_entity_id and c.archived_at is null;
    else
      -- Leaves: expense categories, revenue categories, vendors, payment methods.
      return query select 0::integer, 'records'::text;
  end case;
end;
$$;

comment on function app.active_child_count(text, uuid) is
  'Live children of one master. D-039: archiving refuses while this is above zero. No '
  'cascade, no orphaning, no silent reassignment.';

-- ── D-039 · archiving refuses while live children exist ──────────────────────
create or replace function app.refuse_archive_with_live_children()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_kind  text := case tg_table_name
                    when 'business_units' then 'business_unit'
                    when 'departments'    then 'department'
                    when 'sections'       then 'section'
                  end;
  v_count integer;
  v_child text;
begin
  if old.archived_at is not null or new.archived_at is null then
    return new;                                    -- not an archive transition
  end if;

  select c.child_count, c.child_kind into v_count, v_child
    from app.active_child_count(v_kind, old.id) c;

  if v_count > 0 then
    perform app.refuse(
      'KM005', 'has_active_children',
      format('Archive the %s %s underneath this one first.', v_count, v_child),
      jsonb_build_object('entity_type', tg_table_name, 'entity_id', old.id,
                         'child_count', v_count, 'child_kind', v_child));
  end if;
  return new;
end;
$$;

-- ── The mirror rule: restoring must not create an orphan ─────────────────────
-- A live category hanging off an archived section is exactly the state D-039 rejected
-- when it refused the cascade. Un-archiving has to respect it from the other direction.
create or replace function app.refuse_restore_under_archived_parent()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare v_parent_archived timestamptz;
begin
  if old.archived_at is null or new.archived_at is not null then
    return new;                                    -- not a restore transition
  end if;

  v_parent_archived := case tg_table_name
    when 'departments' then
      (select archived_at from public.business_units where id = new.business_unit_id)
    when 'revenue_categories' then
      (select archived_at from public.business_units where id = new.business_unit_id)
    when 'sections' then
      (select archived_at from public.departments where id = new.department_id)
    when 'expense_categories' then
      (select archived_at from public.sections where id = new.section_id)
  end;

  if v_parent_archived is not null then
    perform app.refuse(
      'KM006', 'archived_parent',
      'Restore the record above this one first - otherwise it would sit inside a '
      'structure that no longer exists.',
      jsonb_build_object('entity_type', tg_table_name, 'entity_id', new.id));
  end if;
  return new;
end;
$$;

-- ── Attach ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['business_units', 'departments', 'sections',
                           'expense_categories', 'revenue_categories',
                           'vendors', 'payment_methods']
  loop
    execute format('drop trigger if exists immutable_code_%1$s on public.%1$s', t);
    execute format(
      'create trigger immutable_code_%1$s before update on public.%1$s '
      'for each row execute function app.refuse_code_change()', t);
  end loop;

  foreach t in array array['departments', 'sections', 'expense_categories',
                           'revenue_categories']
  loop
    execute format('drop trigger if exists no_cross_unit_%1$s on public.%1$s', t);
    execute format(
      'create trigger no_cross_unit_%1$s before update on public.%1$s '
      'for each row execute function app.refuse_reparent_across_units()', t);

    execute format('drop trigger if exists no_orphan_restore_%1$s on public.%1$s', t);
    execute format(
      'create trigger no_orphan_restore_%1$s before update on public.%1$s '
      'for each row execute function app.refuse_restore_under_archived_parent()', t);
  end loop;

  foreach t in array array['business_units', 'departments', 'sections']
  loop
    execute format('drop trigger if exists archive_guard_%1$s on public.%1$s', t);
    execute format(
      'create trigger archive_guard_%1$s before update on public.%1$s '
      'for each row execute function app.refuse_archive_with_live_children()', t);
  end loop;
end $$;
