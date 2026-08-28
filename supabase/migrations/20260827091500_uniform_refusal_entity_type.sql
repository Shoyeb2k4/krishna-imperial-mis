-- ─────────────────────────────────────────────────────────────────────────────
-- 0016 · One meaning for `entity_type` in a refusal
--
-- Found by executing the refusals against the real database rather than by reading them.
--
-- The structured DETAIL payload is what the UI matches on to decide which message to
-- show. The RPCs report the singular entity type (`section`); these triggers were
-- reporting the *table* name (`sections`). Both refusals are correct, but a client
-- reacting to either would have had to know which layer produced it — which is exactly
-- the kind of detail that gets discovered by a bug report rather than by design.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function app.entity_type_of(p_table_name text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_table_name
           when 'business_units'      then 'business_unit'
           when 'departments'         then 'department'
           when 'sections'            then 'section'
           when 'expense_categories'  then 'expense_category'
           when 'revenue_categories'  then 'revenue_category'
           when 'vendors'             then 'vendor'
           when 'payment_methods'     then 'payment_method'
           when 'revenue_tax_rates'   then 'revenue_tax_rate'
           else p_table_name
         end;
$$;

create or replace function app.refuse_code_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare v_kind text := app.entity_type_of(tg_table_name);
begin
  if new.code is distinct from old.code then
    perform app.refuse(
      'KM009', 'immutable_code',
      format('The permanent code of a %s cannot be changed once it is created.',
             replace(v_kind, '_', ' ')),
      jsonb_build_object('entity_type', v_kind, 'entity_id', old.id));
  end if;
  return new;
end;
$$;

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
      jsonb_build_object('entity_type', app.entity_type_of(tg_table_name),
                         'entity_id', old.id,
                         'from_business_unit_id', old.business_unit_id,
                         'to_business_unit_id', new.business_unit_id));
  end if;
  return new;
end;
$$;

create or replace function app.refuse_archive_with_live_children()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_kind  text := app.entity_type_of(tg_table_name);
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
      jsonb_build_object('entity_type', v_kind, 'entity_id', old.id,
                         'child_count', v_count, 'child_kind', v_child));
  end if;
  return new;
end;
$$;

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
      jsonb_build_object('entity_type', app.entity_type_of(tg_table_name),
                         'entity_id', new.id));
  end if;
  return new;
end;
$$;

revoke all on function app.entity_type_of(text) from public, anon, authenticated;
