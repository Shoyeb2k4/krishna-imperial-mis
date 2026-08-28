-- ─────────────────────────────────────────────────────────────────────────────
-- 0017 · Restore guard: branch with IF, not with a CASE expression
--
-- A real defect, and one that only executing against Postgres could have found.
--
-- The guard chose its parent lookup with a `CASE` **expression**. PL/pgSQL evaluates that
-- as a single SQL expression, which means **every branch is planned**, including
-- `new.section_id` — a column that does not exist on a `sections` record. So the trigger
-- raised `42703 record "new" has no field "section_id"` on any attempt to restore a
-- department, a section or a revenue category. Only the expense-category branch would
-- ever have worked, and the failure would have looked like a database fault rather than
-- a bug in the guard.
--
-- The Dart-side tests could not have caught this: the rule is a Postgres trigger, and the
-- mistake is in how PL/pgSQL plans an expression. It was caught by the D-039 archive and
-- restore test running against the real development database (owner requirement §6).
--
-- `IF`/`ELSIF` makes each branch a separate statement, so a record field is resolved only
-- when the branch that mentions it actually runs.
-- ─────────────────────────────────────────────────────────────────────────────

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

  if tg_table_name in ('departments', 'revenue_categories') then
    select archived_at into v_parent_archived
      from public.business_units where id = new.business_unit_id;
  elsif tg_table_name = 'sections' then
    select archived_at into v_parent_archived
      from public.departments where id = new.department_id;
  elsif tg_table_name = 'expense_categories' then
    select archived_at into v_parent_archived
      from public.sections where id = new.section_id;
  end if;

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
