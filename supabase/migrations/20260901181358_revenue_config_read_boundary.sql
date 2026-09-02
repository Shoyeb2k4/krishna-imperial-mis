-- Slice 6 — the revenue configuration read boundary, narrowed to what it claimed to be.
--
-- Slice 6 synchronises the revenue configuration a device needs to resolve tax offline.
-- Auditing the read surface before building the transport found three defects, all of
-- them in policies that had never been exercised because the datasets they guard are
-- empty in the verified baseline.
--
-- 1. `business_unit_tax_statuses_read` required `revenue.view.all`. **No role holds that
--    capability** — not manager, not accountant, not data_entry, and not owner. The policy
--    could never be satisfied by anybody, so the moment a premises status were configured
--    it would be unreachable by every client, and any rule requiring one would refuse for
--    ever with no way to fix it from the application. The same family as D-068, D-071 and
--    D-073a — a rule nothing can evaluate to true — arriving as unsatisfiable rather than
--    as vacuously permissive.
--
-- 2. `revenue_value_bands_read` and 3. `revenue_supply_subtypes_read` were scoped to the
--    organisation alone. A Crystal Canopy manager could read Hotel Krishna's band and
--    subtype configuration. Not a financial amount, but configuration about a property
--    they deliberately cannot see — exactly what the tax-rule policy already refuses, and
--    what D-107 restated phase-a to assert.
--
-- All three now say what `revenue_tax_rates_read` says: this organisation, and a unit the
-- caller may view. Bands and subtypes reach their unit only through their category.

-- Resolving that hop inside a policy with a plain subquery would make the predicate depend
-- on `revenue_categories`' own RLS, evaluated with the caller's privileges — which is how
-- D-045 broke every table and how D-073a's attachment policy became vacuously true. A
-- `security definer` helper answers the structural question directly, and the answer is a
-- business unit id the caller is then checked against.
create or replace function app.revenue_category_unit(p_category_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select business_unit_id from public.revenue_categories where id = p_category_id;
$$;

comment on function app.revenue_category_unit(uuid) is
  'The business unit a revenue category belongs to, resolved without the caller''s RLS so a policy can ask a structural question. Internal: no client role may execute it.';

revoke all on function app.revenue_category_unit(uuid) from public, anon, authenticated;

drop policy if exists revenue_value_bands_read on public.revenue_value_bands;
create policy revenue_value_bands_read on public.revenue_value_bands
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', app.revenue_category_unit(revenue_category_id)))
  );

drop policy if exists revenue_supply_subtypes_read on public.revenue_supply_subtypes;
create policy revenue_supply_subtypes_read on public.revenue_supply_subtypes
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', app.revenue_category_unit(revenue_category_id)))
  );

drop policy if exists business_unit_tax_statuses_read on public.business_unit_tax_statuses;
create policy business_unit_tax_statuses_read on public.business_unit_tax_statuses
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', business_unit_id))
  );

-- Assert the defect is really gone rather than merely rewritten: the capability the new
-- policies name must actually be held by somebody, or this migration has replaced an
-- unsatisfiable policy with another one.
do $$
declare v_holders integer; v_orphan text;
begin
  select count(*) into v_holders
    from public.role_capabilities where capability_code = 'masters.view';
  if v_holders = 0 then
    raise exception
      'the revenue configuration policies name masters.view, which no role holds - '
      'the same unsatisfiable shape this migration exists to remove';
  end if;

  if exists (select 1 from public.role_capabilities where capability_code = 'revenue.view.all') then
    raise exception 'revenue.view.all is now granted somewhere; revisit the status policy deliberately';
  end if;

  -- And the helper must not have arrived executable by a client, which is the default
  -- Postgres applies and the finding D-044 and D-101 both record.
  select string_agg(p.proname, ', ') into v_orphan
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_orphan is not null then
    raise exception 'a client role can execute functions in app: %', v_orphan;
  end if;
end $$;
