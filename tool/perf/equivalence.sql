-- Phase 8 · D-320 authorisation equivalence gate.
--
-- The D-318 redesign (R1, R2, R3) may change HOW authority is evaluated and HOW rows are
-- delivered. It may not change WHICH rows any principal can see. This proves it on the
-- loaded dataset by exact row identity — never by count — comparing the pre-redesign
-- definitions (captured into `perf_old` by capture_old.sql) with the live ones, for every
-- principal, scope and surface, before and after authority transitions. Then it plants a
-- widening in each new path, inside a rolled-back transaction, and requires the gate to go
-- red.
--
-- Run after synth.sh. Harness only; refuses to run anywhere else.
\set ON_ERROR_STOP 1
do $$
begin
  if current_database() <> 'krishna_perf' or current_setting('listen_addresses') <> ''
     or not exists (select 1 from pg_namespace where nspname = 'perf_old') then
    raise exception 'equivalence.sql runs only inside the local harness, after capture_old.sql';
  end if;
end $$;

-- ── Additional principals, by capability set ─────────────────────────────────────────
--   a..06 mixed      data_entry (view.own) on CCR + manager (view.all) on HKI
--   a..07 noauth     a profile with no grant at all
--   a..08 revoked    manager on CCR, granted and then revoked
--   a..09 reports    a custom role holding ONLY reports.view, on CCR
--   a..10 two_scoped manager on CCR and manager on HKI — two scoped grants, not consolidated
--   a..12 owner2     a second unscoped owner, used for consolidated-scope loss
insert into auth.users (id, email) values
  ('a0000000-0000-4000-8000-000000000006', 'perf.mixed@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000007', 'perf.noauth@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000008', 'perf.revoked@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000009', 'perf.reports.only@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000010', 'perf.two.scoped@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000012', 'perf.owner2@krishna-perf.invalid')
on conflict do nothing;
select app.bootstrap_owner('perf.owner2@krishna-perf.invalid', 'Perf Owner 2', true);

insert into public.roles (org_id, code, name, requires_unit_scope)
select app.seed_id('org:KRISHNA'), 'perf_reports_only', 'PERF reports.view only', true
where not exists (select 1 from public.roles where code = 'perf_reports_only');
insert into public.role_capabilities (role_id, capability_code)
select r.id, 'reports.view' from public.roles r where r.code = 'perf_reports_only'
on conflict do nothing;

select app.seed_id('bu:CCR') as ccr, app.seed_id('bu:HKI') as hki \gset

begin;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select public.user_provision('perf.mixed@krishna-perf.invalid',        'Perf Mixed');
select public.user_provision('perf.noauth@krishna-perf.invalid',       'Perf No Authority');
select public.user_provision('perf.revoked@krishna-perf.invalid',      'Perf Revoked');
select public.user_provision('perf.reports.only@krishna-perf.invalid', 'Perf Reports Only');
select public.user_provision('perf.two.scoped@krishna-perf.invalid',   'Perf Two Scoped');
select public.user_role_grant('a0000000-0000-4000-8000-000000000006', 'data_entry', :'ccr');
select public.user_role_grant('a0000000-0000-4000-8000-000000000006', 'manager',    :'hki');
select public.user_role_grant('a0000000-0000-4000-8000-000000000008', 'manager',    :'ccr');
select public.user_role_grant('a0000000-0000-4000-8000-000000000009', 'perf_reports_only', :'ccr');
select public.user_role_grant('a0000000-0000-4000-8000-000000000010', 'manager',    :'ccr');
select public.user_role_grant('a0000000-0000-4000-8000-000000000010', 'manager',    :'hki');
commit;
update public.user_roles set revoked_at = now(),
       revoked_by = 'a0000000-0000-4000-8000-000000000001'
 where user_id = 'a0000000-0000-4000-8000-000000000008' and revoked_at is null;

-- Own-recorded documents where they matter: shared (CCR+HKI) documents recorded by the
-- expense.view.own principal and by the mixed principal, and CCR-only documents recorded by
-- the mixed principal. Non-voided only: a voided document is immutable (D-006).
with shared as (
  select e.id, row_number() over (order by e.id) as k
    from public.expenses e
   where e.voided_at is null
     and (select count(distinct a.business_unit_id) from public.expense_allocations a
           where a.expense_id = e.id) = 2
   limit 600)
update public.expenses e
   set created_by = case when s.k % 2 = 0 then 'a0000000-0000-4000-8000-000000000005'::uuid
                         else 'a0000000-0000-4000-8000-000000000006'::uuid end
  from shared s where s.id = e.id;
