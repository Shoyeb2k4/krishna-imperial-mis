-- Phase 4 closure corrective - the fourth write privilege
--
-- Found by the Slice 14 audit asking the live catalogue what clients may actually do,
-- rather than reading the migrations that were supposed to have closed it.
--
-- `20260829090300_expense_rls.sql` wrote:
--
--     revoke insert, update, delete on public.expenses from authenticated;
--
-- There are **four** write privileges, not three. Supabase's template grants ALL on public
-- tables to `authenticated`, so `TRUNCATE` survived that revoke on four financial base
-- tables - and TRUNCATE does not consult row level security at all. The revenue side used
-- `revoke all ... from public, anon, authenticated` and is clean, so the correct idiom was
-- already in the repository; Phase 3 used the enumerating form and lost a privilege in it.
--
-- The guard that should have caught this enumerated the same three words (D-139's lesson,
-- again): it searched the migrations for `grant insert|update|delete` and never asked what
-- a client was left holding.
--
-- **Not reachable through the shipped surface.** PostgREST issues SELECT, INSERT, UPDATE
-- and DELETE; it has no way to say TRUNCATE, and no client holds a SQL connection. That is
-- exactly the reasoning D-044 refused to accept the first time: "happens to be unreachable"
-- is a different claim from "cannot be granted", and this is four financial tables one
-- exposed SQL path away from being emptied without RLS looking at it.
--
-- The five projections carried the whole default `GRANT ALL` as well. Those grants are
-- inert - a view over a join is not auto-updatable, and TRUNCATE on a view is meaningless -
-- but a privilege nobody can use is still a privilege nobody reviewed.

-- Revoke everything, then re-grant exactly what the product reads.
revoke all on public.expenses                      from anon, authenticated;
revoke all on public.expense_allocations           from anon, authenticated;
revoke all on public.expense_period_allocations    from anon, authenticated;
revoke all on public.expense_attachments           from anon, authenticated;
revoke all on public.expense_document              from anon, authenticated;
revoke all on public.expense_period_contributions  from anon, authenticated;
revoke all on public.revenue_document              from anon, authenticated;
revoke all on public.revenue_component_detail      from anon, authenticated;
revoke all on public.revenue_period_contributions  from anon, authenticated;

-- `public.expenses` deliberately gets nothing back: the header total on a shared bill is
-- withheld from a unit-scoped caller, and the projection is the only way in (D-062).
grant select on public.expense_allocations           to authenticated;
grant select on public.expense_period_allocations    to authenticated;
grant select on public.expense_attachments           to authenticated;
grant select on public.expense_document              to authenticated;
grant select on public.expense_period_contributions  to authenticated;
grant select on public.revenue_document              to authenticated;
grant select on public.revenue_component_detail      to authenticated;
grant select on public.revenue_period_contributions  to authenticated;

-- The invariant, stated over all four privileges and over everything in `public` rather
-- than over a list somebody has to remember to extend.
do $inv$
declare v_bad text;
begin
  select string_agg(format('%s:%s(%s)', grantee, table_name, privilege_type), ', ')
    into v_bad
    from information_schema.role_table_grants
   where table_schema = 'public'
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_bad is not null then
    raise exception
      'a client role holds a write privilege in public - every mutation must travel '
      'through a reviewed SECURITY DEFINER RPC: %', v_bad;
  end if;
end $inv$;

-- And the reads the product actually depends on are still there, so this migration cannot
-- have closed the boundary by breaking the application.
do $inv$
declare v_missing text;
begin
  select string_agg(t, ', ') into v_missing
    from unnest(array['expense_document', 'expense_period_contributions',
                      'revenue_document', 'revenue_component_detail',
                      'revenue_period_contributions', 'expense_allocations',
                      'expense_period_allocations', 'expense_attachments']) as t
   where not has_table_privilege('authenticated', 'public.' || t, 'SELECT');
  if v_missing is not null then
    raise exception 'a projection the client reads is no longer readable: %', v_missing;
  end if;

  if has_table_privilege('authenticated', 'public.expenses', 'SELECT') then
    raise exception
      'authenticated can read public.expenses directly; the header total on a shared bill '
      'is the other property''s share (D-062)';
  end if;
end $inv$;