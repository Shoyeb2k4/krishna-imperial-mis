-- Phase 8 · D-320 equivalence harness — capture the PRE-redesign read paths.
--
-- Run by localpg.sh immediately before the first migration after
-- 20260912100000 (i.e. before the D-318 redesign), so the definitions copied here are
-- exactly the ones krishna-mis-dev ran before it. They live in a harness-only schema,
-- `perf_old`, and read the same tables as the new definitions, so old and new can be
-- compared on the same data, for the same principal, in the same transaction.
--
-- Harness only: nothing here is a migration and nothing here reaches krishna-mis-dev.
\set ON_ERROR_STOP 1
do $$
begin
  if current_database() <> 'krishna_perf' or current_setting('listen_addresses') <> '' then
    raise exception 'capture_old.sql runs only inside the local D-186 harness cluster';
  end if;
end $$;

create schema perf_old;
grant usage on schema perf_old to authenticated;

do $$
declare
  v_def text;
begin
  -- The two projections, verbatim, as security-barrier views owned by the same role.
  v_def := pg_get_viewdef('public.expense_period_contributions'::regclass, true);
  execute 'create view perf_old.expense_period_contributions with (security_barrier = true) as '
          || v_def;
  v_def := pg_get_viewdef('public.revenue_period_contributions'::regclass, true);
  execute 'create view perf_old.revenue_period_contributions with (security_barrier = true) as '
          || v_def;

  -- The three reporting functions, verbatim, re-pointed at the OLD projections so the old
  -- function is the old implementation end to end.
  for v_def in
    select pg_get_functiondef(p.oid)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('reporting_primitives', 'reporting_snapshot', 'reporting_newer_than')
  loop
    v_def := replace(v_def, 'FUNCTION public.', 'FUNCTION perf_old.');
    v_def := replace(v_def, 'public.expense_period_contributions',
                            'perf_old.expense_period_contributions');
    v_def := replace(v_def, 'public.revenue_period_contributions',
                            'perf_old.revenue_period_contributions');
    execute v_def;
  end loop;
end $$;

grant select on perf_old.expense_period_contributions, perf_old.revenue_period_contributions
  to authenticated;
grant execute on all functions in schema perf_old to authenticated;

-- Sanity: every copy exists and reads the old projections, not the public ones.
do $$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'perf_old') <> 3 then
    raise exception 'perf_old does not hold the three old reporting functions';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'perf_old'
                and p.prosrc like '%public.expense_period_contributions%') then
    raise exception 'an old function still reads the public (new) projection';
  end if;
end $$;