with ccr_only as (
  select e.id from public.expenses e
   where e.voided_at is null
     and e.created_by = 'a0000000-0000-4000-8000-000000000001'
     and not exists (select 1 from public.expense_allocations a
                      where a.expense_id = e.id and a.business_unit_id <> app.seed_id('bu:CCR'))
   limit 300)
update public.expenses e set created_by = 'a0000000-0000-4000-8000-000000000006'
  from ccr_only c where c.id = e.id;
analyze;

-- ── The comparison machinery ─────────────────────────────────────────────────────────
create temp table verdicts (
  phase text, principal text, surface text, scope text,
  old_n bigint, new_n bigint, only_old bigint, only_new bigint);
grant insert, select on verdicts to authenticated;
create temp table ids_old (k text); create temp table ids_new (k text);
grant insert, select, delete on ids_old, ids_new to authenticated;

-- Each document's own generation, read from the base tables as the harness owner and
-- independent of the new definitions. The delta contract is document-grain (D-320): a
-- document is listed when ITS generation passes the cursor, and every server path that
-- writes an expense's lines also stamps its header in the same transaction (D-177), so no
-- child can change without the document's own generation advancing. The old transport was
-- row-grain, keyed on greatest(header, allocation, period). The two coincide in production
-- and differ in the synthetic load, whose children were all inserted after all headers.
-- The delta check therefore compares against the old authorised rows of every document
-- whose own generation passes the cursor, and counts the child-only rows it set aside.
create temp table doc_gen (id uuid primary key, seq bigint);
insert into doc_gen select id, change_seq from public.expenses
                    union all select id, change_seq from public.revenue_entries;
grant select on doc_gen to authenticated;
create temp table delta_set_aside (principal text, scope text, rows bigint);
grant insert, select on delta_set_aside to authenticated;
create temp table pages (principal text, scope text, since bigint, page int,
                         rev_docs int, exp_docs int, rev_rows int, exp_rows int, ms numeric);
grant insert, select on pages to authenticated;

