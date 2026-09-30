-- Server migration ledger name: reporting_snapshot_page_windowed
--
-- Phase 8 · D-320 R3 acceptance, recorded as D-321. The contract of
-- `reporting_snapshot_page` is UNCHANGED — same parameters, same page, same rows, same
-- `has_more`, same authority. What changes is how the server finds a page's rows.
--
-- ── The defect the STRESS acceptance found ────────────────────────────────────────────
--
-- Each page selected its candidates with
--
--     … from expense_period_contributions c where … order by (generation, id) limit 4n+1
--
-- The projection is a security_barrier view, so PostgreSQL plans it as a separate
-- subquery: it cannot push the ORDER BY … LIMIT into it and cannot use the
-- (org_id, change_seq, id) index to stop early. Every page therefore joined and sorted
-- the caller's WHOLE history before returning n documents. Pages were bounded in size and
-- not in cost: at STRESS (499,975 rows over five years) one page cost 3–4 s warm, a cold
-- first page was cancelled at the 8 s `authenticated` statement timeout, and a paged
-- first synchronisation grew with the square of the history.
--
-- ── The fix, and why the answer is identical ──────────────────────────────────────────
--
-- A comparison on the generation (bigint, leakproof) IS pushed into the view, and a
-- bounded range on it is served by expenses_org_change_seq_idx / revenue_entries_org_
-- change_seq_idx. So each page now reads a generation WINDOW [lo, hi]:
--
--   * with no authorised property nothing can qualify and no window is searched;
--   * lo is the cursor's generation (inclusive — the id tie-break still applies), or
--     since + 1 on a delta, or — on the first page of a first synchronisation — the lowest
--     generation of any row in the requested financial years (one bounded year-range
--     aggregate, never the whole history);
--   * hi starts at lo + 8n − 1 and grows fourfold until the window holds 4n + 1
--     qualifying rows, or until it covers every generation there can be;
--   * the page's candidates are the window's rows in (generation, id) order, limit 4n + 1;
--   * the page's rows are then fetched inside its documents' own generation range — every
--     row of a document carries the document's generation — so that read is an index
--     range too, where `document id IN (…)` alone could not cross the security barrier. The
--     membership test is an array comparison, not a semi-join: the planner cannot estimate
--     the page's document list and would otherwise re-scan the window once per document.
--
-- Every row outside the window has a higher generation than every row inside it, so when
-- the window holds 4n + 1 qualifying rows they ARE the first 4n + 1 overall, and when it
-- covers everything it holds them all. The candidates — and therefore the documents, the
-- rows and `has_more` — are exactly what the previous body returned for the same
-- arguments. Nothing about authority, snapshot coherence (D-188) or the client moves.
--
-- `reporting_newer_than` is unchanged.

begin;

