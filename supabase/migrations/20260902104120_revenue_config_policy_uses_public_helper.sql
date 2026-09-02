-- D-045, in a new place, caused by the migration immediately before this one.
--
-- `revenue_config_read_boundary` pointed two policies at `app.revenue_category_unit`.
-- A policy expression is evaluated with the **querying user's** privileges, and
-- `authenticated` deliberately holds no EXECUTE in `app` — so every SELECT on
-- `revenue_value_bands` and `revenue_supply_subtypes` failed outright with
-- `permission denied for function revenue_category_unit`, which took the whole reference
-- pull down with it. No data was exposed; synchronisation was simply impossible.
--
-- This is precisely the shape of D-045, where every table returned 403 because the
-- policies called `app.current_org_id()`. The fix then and the fix now are the same: a
-- policy calls a **published** helper granted to `authenticated`; the `app` schema stays
-- unreachable and is for `security definer` bodies, which run as the owner.
--
-- Granting `authenticated` USAGE on `app` would also have worked and would have eroded
-- the boundary the schema exists to draw, and broken the D-044 invariant.

create or replace function public.revenue_category_unit(p_category_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select business_unit_id from public.revenue_categories where id = p_category_id;
$$;

comment on function public.revenue_category_unit(uuid) is
  'The business unit a revenue category belongs to. Published because RLS policies must be able to call it (D-045); returns an identifier and nothing else, and the caller is still checked against has_capability for that unit.';

grant execute on function public.revenue_category_unit(uuid) to authenticated;
revoke all on function public.revenue_category_unit(uuid) from public, anon;

drop policy if exists revenue_value_bands_read on public.revenue_value_bands;
create policy revenue_value_bands_read on public.revenue_value_bands
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', public.revenue_category_unit(revenue_category_id)))
  );

drop policy if exists revenue_supply_subtypes_read on public.revenue_supply_subtypes;
create policy revenue_supply_subtypes_read on public.revenue_supply_subtypes
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', public.revenue_category_unit(revenue_category_id)))
  );

drop function if exists app.revenue_category_unit(uuid);

-- No policy anywhere may reference the internal schema. Asserted rather than reviewed,
-- because reviewing is what let this through in the first place.
do $$
declare v_bad text;
begin
  select string_agg(policyname || ' on ' || tablename, ', ') into v_bad
    from pg_policies
   where schemaname = 'public' and coalesce(qual, '') like '%app.%';
  if v_bad is not null then
    raise exception 'an RLS policy references the app schema, which clients cannot reach: %', v_bad;
  end if;
end $$;