create function pg_temp.as_principal(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.record(p_phase text, p_who text, p_surface text, p_scope text)
returns void language plpgsql as $$
begin
  insert into verdicts
  select p_phase, p_who, p_surface, p_scope,
         (select count(*) from ids_old), (select count(*) from ids_new),
         (select count(*) from (select k from ids_old except all select k from ids_new) x),
         (select count(*) from (select k from ids_new except all select k from ids_old) x);
  delete from ids_old; delete from ids_new;
end $$;

-- Every page of the new transport, until both datasets are exhausted. Returns every row
-- and every listed document as keys, and records the page shape.
create function pg_temp.new_snapshot(p_who text, p_scope text, p_units uuid[], p_years int[],
                                     p_since bigint, p_page int)
returns void language plpgsql as $$
declare
  j jsonb; rs bigint; ri uuid; es bigint; ei uuid; n int := 0; t0 timestamptz;
  rdone boolean := false; edone boolean := false;
begin
  loop
    n := n + 1;
    t0 := clock_timestamp();
    j := public.reporting_snapshot_page(p_units, p_years, p_since, p_since, rs, ri, es, ei, p_page);
    insert into pages values (p_who, p_scope, p_since, n,
      jsonb_array_length(j -> 'revenue_documents'), jsonb_array_length(j -> 'expense_documents'),
      jsonb_array_length(j -> 'revenue'), jsonb_array_length(j -> 'expense'),
      round((extract(epoch from clock_timestamp() - t0) * 1000)::numeric, 1));
    insert into ids_new select 'rev:' || (r ->> 'id') from jsonb_array_elements(j -> 'revenue') r;
    insert into ids_new select 'exp:' || (r ->> 'id') from jsonb_array_elements(j -> 'expense') r;
    if jsonb_array_length(j -> 'revenue_documents') > 0 then
      rs := (j -> 'revenue_documents' -> -1 ->> 'seq')::bigint;
      ri := (j -> 'revenue_documents' -> -1 ->> 'id')::uuid;
    end if;
    if jsonb_array_length(j -> 'expense_documents') > 0 then
      es := (j -> 'expense_documents' -> -1 ->> 'seq')::bigint;
      ei := (j -> 'expense_documents' -> -1 ->> 'id')::uuid;
    end if;
    exit when not (j ->> 'revenue_has_more')::boolean and not (j ->> 'expense_has_more')::boolean;
    if n > 100000 then raise exception 'paging did not terminate'; end if;
  end loop;
end $$;

create function pg_temp.compare_all(p_phase text, p_who uuid, p_name text) returns void
language plpgsql as $$
declare
  v_units uuid[]; v_scope text; v_all_years int[]; v_since bigint;
  v_ccr uuid := 'ce13c1ce-daed-5084-a23c-c35bb8da0fa8';
  v_hki uuid := '061dfcf5-10bc-58d5-9700-0ffa0e659abe';
  j_old jsonb; j_new jsonb; r record;
begin
  select array_agg(distinct y) into v_all_years from (
    select case when extract(month from pnl_date) >= 4 then extract(year from pnl_date)
                else extract(year from pnl_date) - 1 end::int as y
      from public.expense_period_allocations
    union
    select case when extract(month from business_date) >= 4 then extract(year from business_date)
                else extract(year from business_date) - 1 end::int
      from public.revenue_entries) t;
  select percentile_disc(0.5) within group (order by change_seq) into v_since
    from public.expenses;

  perform pg_temp.as_principal(p_who);

  -- 1 · the two projections, every row, all history
  insert into ids_old select id::text from perf_old.expense_period_contributions;
  insert into ids_new select id::text from public.expense_period_contributions;
  perform pg_temp.record(p_phase, p_name, 'expense_period_contributions', 'all');
  insert into ids_old select id::text from perf_old.revenue_period_contributions;
  insert into ids_new select id::text from public.revenue_period_contributions;
  perform pg_temp.record(p_phase, p_name, 'revenue_period_contributions', 'all');

  -- 2 · reporting_primitives, per scope and range, the whole answer minus the clock
  for v_scope, v_units in
    select * from (values ('CCR', array[v_ccr]), ('HKI', array[v_hki]),
                          ('both', array[v_ccr, v_hki])) s(a, b)
  loop
    for r in select * from (values ('month', date '2027-01-01', date '2027-01-31'),
                                   ('FY',    date '2026-04-01', date '2027-03-31')) d(l, f, t)
    loop
      j_old := perf_old.reporting_primitives(v_units, r.f, r.t, true) - 'server_time';
      j_new := public.reporting_primitives(v_units, r.f, r.t, true) - 'server_time';
      insert into ids_old select j_old::text;
      insert into ids_new select j_new::text;
      perform pg_temp.record(p_phase, p_name, 'reporting_primitives', v_scope || ' ' || r.l);
    end loop;

    -- 3 · the transport: old single answer vs every page of the new one, all history
    j_old := perf_old.reporting_snapshot(v_units, 0, 0);
    insert into ids_old select 'rev:' || (x ->> 'id') from jsonb_array_elements(j_old -> 'revenue') x;
    insert into ids_old select 'exp:' || (x ->> 'id') from jsonb_array_elements(j_old -> 'expense') x;
    perform pg_temp.new_snapshot(p_name, v_scope, v_units, v_all_years, 0, 1000);
    perform pg_temp.record(p_phase, p_name, 'snapshot bootstrap', v_scope);

    -- 4 · a delta from the median document generation
    --     (document-grain; see doc_gen above)
    j_old := perf_old.reporting_snapshot(v_units, v_since, v_since);
    insert into ids_old select 'rev:' || (x ->> 'id') from jsonb_array_elements(j_old -> 'revenue') x
      join doc_gen d on d.id = (x ->> 'revenue_entry_id')::uuid where d.seq > v_since;
    insert into ids_old select 'exp:' || (x ->> 'id') from jsonb_array_elements(j_old -> 'expense') x
      join doc_gen d on d.id = (x ->> 'expense_id')::uuid where d.seq > v_since;
    insert into delta_set_aside
    select p_name, v_scope,
           (select count(*) from jsonb_array_elements(j_old -> 'revenue') x
              join doc_gen d on d.id = (x ->> 'revenue_entry_id')::uuid where d.seq <= v_since)
         + (select count(*) from jsonb_array_elements(j_old -> 'expense') x
              join doc_gen d on d.id = (x ->> 'expense_id')::uuid where d.seq <= v_since);
    perform pg_temp.new_snapshot(p_name, v_scope, v_units, v_all_years, v_since, 1000);
    perform pg_temp.record(p_phase, p_name, 'snapshot delta', v_scope);

    -- 5 · the head check, where old and new share a meaning (cursor 0: anything at all)
    insert into ids_old select (perf_old.reporting_newer_than(v_units, 0, 0) - 'server_time')::text;
    insert into ids_new select (public.reporting_newer_than(v_units, 0, 0) - 'server_time')::text;
    perform pg_temp.record(p_phase, p_name, 'reporting_newer_than(0)', v_scope);
  end loop;

  execute 'set local role none';
end $$;

-- ── Phase A · every principal, as loaded ─────────────────────────────────────────────
begin;
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000001', 'owner');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000002', 'ccr_manager');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000003', 'hki_manager');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000004', 'accountant');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000005', 'data_entry');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000006', 'mixed');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000007', 'noauth');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000008', 'revoked');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000009', 'reports_only');
select pg_temp.compare_all('A', 'a0000000-0000-4000-8000-000000000010', 'two_scoped');
select pg_temp.compare_all('A', '00000000-0000-4000-8000-00000000dead', 'unknown');
commit;