create or replace function public.reporting_snapshot_page(
  p_business_unit_ids uuid[],
  p_financial_years   integer[],
  p_revenue_since     bigint  default 0,
  p_expense_since     bigint  default 0,
  p_revenue_after_seq bigint  default null,
  p_revenue_after_id  uuid    default null,
  p_expense_after_seq bigint  default null,
  p_expense_after_id  uuid    default null,
  p_page_documents    integer default 1000
) returns jsonb
language sql
volatile
security invoker
set search_path = public, pg_temp
as $fn$
  with recursive requested as (
    select distinct u as business_unit_id
      from unnest(coalesce(p_business_unit_ids, '{}'::uuid[])) as u
     where u is not null
  ),
  authority as (
    select r.business_unit_id,
           public.has_capability('reports.view', r.business_unit_id)
             and public.has_capability('revenue.view', r.business_unit_id)
             and public.has_capability('expense.view.all', r.business_unit_id)
             as reporting_authorised
      from requested r
  ),
  params as (
    select q.*,
           -- The requested financial years as one P&L-date range, so the first page of a
           -- first synchronisation can find its lowest generation from a bounded scan.
           make_date((select min(y) from unnest(q.years) y), 4, 1) as y_from,
           make_date((select max(y) from unnest(q.years) y) + 1, 4, 1) as y_until
      from (
        select array(select a.business_unit_id from authority a where a.reporting_authorised)
                 as units,
               array(select distinct y from unnest(coalesce(p_financial_years, '{}'::int[])) y
                      where y is not null) as years,
               least(greatest(coalesce(p_page_documents, 1000), 1), 2000) as n,
               coalesce(p_revenue_since, 0) as rev_since,
               coalesce(p_expense_since, 0) as exp_since
      ) q
  ),
  -- ── Expenses ──────────────────────────────────────────────────────────────────────
  exp_lo as (
    select case
             -- No authorised property: nothing can qualify, so no window is searched.
             when cardinality(p.units) = 0 then null
             when p_expense_after_seq is not null then p_expense_after_seq
             when p.exp_since > 0 then p.exp_since + 1
             else (select min(c.document_change_seq)
                     from public.expense_period_contributions c
                    where c.business_unit_id = any (p.units)
                      and c.pnl_date >= p.y_from and c.pnl_date < p.y_until
                      and (case when extract(month from c.pnl_date) >= 4
                                then extract(year from c.pnl_date)
                                else extract(year from c.pnl_date) - 1 end)::int
                            = any (p.years))
           end as lo
      from params p
  ),
  exp_win(k, hi, cnt) as (
    select 0, l.lo + p.n * 8 - 1,
           (select count(*) from (
              select 1 from public.expense_period_contributions c
               where c.business_unit_id = any (p.units)
                 and c.document_change_seq >= l.lo
                 and c.document_change_seq <= l.lo + p.n * 8 - 1
                 and c.document_change_seq > p.exp_since
                 and (c.document_change_seq, c.expense_id)
                       > (coalesce(p_expense_after_seq, -1),
                          coalesce(p_expense_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
                 and (p.exp_since > 0
                      or (case when extract(month from c.pnl_date) >= 4
                               then extract(year from c.pnl_date)
                               else extract(year from c.pnl_date) - 1 end)::int
                           = any (p.years))
               limit p.n * 4 + 1) s)
      from exp_lo l, params p
     where l.lo is not null
    union all
    select w.k + 1, x.hi,
           (select count(*) from (
              select 1 from public.expense_period_contributions c
               where c.business_unit_id = any (p.units)
                 and c.document_change_seq >= l.lo
                 and c.document_change_seq <= x.hi
                 and c.document_change_seq > p.exp_since
                 and (c.document_change_seq, c.expense_id)
                       > (coalesce(p_expense_after_seq, -1),
                          coalesce(p_expense_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
                 and (p.exp_since > 0
                      or (case when extract(month from c.pnl_date) >= 4
                               then extract(year from c.pnl_date)
                               else extract(year from c.pnl_date) - 1 end)::int
                           = any (p.years))
               limit p.n * 4 + 1) s)
      from exp_win w
      cross join exp_lo l
      cross join params p
      cross join lateral (
        select case when w.hi - l.lo + 1 >= 1152921504606846976
                    then 9223372036854775807
                    else w.hi + (w.hi - l.lo + 1) * 3 end as hi) x
     where w.cnt < p.n * 4 + 1
       and w.hi < 9223372036854775807
  ),
  exp_hi as (
    select w.hi from exp_win w order by w.k desc limit 1
  ),
  exp_cand as (
    select c.expense_id as id, c.document_change_seq as seq
      from public.expense_period_contributions c
     where c.business_unit_id = any ((select units from params)::uuid[])
       and c.document_change_seq >= (select lo from exp_lo)
       and c.document_change_seq <= (select hi from exp_hi)
       and c.document_change_seq > (select exp_since from params)
       and (c.document_change_seq, c.expense_id)
             > (coalesce(p_expense_after_seq, -1),
                coalesce(p_expense_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
       and ((select exp_since from params) > 0
            or (case when extract(month from c.pnl_date) >= 4
                     then extract(year from c.pnl_date)
                     else extract(year from c.pnl_date) - 1 end)::int
                 = any ((select years from params)::int[]))
     order by c.document_change_seq, c.expense_id
     limit (select n * 4 + 1 from params)
  ),
  exp_docs as (
    select d.id, d.seq
      from (select distinct id, seq from exp_cand) d
     order by d.seq, d.id
     limit (select n from params)
  ),
  exp_rows as (
    select c.*
      from public.expense_period_contributions c
     where c.expense_id = any ((select array_agg(id) from exp_docs)::uuid[])
       -- Every row of a document carries the document's generation, so the page's rows lie
       -- inside its documents' generation range: a pushed-down, index-served bound.
       and c.document_change_seq >= (select min(seq) from exp_docs)
       and c.document_change_seq <= (select max(seq) from exp_docs)
       and c.business_unit_id = any ((select units from params)::uuid[])
       and (case when extract(month from c.pnl_date) >= 4
                 then extract(year from c.pnl_date)
                 else extract(year from c.pnl_date) - 1 end)::int
             = any ((select years from params)::int[])
  ),
  -- ── Revenue ───────────────────────────────────────────────────────────────────────
  rev_lo as (
    select case
             -- No authorised property: nothing can qualify, so no window is searched.
             when cardinality(p.units) = 0 then null
             when p_revenue_after_seq is not null then p_revenue_after_seq
             when p.rev_since > 0 then p.rev_since + 1
             else (select min(c.change_seq)
                     from public.revenue_period_contributions c
                    where c.business_unit_id = any (p.units)
                      and c.pnl_date >= p.y_from and c.pnl_date < p.y_until
                      and (case when extract(month from c.pnl_date) >= 4
                                then extract(year from c.pnl_date)
                                else extract(year from c.pnl_date) - 1 end)::int
                            = any (p.years))
           end as lo
      from params p
  ),
  rev_win(k, hi, cnt) as (
    select 0, l.lo + p.n * 8 - 1,
           (select count(*) from (
              select 1 from public.revenue_period_contributions c
               where c.business_unit_id = any (p.units)
                 and c.change_seq >= l.lo
                 and c.change_seq <= l.lo + p.n * 8 - 1
                 and c.change_seq > p.rev_since
                 and (c.change_seq, c.revenue_entry_id)
                       > (coalesce(p_revenue_after_seq, -1),
                          coalesce(p_revenue_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
                 and (p.rev_since > 0
                      or (case when extract(month from c.pnl_date) >= 4
                               then extract(year from c.pnl_date)
                               else extract(year from c.pnl_date) - 1 end)::int
                           = any (p.years))
               limit p.n * 4 + 1) s)
      from rev_lo l, params p
     where l.lo is not null
    union all
    select w.k + 1, x.hi,
           (select count(*) from (
              select 1 from public.revenue_period_contributions c
               where c.business_unit_id = any (p.units)
                 and c.change_seq >= l.lo
                 and c.change_seq <= x.hi
                 and c.change_seq > p.rev_since
                 and (c.change_seq, c.revenue_entry_id)
                       > (coalesce(p_revenue_after_seq, -1),
                          coalesce(p_revenue_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
                 and (p.rev_since > 0
                      or (case when extract(month from c.pnl_date) >= 4
                               then extract(year from c.pnl_date)
                               else extract(year from c.pnl_date) - 1 end)::int
                           = any (p.years))
               limit p.n * 4 + 1) s)
      from rev_win w
      cross join rev_lo l
      cross join params p
      cross join lateral (
        select case when w.hi - l.lo + 1 >= 1152921504606846976
                    then 9223372036854775807
                    else w.hi + (w.hi - l.lo + 1) * 3 end as hi) x
     where w.cnt < p.n * 4 + 1
       and w.hi < 9223372036854775807
  ),
  rev_hi as (
    select w.hi from rev_win w order by w.k desc limit 1
  ),
  rev_cand as (
    select c.revenue_entry_id as id, c.change_seq as seq
      from public.revenue_period_contributions c
     where c.business_unit_id = any ((select units from params)::uuid[])
       and c.change_seq >= (select lo from rev_lo)
       and c.change_seq <= (select hi from rev_hi)
       and c.change_seq > (select rev_since from params)
       and (c.change_seq, c.revenue_entry_id)
             > (coalesce(p_revenue_after_seq, -1),
                coalesce(p_revenue_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
       and ((select rev_since from params) > 0
            or (case when extract(month from c.pnl_date) >= 4
                     then extract(year from c.pnl_date)
                     else extract(year from c.pnl_date) - 1 end)::int
                 = any ((select years from params)::int[]))
     order by c.change_seq, c.revenue_entry_id
     limit (select n * 4 + 1 from params)
  ),
  rev_docs as (
    select d.id, d.seq
      from (select distinct id, seq from rev_cand) d
     order by d.seq, d.id
     limit (select n from params)
  ),
  rev_rows as (
    select c.*
      from public.revenue_period_contributions c
     where c.revenue_entry_id = any ((select array_agg(id) from rev_docs)::uuid[])
       and c.change_seq >= (select min(seq) from rev_docs)
       and c.change_seq <= (select max(seq) from rev_docs)
       and c.business_unit_id = any ((select units from params)::uuid[])
       and (case when extract(month from c.pnl_date) >= 4
                 then extract(year from c.pnl_date)
                 else extract(year from c.pnl_date) - 1 end)::int
             = any ((select years from params)::int[])
  )
  select jsonb_build_object(
    'snapshot_id', pg_current_snapshot()::text,
    'server_time', now(),
    'page_documents', (select n from params),
    'units', coalesce((
      select jsonb_agg(jsonb_build_object(
               'business_unit_id',     a.business_unit_id,
               'reporting_authorised', a.reporting_authorised)
             order by a.business_unit_id)
        from authority a), '[]'::jsonb),
    'revenue', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.change_seq, r.revenue_entry_id, r.id)
        from rev_rows r), '[]'::jsonb),
    'revenue_documents', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq) order by d.seq, d.id)
        from rev_docs d), '[]'::jsonb),
    'revenue_has_more',
      (select count(*) from rev_cand) > (select n * 4 from params)
      or (select count(distinct id) from rev_cand) > (select n from params),
    'expense', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.document_change_seq, x.expense_id, x.id)
        from exp_rows x), '[]'::jsonb),
    'expense_documents', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq) order by d.seq, d.id)
        from exp_docs d), '[]'::jsonb),
    'expense_has_more',
      (select count(*) from exp_cand) > (select n * 4 from params)
      or (select count(distinct id) from exp_cand) > (select n from params))
