-- Phase 8 Slice 2 — deterministic synthetic financial year for the local D-186 harness.
--
-- Run by synth.sh once per financial year, each year its own transaction so the deferred
-- balance triggers (expense header = Σ lines, line = Σ period allocations, revenue entry
-- has a component) are checked and committed a year at a time. Nothing is bypassed:
-- every row goes through the same constraints, foreign keys and triggers the server has.
--
-- psql variables:
--   :fy          first calendar year of the financial year (2026 = 2026-04-01 … 2027-03-31)
--   :exp_rows    target expense contribution rows for the year (period-allocation rows)
--   :rev_rows    target revenue contribution rows for the year (components)
--   :seed        generator seed; the same seed gives the same rows
--   :void_pm     voided documents, per mille (default in synth.sh: 100 = 10%)
--   :split_u_pct share of expenses split across BOTH properties (two allocation lines)
--   :split_p_pct share of allocation lines split across two accounting periods
--
-- Every figure is a pure function of (seed, year, row index, purpose) through
-- hashtextextended, so a result can be regenerated exactly. The data is synthetic: no
-- name, amount or business fact is real, every text field says PERF, and it never leaves
-- this cluster.
--
-- Refuses to run anywhere but the harness database with the five synthetic principals.
\set ON_ERROR_STOP 1
do $$
begin
  if current_database() <> 'krishna_perf'
     or current_setting('port') <> '55432'
     or current_setting('listen_addresses') <> ''
     or not exists (select 1 from auth.users where email = 'perf.owner@krishna-perf.invalid') then
    raise exception 'synth.sql runs only inside the local D-186 harness cluster';
  end if;
end $$;

begin;

create temp table ctx on commit drop as
select app.seed_id('org:KRISHNA')   as org,
       app.seed_id('bu:CCR')        as ccr,
       app.seed_id('bu:HKI')        as hki,
       make_date(:fy, 4, 1)         as fy_from,
       make_date(:fy + 1, 3, 31)    as fy_to,
       (make_date(:fy + 1, 3, 31) - make_date(:fy, 4, 1) + 1) as fy_days,
       :'seed' || ':' || :fy        as s;

create function pg_temp.h(p_i bigint, p_k text) returns bigint language sql stable as $$
  select abs(hashtextextended((select s from ctx) || ':' || p_i || ':' || p_k, 0))
$$;

create temp table cats on commit drop as
select row_number() over (partition by c.business_unit_id order by c.id) - 1 as k,
       count(*)     over (partition by c.business_unit_id)                   as n,
       c.id, c.section_id, c.department_id, c.business_unit_id, c.name
  from public.expense_categories c where c.archived_at is null;

-- Principals, by the capability bundle each holds (bootstrap_identities.sql).
create temp table who on commit drop as select * from (values
  ('owner',       'a0000000-0000-4000-8000-000000000001'::uuid),
  ('ccr_manager', 'a0000000-0000-4000-8000-000000000002'::uuid),
  ('hki_manager', 'a0000000-0000-4000-8000-000000000003'::uuid),
  ('data_entry',  'a0000000-0000-4000-8000-000000000005'::uuid)) v(name, id);

-- ---------------------------------------------------------------------------- expenses
-- Expected contribution rows per expense = (1 + split_u) × (1 + split_p). The document
-- count is sized from that; the exact row count produced is reported, not assumed.
create temp table g on commit drop as
with n as (
  select greatest(1, round(:exp_rows / ((1 + :split_u_pct / 100.0) * (1 + :split_p_pct / 100.0))))::int as docs
)
select i,
       gen_random_uuid() as id,
       c.fy_from + (pg_temp.h(i, 'day') % c.fy_days)::int              as bdate,
       (pg_temp.h(i, 'unit') % 100) < 70                               as primary_ccr,
       (pg_temp.h(i, 'split_u') % 100) < :split_u_pct                  as two_units,
       (pg_temp.h(i, 'void') % 1000) < :void_pm                        as voided,
       (1000 + pg_temp.h(i, 'amt') % 5000000)::bigint                  as total,
       pg_temp.h(i, 'who') % 100                                       as who_roll
  from ctx c, n, generate_series(1, n.docs) i;

insert into public.expenses (id, org_id, txn_number, financial_year, business_date,
    total_amount_minor, created_by, captured_at, notes,
    voided_at, voided_by, void_reason)
select g.id, c.org,
       'PERF-EXP-' || :fy || '-' || g.i, :fy::smallint, g.bdate, g.total,
       -- The expense.view.own principal records a tenth of Crystal Canopy's documents, so
       -- the own-document branch of may_read_expense is exercised for real.
       case when g.primary_ccr and not g.two_units then
              case when g.who_roll < 10 then (select id from who where name = 'data_entry')
                   when g.who_roll < 30 then (select id from who where name = 'ccr_manager')
                   else (select id from who where name = 'owner') end
            when not g.primary_ccr and not g.two_units and g.who_roll < 30
              then (select id from who where name = 'hki_manager')
            else (select id from who where name = 'owner') end,
       g.bdate::timestamptz, 'PERF synthetic',
       case when g.voided then g.bdate::timestamptz + interval '1 day' end,
       case when g.voided then (select id from who where name = 'owner') end,
       case when g.voided then 'PERF synthetic void' end
  from g, ctx c;