-- ── Phase B · authority transitions ──────────────────────────────────────────────────
-- property-scope loss: the CCR manager loses CCR; capability revocation: the accountant's
-- role loses expense.view.all for everyone holding it (restored at the end); consolidated
-- loss: the second owner's unscoped grant is revoked.
update public.user_roles set revoked_at = now(),
       revoked_by = 'a0000000-0000-4000-8000-000000000001'
 where user_id = 'a0000000-0000-4000-8000-000000000002' and revoked_at is null;
update public.user_roles set revoked_at = now(),
       revoked_by = 'a0000000-0000-4000-8000-000000000001'
 where user_id = 'a0000000-0000-4000-8000-000000000012' and revoked_at is null;
create temp table saved_caps as
  select rc.* from public.role_capabilities rc join public.roles r on r.id = rc.role_id
   where r.code = 'accountant' and rc.capability_code = 'expense.view.all';
delete from public.role_capabilities rc using public.roles r
 where r.id = rc.role_id and r.code = 'accountant' and rc.capability_code = 'expense.view.all';

begin;
select pg_temp.compare_all('B', 'a0000000-0000-4000-8000-000000000002', 'ccr_manager, CCR lost');
select pg_temp.compare_all('B', 'a0000000-0000-4000-8000-000000000012', 'owner2, unscoped lost');
select pg_temp.compare_all('B', 'a0000000-0000-4000-8000-000000000004', 'accountant, view.all lost');
commit;

insert into public.role_capabilities select * from saved_caps;

-- ── Report ───────────────────────────────────────────────────────────────────────────
\echo
select phase, principal, surface, scope, old_n, new_n, only_old, only_new,
       case when only_old = 0 and only_new = 0 then 'PASS' else 'FAIL' end as verdict
  from verdicts order by phase, principal, surface, scope;

select count(*) as checks,
       count(*) filter (where only_old = 0 and only_new = 0) as identical,
       count(*) filter (where only_old <> 0 or only_new <> 0) as different,
       sum(old_n) as rows_compared
  from verdicts;

-- Rows the old row-grain delta returned for documents whose own generation is at or below
-- the cursor (child-only generations: the synthetic load, not a production path).
select principal, scope, rows as delta_rows_set_aside
  from delta_set_aside where principal in ('owner', 'ccr_manager', 'hki_manager')
 order by 1, 2;

select principal, scope, since, count(*) as pages,
       max(rev_docs + exp_docs) as max_docs_per_page,
       max(rev_rows + exp_rows) as max_rows_per_page, round(avg(ms), 1) as avg_ms
  from pages where principal in ('owner', 'ccr_manager')
 group by 1, 2, 3 order by 1, 2, 3;

-- ── Positive controls: each widens ONE new path inside a rolled-back transaction ─────
-- C1 · the expense projection ignores the D-169 document rule
begin;
create or replace view public.expense_period_contributions with (security_barrier = true) as
select p.id, p.org_id, p.expense_id, p.allocation_id, p.business_unit_id, a.department_id,
       a.section_id, a.category_id, p.accounting_period_start, p.accounting_period_end,
       p.pnl_date, p.pnl_period_key, p.amount_minor, p.is_derived, e.business_date,
       e.payment_status, e.payment_date, e.vendor_id, e.voided_at,
       greatest(e.change_seq, a.change_seq, p.change_seq) as change_seq, e.txn_number,
       e.change_seq as document_change_seq
  from public.expense_period_allocations p
  join public.expense_allocations a on a.id = p.allocation_id
  join public.expenses e on e.id = p.expense_id
 where p.org_id = (select public.current_org_id())
   and p.business_unit_id in (select public.expense_visible_units());
