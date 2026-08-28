-- ─────────────────────────────────────────────────────────────────────────────
-- 0010 · Row Level Security — deny by default, everywhere
--
-- Two separate mechanisms, both required, because either alone leaves a hole:
--
--  1. **Grants.** INSERT, UPDATE and DELETE are revoked from `anon` and `authenticated`
--     on every table. Supabase grants these by default, so revoking is not tidiness —
--     it is the difference between "the policy stops you" and "there is nothing to stop".
--     Every mutation therefore travels through a SECURITY DEFINER RPC that re-checks
--     capability, unit scope, period state and row version (owner requirement §7).
--  2. **Policies.** RLS is enabled on every table. A table with RLS on and no policy for
--     an operation denies it — that is the default stance, and tables that should never
--     be read directly (the mutation ledger, the usage counters) deliberately have no
--     SELECT policy at all.
--
-- RLS is enabled but deliberately **not** forced. `FORCE ROW LEVEL SECURITY` applies
-- policies to the table owner as well, which would subject every SECURITY DEFINER RPC to
-- the very policies it exists to enforce more precisely — and since there are no write
-- policies at all, every administrative mutation would fail. Forcing buys nothing here
-- either way: clients connect as `anon` or `authenticated` and are never the owner.
--
-- Unit scoping is decided by `has_capability(cap, unit)`, which is false for a null unit.
-- A Crystal Canopy manager therefore cannot see a Hotel Krishna department, section or
-- category — not because the client hides it, but because the row never leaves Postgres.
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array[
    'organizations', 'profiles', 'capabilities', 'roles', 'role_capabilities',
    'user_roles', 'org_settings', 'business_units', 'departments', 'sections',
    'expense_categories', 'revenue_categories', 'vendors', 'payment_methods',
    'period_locks', 'period_lock_events', 'revenue_tax_rates', 'audit_logs',
    'processed_mutations', 'master_usage_counters']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- The usage counters and the mutation ledger are served through RPCs that label their
-- authority and enforce scope. Direct reads would bypass both.
revoke select on public.master_usage_counters from authenticated;
revoke select on public.processed_mutations   from authenticated;

-- ── Tenancy and identity ─────────────────────────────────────────────────────
drop policy if exists organizations_read on public.organizations;
create policy organizations_read on public.organizations
  for select to authenticated
  using (id = (select app.current_org_id()));

-- A user always sees themselves. Seeing anybody else requires user administration —
-- the roster is not public within the organisation.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (org_id = (select app.current_org_id())
        and (select public.has_capability_anywhere('users.manage')))
  );

-- The capability catalogue is a dictionary of codes and descriptions. It carries no
-- business data, and the client needs it to render permission screens honestly.
drop policy if exists capabilities_read on public.capabilities;
create policy capabilities_read on public.capabilities
  for select to authenticated using (true);

drop policy if exists roles_read on public.roles;
create policy roles_read on public.roles
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (
      (select public.has_capability_anywhere('roles.manage'))
      or (select public.has_capability_anywhere('users.manage'))
      or exists (select 1 from public.user_roles ur
                  where ur.role_id = roles.id
                    and ur.user_id = (select auth.uid())
                    and ur.revoked_at is null)
    )
  );

-- A user may read the capability list of a role they actually hold — that is how the
-- client builds its `Principal` and shapes the UI. Reading anybody else's requires role
-- administration.
drop policy if exists role_capabilities_read on public.role_capabilities;
create policy role_capabilities_read on public.role_capabilities
  for select to authenticated
  using (
    (select public.has_capability_anywhere('roles.manage'))
    or exists (select 1 from public.user_roles ur
                where ur.role_id = role_capabilities.role_id
                  and ur.user_id = (select auth.uid())
                  and ur.revoked_at is null)
  );

drop policy if exists user_roles_read on public.user_roles;
create policy user_roles_read on public.user_roles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (org_id = (select app.current_org_id())
        and (select public.has_capability_anywhere('users.manage')))
  );

drop policy if exists org_settings_read on public.org_settings;
create policy org_settings_read on public.org_settings
  for select to authenticated
  using (org_id = (select app.current_org_id()));

-- ── Master data, scoped by property ──────────────────────────────────────────
drop policy if exists business_units_read on public.business_units;
create policy business_units_read on public.business_units
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select public.has_capability('masters.view', business_units.id))
  );

drop policy if exists departments_read on public.departments;
create policy departments_read on public.departments
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select public.has_capability('masters.view', departments.business_unit_id))
  );

drop policy if exists sections_read on public.sections;
create policy sections_read on public.sections
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select public.has_capability('masters.view', sections.business_unit_id))
  );

drop policy if exists expense_categories_read on public.expense_categories;
create policy expense_categories_read on public.expense_categories
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select public.has_capability('masters.view', expense_categories.business_unit_id))
  );

drop policy if exists revenue_categories_read on public.revenue_categories;
create policy revenue_categories_read on public.revenue_categories
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select public.has_capability('masters.view', revenue_categories.business_unit_id))
  );

-- Vendors and payment methods are organisation-level: a supplier serves the company, not
-- one property. Scope still applies to *changing* them (0011), and to the optional
-- default business unit a vendor may carry.
drop policy if exists vendors_read on public.vendors;
create policy vendors_read on public.vendors
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select public.has_capability_anywhere('masters.view'))
  );

drop policy if exists payment_methods_read on public.payment_methods;
create policy payment_methods_read on public.payment_methods
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select public.has_capability_anywhere('masters.view'))
  );

-- ── Tax configuration ────────────────────────────────────────────────────────
drop policy if exists revenue_tax_rates_read on public.revenue_tax_rates;
create policy revenue_tax_rates_read on public.revenue_tax_rates
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select public.has_capability('masters.view', revenue_tax_rates.business_unit_id))
  );

-- ── Period control ───────────────────────────────────────────────────────────
-- An organisation-wide lock is visible to anyone who can see any master; a unit lock is
-- visible to those scoped to that unit. Lock state is not sensitive — being told "this
-- month is closed" is the whole point — but it still never crosses the organisation.
drop policy if exists period_locks_read on public.period_locks;
create policy period_locks_read on public.period_locks
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
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
    org_id = (select app.current_org_id())
    and exists (select 1 from public.period_locks pl where pl.id = period_lock_events.period_lock_id)
  );

-- ── Audit ────────────────────────────────────────────────────────────────────
-- Readable only with `audit.view`, and only for the property the entry concerns. Never
-- writable: no INSERT policy exists, no grant exists, and the append-only trigger refuses
-- UPDATE and DELETE regardless of who is asking (master spec §14).
drop policy if exists audit_logs_read on public.audit_logs;
create policy audit_logs_read on public.audit_logs
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (
      case when audit_logs.business_unit_id is null
           then (select public.has_capability_anywhere('audit.view'))
           else (select public.has_capability('audit.view', audit_logs.business_unit_id))
      end
    )
  );
