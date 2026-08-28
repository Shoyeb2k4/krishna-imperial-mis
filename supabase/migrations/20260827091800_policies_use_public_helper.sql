-- ─────────────────────────────────────────────────────────────────────────────
-- 0019 · RLS policies must not reach into the internal schema
--
-- Defect found the first time an authenticated session actually read a table.
--
-- Every policy called `app.current_org_id()`. A policy expression is evaluated with the
-- *querying* user's privileges, and `authenticated` has no USAGE on `app` - that schema
-- was locked down in 0001 precisely so it could not be reached. So the policy could not
-- be evaluated at all and PostgREST returned 403 for every table, for every signed-in
-- user. Not a leak: the failure was closed, and no data was exposed. But the entire
-- application was unusable for anyone who signed in, and no amount of static review had
-- shown it - only a real session did.
--
-- Two ways out. Granting `authenticated` USAGE on `app` would work and would also erode
-- the boundary the schema exists to draw, and would break the invariant asserted in 0015.
-- So instead the one helper a policy needs is published properly, and `app` stays
-- internal. `app.current_org_id()` remains for use inside SECURITY DEFINER functions,
-- which run as the owner and can reach it.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.org_id
    from public.profiles p
   where p.id = (select auth.uid())
     and p.is_active;
$$;

comment on function public.current_org_id() is
  'The caller organisation, read from their profile row. Published because RLS policies '
  'are evaluated as the querying user and must be able to call it; still derives '
  'everything from auth.uid() and accepts nothing from the request.';

revoke all on function public.current_org_id() from public, anon;
grant execute on function public.current_org_id() to authenticated;

drop policy if exists organizations_read on public.organizations;
create policy organizations_read on public.organizations
  for select to authenticated
  using (id = (select public.current_org_id()));

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (org_id = (select public.current_org_id())
        and (select public.has_capability_anywhere('users.manage')))
  );

drop policy if exists roles_read on public.roles;
create policy roles_read on public.roles
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (
      (select public.has_capability_anywhere('roles.manage'))
      or (select public.has_capability_anywhere('users.manage'))
      or exists (select 1 from public.user_roles ur
                  where ur.role_id = roles.id
                    and ur.user_id = (select auth.uid())
                    and ur.revoked_at is null)
    )
  );

drop policy if exists user_roles_read on public.user_roles;
create policy user_roles_read on public.user_roles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (org_id = (select public.current_org_id())
        and (select public.has_capability_anywhere('users.manage')))
  );

drop policy if exists org_settings_read on public.org_settings;
create policy org_settings_read on public.org_settings
  for select to authenticated
  using (org_id = (select public.current_org_id()));

drop policy if exists business_units_read on public.business_units;
create policy business_units_read on public.business_units
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', business_units.id))
  );

drop policy if exists departments_read on public.departments;
create policy departments_read on public.departments
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', departments.business_unit_id))
  );

drop policy if exists sections_read on public.sections;
create policy sections_read on public.sections
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', sections.business_unit_id))
  );

drop policy if exists expense_categories_read on public.expense_categories;
create policy expense_categories_read on public.expense_categories
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', expense_categories.business_unit_id))
  );

drop policy if exists revenue_categories_read on public.revenue_categories;
create policy revenue_categories_read on public.revenue_categories
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', revenue_categories.business_unit_id))
  );

drop policy if exists vendors_read on public.vendors;
create policy vendors_read on public.vendors
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability_anywhere('masters.view'))
  );

drop policy if exists payment_methods_read on public.payment_methods;
create policy payment_methods_read on public.payment_methods
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability_anywhere('masters.view'))
  );

drop policy if exists revenue_tax_rates_read on public.revenue_tax_rates;
create policy revenue_tax_rates_read on public.revenue_tax_rates
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('masters.view', revenue_tax_rates.business_unit_id))
  );

drop policy if exists period_locks_read on public.period_locks;
create policy period_locks_read on public.period_locks
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (
      case when period_locks.business_unit_id is null
           then (select public.has_capability_anywhere('masters.view'))
           else (select public.has_capability('masters.view', period_locks.business_unit_id))
      end
    )
  );

drop policy if exists period_lock_events_read on public.period_lock_events;
create policy period_lock_events_read on public.period_lock_events
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and exists (select 1 from public.period_locks pl where pl.id = period_lock_events.period_lock_id)
  );

drop policy if exists audit_logs_read on public.audit_logs;
create policy audit_logs_read on public.audit_logs
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (
      case when audit_logs.business_unit_id is null
           then (select public.has_capability_anywhere('audit.view'))
           else (select public.has_capability('audit.view', audit_logs.business_unit_id))
      end
    )
  );

-- No policy may reference the internal schema, now or later.
do $$
declare v_bad text;
begin
  select string_agg(polname, ', ')
    into v_bad
    from pg_policy
   where pg_get_expr(polqual, polrelid) like '%app.%';
  if v_bad is not null then
    raise exception 'policies still reach into the app schema: %', v_bad;
  end if;
end $$;