select pg_temp.as_principal('a0000000-0000-4000-8000-000000000005');
insert into ids_old select id::text from perf_old.expense_period_contributions;
insert into ids_new select id::text from public.expense_period_contributions;
select 'CONTROL C1 (must differ): data_entry epc — old ' || (select count(*) from ids_old)
       || ', widened ' || (select count(*) from ids_new)
       || ', extra rows ' || (select count(*) from (select k from ids_new except all select k from ids_old) x)
       as control;
do $$
begin
  if not exists (select k from ids_new except all select k from ids_old) then
    raise exception 'CONTROL C1 DID NOT GO RED: the gate cannot see this widening';
  end if;
end $$;
rollback;

-- C2 · the revenue projection ignores revenue.view
begin;
create or replace view public.revenue_period_contributions with (security_barrier = true) as
select c.id, c.org_id, c.revenue_entry_id, e.business_unit_id, e.revenue_category_id,
       c.supply_subtype_id, c.value_band_id, c.value_band_floor_minor as value_band_min_minor,
       c.value_band_ceiling_minor as value_band_max_minor, c.premises_status_code,
       e.business_date, e.business_date as pnl_date, e.pnl_period_key,
       c.gross_amount_minor as gross_minor, c.tax_amount_minor as tax_minor,
       c.net_amount_minor as net_minor, c.tax_rule_id, c.tax_rate_bp, c.tax_treatment,
       c.entered_basis, e.entry_kind, e.txn_number, e.business_date_source, e.voided_at,
       e.change_seq
  from public.revenue_components c join public.revenue_entries e on e.id = c.revenue_entry_id
 where e.org_id = (select public.current_org_id());
select pg_temp.as_principal('a0000000-0000-4000-8000-000000000003');
insert into ids_old select id::text from perf_old.revenue_period_contributions;
insert into ids_new select id::text from public.revenue_period_contributions;
select 'CONTROL C2 (must differ): hki_manager rpc — old ' || (select count(*) from ids_old)
       || ', widened ' || (select count(*) from ids_new)
       || ', extra rows ' || (select count(*) from (select k from ids_new except all select k from ids_old) x)
       as control;
do $$
begin
  if not exists (select k from ids_new except all select k from ids_old) then
    raise exception 'CONTROL C2 DID NOT GO RED: the gate cannot see this widening';
  end if;
end $$;
rollback;

-- C3 · the paged transport forgets the per-unit authority and pages every requested unit.
-- The principal is `mixed`: view.own on CCR (the projection lets their own CCR expenses
-- through) but no reports.view there, so the per-unit reporting authority is the ONLY
-- thing that keeps those rows out. A principal with no expense authority at all on the
-- unit would be stopped by the projection itself and would prove nothing about this gate.
begin;
do $c3$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p join pg_namespace n
    on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'reporting_snapshot_page';
  v_src := replace(v_src,
    'select array(select a.business_unit_id from authority a where a.reporting_authorised)',
    'select array(select a.business_unit_id from authority a)');
  if v_src not like '%select array(select a.business_unit_id from authority a)%' then
    raise exception 'CONTROL C3 could not plant its widening: the source text moved';
  end if;
  execute v_src;
end $c3$;
select pg_temp.as_principal('a0000000-0000-4000-8000-000000000006');
select public.reporting_snapshot_page(
         array['ce13c1ce-daed-5084-a23c-c35bb8da0fa8'::uuid], array[2026], 0, 0,
         null, null, null, null, 50) -> 'expense' as j \gset
select 'CONTROL C3 (must differ): mixed paging CCR with reporting authority removed — expense rows '
       || jsonb_array_length(:'j'::jsonb) || ' (the real function returns 0)' as control;
select set_config('perf.c3', :'j', true) is not null as c3_recorded;
do $$
begin
  if jsonb_array_length(current_setting('perf.c3')::jsonb) = 0 then
    raise exception 'CONTROL C3 DID NOT GO RED: the gate cannot see this widening';
  end if;
end $$;
rollback;

select case when md5(pg_get_viewdef('public.expense_period_contributions'::regclass, true))
                 <> md5(pg_get_viewdef('perf_old.expense_period_contributions'::regclass, true))
            then 'controls rolled back: the redesigned projection is in place'
            else 'NOT RESTORED' end as restore;

do $$
begin
  if exists (select 1 from verdicts where only_old <> 0 or only_new <> 0) then
    raise exception 'AUTHORISATION EQUIVALENCE FAILED';
  end if;
end $$;