$fn$;

comment on function public.reporting_snapshot_page(
  uuid[], integer[], bigint, bigint, bigint, uuid, bigint, uuid, integer) is
  'One bounded page of the canonical reporting transport (D-320). Documents are paged in '
  '(generation, id) order and never split; each page reads only a generation window that '
  'grows until it holds the page''s candidates (D-321). The page on which both datasets '
  'report has_more = false certifies the run. D-164 authority per unit, SECURITY INVOKER '
  'over the two reporting projections. Canonical facts only - no derived P&L arithmetic.';

revoke all on function public.reporting_snapshot_page(
  uuid[], integer[], bigint, bigint, bigint, uuid, bigint, uuid, integer)
  from public, anon;
grant execute on function public.reporting_snapshot_page(
  uuid[], integer[], bigint, bigint, bigint, uuid, bigint, uuid, integer)
  to authenticated;

-- ── Invariants ─────────────────────────────────────────────────────────────────────
do $inv$
declare
  r      record;
  v_anon text;
begin
  select p.proname, p.prosecdef, l.lanname, p.prosrc, p.proconfig into r
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
   where n.nspname = 'public' and p.proname = 'reporting_snapshot_page';
  if r.prosecdef then
    raise exception 'reporting_snapshot_page must be SECURITY INVOKER';
  end if;
  if r.lanname <> 'sql' then
    raise exception 'reporting_snapshot_page must be one SQL statement (one MVCC snapshot)';
  end if;
  if r.proconfig is null
     or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
    raise exception 'reporting_snapshot_page must pin search_path';
  end if;
  if position('''reports.view''' in r.prosrc) = 0
     or position('''revenue.view''' in r.prosrc) = 0
     or position('''expense.view.all''' in r.prosrc) = 0 then
    raise exception 'reporting_snapshot_page lost part of the D-164 intersection';
  end if;
  if r.prosrc ~* '\m(owner|manager|accountant|data_entry)\M' then
    raise exception 'reporting_snapshot_page branches on a role name';
  end if;
  if r.prosrc ~* '\m(from|join)\s+public\.(expenses|expense_allocations|expense_period_allocations|revenue_entries|revenue_components)\M' then
    raise exception 'reporting_snapshot_page reads a financial base table';
  end if;
  if r.prosrc ~* '\m(float|real|double\s+precision|numeric)\M'
     or r.prosrc ~* '\m(net_sales|operating_profit|margin|rate_bp\s*[*/])\M' then
    raise exception 'reporting_snapshot_page performs arithmetic a reporting transport must not';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'reporting_snapshot_page') <> 1 then
    raise exception 'reporting_snapshot_page must exist exactly once';
  end if;
  if not has_function_privilege('authenticated',
       'public.reporting_snapshot_page(uuid[], integer[], bigint, bigint, bigint, uuid, bigint, uuid, integer)',
       'execute') then
    raise exception 'reporting_snapshot_page is not callable by authenticated';
  end if;
  select string_agg(p.proname, ', ') into v_anon
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if v_anon is not null then
    raise exception 'anon can execute functions in public: %', v_anon;
  end if;
end $inv$;

commit;
