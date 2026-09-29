-- Phase 8 Slice 2 — harness self-test: authorization must behave in the harness exactly
-- as the product requires, or no timing taken here means anything.
--
-- Every principal's view of expense_period_contributions is compared with ground truth
-- computed from the base tables by the session role. Then a positive control: inside a
-- transaction that is rolled back, may_read_expense is replaced by `true`, and the
-- expense.view.own principal must immediately see other people's documents — proving the
-- check below it can fail. The rollback restores the function; its definition hash is
-- read back afterwards and compared.
\set ON_ERROR_STOP 1
do $$
begin
  if current_database() <> 'krishna_perf' or current_setting('listen_addresses') <> '' then
    raise exception 'selftest.sql runs only inside the local D-186 harness cluster';
  end if;
end $$;

create temp table truth as
select p.id, p.business_unit_id, e.created_by, bu.code as unit
  from public.expense_period_allocations p
  join public.expenses e on e.id = p.expense_id
  join public.business_units bu on bu.id = p.business_unit_id;
grant select on truth to authenticated;

create temp table verdicts (principal text, check_name text, expected bigint, actual bigint);
grant insert, select on verdicts to authenticated;

create function pg_temp.seen(p_who uuid, p_label text,
                             p_expected bigint, p_filter text) returns void
language plpgsql as $$
declare v bigint;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute 'select count(*) from public.expense_period_contributions c where ' || p_filter
     into v;
  insert into verdicts values (p_who::text, p_label, p_expected, v);
  execute 'set local role none';
end $$;

begin;
select pg_temp.seen('a0000000-0000-4000-8000-000000000001', 'owner: every row',
  (select count(*) from truth), 'true');
select pg_temp.seen('a0000000-0000-4000-8000-000000000002', 'ccr manager: CCR rows',
  (select count(*) from truth where unit = 'CCR'), 'true');
select pg_temp.seen('a0000000-0000-4000-8000-000000000002', 'ccr manager: no HKI row',
  0, 'business_unit_id = ''061dfcf5-10bc-58d5-9700-0ffa0e659abe''::uuid');
select pg_temp.seen('a0000000-0000-4000-8000-000000000003', 'hki manager: HKI rows',
  (select count(*) from truth where unit = 'HKI'), 'true');
select pg_temp.seen('a0000000-0000-4000-8000-000000000004', 'accountant: CCR rows',
  (select count(*) from truth where unit = 'CCR'), 'true');
select pg_temp.seen('a0000000-0000-4000-8000-000000000005', 'data entry: own CCR rows only',
  (select count(*) from truth where unit = 'CCR'
     and created_by = 'a0000000-0000-4000-8000-000000000005'), 'true');
select pg_temp.seen('a0000000-0000-4000-8000-000000000005', 'data entry: nobody else''s',
  0, 'not exists (select 1 from truth t where t.id = c.id and t.created_by = '
     '''a0000000-0000-4000-8000-000000000005'')');
select pg_temp.seen('00000000-0000-0000-0000-000000000000', 'unknown principal: nothing',
  0, 'true');
commit;

select md5(pg_get_functiondef('public.may_read_expense(uuid)'::regprocedure)) as before_md5 \gset

\echo
select check_name, expected, actual,
       case when expected = actual then 'PASS' else 'FAIL' end as verdict
  from verdicts order by check_name;

-- Positive control, in a transaction that is rolled back: the rollback itself restores the
-- function, and its definition hash is read back below.
begin;
create or replace function public.may_read_expense(p_expense_id uuid)
  returns boolean language sql stable security definer set search_path = '' as
  $$ select true $$;
select pg_temp.seen('a0000000-0000-4000-8000-000000000005', 'CONTROL', 0, 'true');
select 'positive control: data entry sees ' || actual
       || ' rows with the predicate disabled, against '
       || (select count(*) from truth where unit = 'CCR'
             and created_by = 'a0000000-0000-4000-8000-000000000005')
       || ' of their own — the checks above can fail' as control
  from verdicts where check_name = 'CONTROL';
rollback;
select md5(pg_get_functiondef('public.may_read_expense(uuid)'::regprocedure)) as after_md5 \gset

select case when :'before_md5' = :'after_md5'
            then 'restored: may_read_expense definition unchanged (' || :'after_md5' || ')'
            else 'NOT RESTORED' end as restore;

do $$
begin
  if exists (select 1 from verdicts where expected <> actual) then
    raise exception 'harness authorization self-test FAILED';
  end if;
end $$;