-- Allocation lines: one line on the primary property, or two lines, one per property.
create temp table l on commit drop as
select g.i, g.id as expense_id, gen_random_uuid() as id, x.unit, x.part, x.amount,
       (pg_temp.h(g.i, 'split_p' || x.part) % 100) < :split_p_pct as two_periods,
       g.bdate
  from g, ctx c,
  lateral (
    select case when g.primary_ccr then c.ccr else c.hki end as unit, 1 as part,
           case when g.two_units then g.total * 6 / 10 else g.total end as amount
    union all
    select case when g.primary_ccr then c.hki else c.ccr end, 2,
           g.total - g.total * 6 / 10
     where g.two_units
  ) x;

insert into public.expense_allocations (id, org_id, expense_id, business_unit_id,
    department_id, section_id, category_id, amount_minor, category_label, sort_order)
select l.id, c.org, l.expense_id, l.unit, k.department_id, k.section_id, k.id, l.amount,
       k.name, l.part - 1
  from l, ctx c
  join lateral (select * from cats k
                 where k.business_unit_id = l.unit
                   and k.k = pg_temp.h(l.i, 'cat' || l.part) % k.n) k on true;

-- Period allocations: the line's own day, or split with the month before (a cross-period
-- bill, D-034). pnl_date = accounting_period_end, as the table's CHECK requires.
insert into public.expense_period_allocations (id, org_id, expense_id, allocation_id,
    business_unit_id, accounting_period_start, accounting_period_end, amount_minor,
    pnl_date, pnl_period_key, is_derived)
select gen_random_uuid(), c.org, l.expense_id, l.id, l.unit, p.ps, p.pe, p.amount,
       p.pe, to_char(p.pe, 'YYYY-MM'), not l.two_periods
  from l, ctx c,
  lateral (
    select l.bdate as ps, l.bdate as pe,
           case when l.two_periods then l.amount - l.amount / 2 else l.amount end as amount
    union all
    select (date_trunc('month', l.bdate) - interval '1 month')::date,
           (date_trunc('month', l.bdate) - interval '1 day')::date,
           l.amount / 2
     where l.two_periods and l.amount / 2 > 0
  ) p;

-- ----------------------------------------------------------------------------- revenue
-- One component per entry, spread over the four revenue categories. The tax figures are
-- the verified baseline's arithmetic (inclusive 5%, Banquet none); the rule snapshot is
-- the baseline rule itself.
create temp table rc on commit drop as
select row_number() over (order by rcat.id) - 1 as k, count(*) over () as n,
       rcat.id, rcat.business_unit_id, r.id as rule_id, r.rate_bp, r.treatment
  from public.revenue_categories rcat
  join public.revenue_tax_rates r on r.revenue_category_id = rcat.id and r.archived_at is null;

create temp table rg on commit drop as
select i, gen_random_uuid() as id,
       c.fy_from + (pg_temp.h(i, 'rday') % c.fy_days)::int as bdate,
       (select rc from rc where rc.k = pg_temp.h(i, 'rcat') % rc.n) as cat,
       (pg_temp.h(i, 'rvoid') % 1000) < :void_pm as voided,
       (10000 + pg_temp.h(i, 'ramt') % 20000000)::bigint as gross
  from ctx c, generate_series(1, greatest(1, :rev_rows)) i;

insert into public.revenue_entries (id, org_id, txn_number, financial_year, business_unit_id,
    revenue_category_id, business_date, pnl_period_key, captured_at, entry_kind, notes,
    created_by, voided_at, voided_by, void_reason)
select rg.id, c.org, 'PERF-REV-' || :fy || '-' || rg.i, :fy || '-' || (:fy + 1),
       (rg.cat).business_unit_id, (rg.cat).id, rg.bdate, to_char(rg.bdate, 'YYYY-MM'),
       rg.bdate::timestamptz, 'shift', 'PERF synthetic',
       (select id from who where name = 'owner'),
       case when rg.voided then rg.bdate::timestamptz + interval '1 day' end,
       case when rg.voided then (select id from who where name = 'owner') end,
       case when rg.voided then 'PERF synthetic void' end
  from rg, ctx c;

insert into public.revenue_components (id, org_id, revenue_entry_id, entered_amount_minor,
    entered_basis, gross_amount_minor, tax_amount_minor, net_amount_minor, tax_rule_id,
    tax_rate_bp, tax_treatment)
select gen_random_uuid(), c.org, rg.id, rg.gross, 'inclusive_total', rg.gross, t.tax,
       rg.gross - t.tax, (rg.cat).rule_id, (rg.cat).rate_bp, (rg.cat).treatment
  from rg, ctx c,
  lateral (select case when (rg.cat).treatment = 'none' then 0
                       else (rg.gross * (rg.cat).rate_bp + (10000 + (rg.cat).rate_bp) / 2)
                            / (10000 + (rg.cat).rate_bp) end as tax) t;

commit;
