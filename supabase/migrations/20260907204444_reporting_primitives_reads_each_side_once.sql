-- Phase 5 Slice 5 · the reporting boundary reads each side once.
--
-- A measured change, not a speculative one. `EXPLAIN (ANALYZE, BUFFERS)` as the development
-- Owner, over the whole of FY 2026-27:
--
--     revenue aggregate    0.3 ms   Index Scan using revenue_entries_reporting_idx
--     expense aggregate  368.7 ms   Index Scan on expense_period_allocations,
--                                   Filter: may_read_expense(expense_id)  -- 1,094 rows,
--                                   11,240 buffer hits inside that one node
--     reporting_primitives(both units, whole FY, breakdown)   774 ms
--
-- The expense projection carries a per-row `security definer` predicate (D-169), so every
-- candidate row costs a function call. The first version of this function scanned that
-- projection **twice** whenever a breakdown was asked for — once for the headline figure and
-- once for the hierarchy lines — and so paid that cost twice for an answer it already had.
--
-- ── What changes, and what provably does not ─────────────────────────────────
--
-- Each side is now grouped **once**, at its finest grain, and the headline figure is rolled
-- up from those subtotals. Integer addition is associative, so the rolled-up total is the
-- same integer as the direct sum, to the paisa — there is no rounding anywhere to be
-- reordered, because rounding happened once at the component and was stored (spec §6.5,
-- D-017). `p_breakdown` now governs only **what is returned**, not what is read.
--
-- Nothing else moves: same signature, same `security invoker`, same per-side authority on
-- `revenue.view` and `expense.view.all`, same null-not-zero for an unauthorised side, same
-- single statement and therefore the same one snapshot across both sides, same `pnl_date`
-- basis, same exclusion of voided and unaccepted documents.
--
-- ── What is recorded and deliberately not changed ────────────────────────────
--
-- `may_read_expense` being evaluated once per candidate row is the dominant remaining cost,
-- and it is not touched here. It is a reviewed authority predicate: making it cheaper is a
-- change to how an expense's visibility is decided, which belongs with the reporting
-- capability model (Slice 7) or performance hardening (Slice 8), not inside a parity slice
-- (D-127). At V1 volume a whole financial year costs a third of a second and no screen
-- exists yet that asks for one; the escalation trigger in `ARCHITECTURE.md` §9 is recorded
-- against a one-month range, which measures 80–185 ms end to end including the round trip
-- to Mumbai.
--
-- No materialised view and no aggregate table: nothing has been measured that needs one.

create or replace function public.reporting_primitives(
  p_business_unit_ids uuid[],
  p_from date,
  p_to date,
  p_breakdown boolean default false
) returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $fn$
  with requested as (
    select distinct u as business_unit_id
      from unnest(coalesce(p_business_unit_ids, '{}'::uuid[])) as u
     where u is not null
  ),
  authority as (
    select r.business_unit_id,
           public.has_capability('revenue.view', r.business_unit_id)     as revenue_authorised,
           public.has_capability('expense.view.all', r.business_unit_id) as expense_authorised
      from requested r
  ),
  rev_rows as (
    select c.business_unit_id,
           c.revenue_category_id,
           -- `none` and a configured 0% both give zero tax and are different facts, so the
           -- treatment travels; a group spanning both is described by neither (D-091).
           case when count(distinct c.tax_treatment) = 1
                then min(c.tax_treatment) end as tax_treatment,
           sum(c.gross_minor)::bigint as gross_minor,
           sum(c.tax_minor)::bigint   as tax_minor,
           sum(c.net_minor)::bigint   as net_minor,
           count(*)::bigint           as contributions
      from public.revenue_period_contributions c
      join authority a
        on a.business_unit_id = c.business_unit_id and a.revenue_authorised
     where c.voided_at is null
       and c.txn_number is not null
       and c.pnl_date >= p_from
       and c.pnl_date <= p_to
     group by c.business_unit_id, c.revenue_category_id
  ),
  exp_rows as (
    select p.business_unit_id,
           p.department_id,
           p.section_id,
           p.category_id,
           sum(p.amount_minor)::bigint as amount_minor,
           count(*)::bigint            as contributions
      from public.expense_period_contributions p
      join authority a
        on a.business_unit_id = p.business_unit_id and a.expense_authorised
     where p.voided_at is null
       and p.txn_number is not null
       and p.pnl_date >= p_from
       and p.pnl_date <= p_to
     group by p.business_unit_id, p.department_id, p.section_id, p.category_id
  ),
  rev as (
    select r.business_unit_id,
           sum(r.gross_minor)::bigint    as gross_minor,
           sum(r.tax_minor)::bigint      as tax_minor,
           sum(r.net_minor)::bigint      as net_minor,
           sum(r.contributions)::bigint  as contributions
      from rev_rows r
     group by r.business_unit_id
  ),
  exp as (
    select e.business_unit_id,
           sum(e.amount_minor)::bigint   as amount_minor,
           sum(e.contributions)::bigint  as contributions
      from exp_rows e
     group by e.business_unit_id
  ),
  rev_cat as (
    select r.business_unit_id,
           jsonb_agg(jsonb_build_object(
             'revenue_category_id', r.revenue_category_id,
             'tax_treatment',       r.tax_treatment,
             'gross_minor',         r.gross_minor,
             'tax_minor',           r.tax_minor,
             'net_minor',           r.net_minor,
             'contributions',       r.contributions)
             order by r.revenue_category_id) as lines
      from rev_rows r
     group by r.business_unit_id
  ),
  exp_cat as (
    select e.business_unit_id,
           jsonb_agg(jsonb_build_object(
             'department_id', e.department_id,
             'section_id',    e.section_id,
             'category_id',   e.category_id,
             'amount_minor',  e.amount_minor,
             'contributions', e.contributions)
             order by e.department_id, e.section_id, e.category_id) as lines
      from exp_rows e
     group by e.business_unit_id
  )
  select jsonb_build_object(
    'from', to_char(p_from, 'YYYY-MM-DD'),
    'to',   to_char(p_to,   'YYYY-MM-DD'),
    'units', coalesce((
      select jsonb_agg(jsonb_build_object(
               'business_unit_id',    a.business_unit_id,
               'revenue_authorised',  a.revenue_authorised,
               'expense_authorised',  a.expense_authorised,
               -- null, never zero, for a side this caller may not read. Zero would be a
               -- figure; this is the absence of one (D-163).
               'revenue', case when a.revenue_authorised then jsonb_build_object(
                   'gross_minor',   coalesce(r.gross_minor, 0),
                   'tax_minor',     coalesce(r.tax_minor, 0),
                   'net_minor',     coalesce(r.net_minor, 0),
                   'contributions', coalesce(r.contributions, 0)) end,
               'expense', case when a.expense_authorised then jsonb_build_object(
                   'amount_minor',  coalesce(x.amount_minor, 0),
                   'contributions', coalesce(x.contributions, 0)) end,
               'revenue_by_category', case when a.revenue_authorised and p_breakdown
                   then coalesce(rc.lines, '[]'::jsonb) else '[]'::jsonb end,
               'expense_by_hierarchy', case when a.expense_authorised and p_breakdown
                   then coalesce(ec.lines, '[]'::jsonb) else '[]'::jsonb end)
             order by a.business_unit_id)
        from authority a
        left join rev     r  on r.business_unit_id  = a.business_unit_id
        left join exp     x  on x.business_unit_id  = a.business_unit_id
        left join rev_cat rc on rc.business_unit_id = a.business_unit_id
        left join exp_cat ec on ec.business_unit_id = a.business_unit_id),
      '[]'::jsonb))
$fn$;

-- ── The Slice 5 invariants, restated over the replacement ────────────────────
--
-- Restated in full rather than trusted to the earlier migration. A `create or replace` is
-- exactly where a `security definer`, a second statement or a lost predicate gets in, and
-- the earlier assertions ran against a body that no longer exists (D-174).

do $inv$
declare
  v_secdef boolean;
  v_lang   text;
  v_vol    char;
  v_src    text;
begin
  select p.prosecdef, l.lanname, p.provolatile, p.prosrc
    into v_secdef, v_lang, v_vol, v_src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
   where n.nspname = 'public' and p.proname = 'reporting_primitives';

  if v_secdef then
    raise exception 'reporting_primitives became security definer';
  end if;
  if v_vol <> 's' then
    raise exception 'reporting_primitives is no longer stable';
  end if;
  if v_lang <> 'sql' then
    raise exception 'reporting_primitives is no longer a single sql statement';
  end if;
  if (length(regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g'))
      - length(replace(regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g'), ';', ''))) > 1 then
    raise exception
      'reporting_primitives contains more than one statement; revenue and expenses would '
      'then be read at two snapshots';
  end if;
  if v_src !~ 'revenue_period_contributions' or v_src !~ 'expense_period_contributions' then
    raise exception 'reporting_primitives does not read the two canonical projections';
  end if;
  if v_src ~ '\mpublic\.expenses\M'
     or v_src ~ '\mpublic\.revenue_entries\M'
     or v_src ~ '\mpublic\.revenue_components\M'
     or v_src ~ '\mpublic\.expense_allocations\M'
     or v_src ~ '\mpublic\.expense_period_allocations\M' then
    raise exception 'reporting_primitives reads a financial base table directly';
  end if;
  if v_src !~ 'revenue\.view' or v_src !~ 'expense\.view\.all' then
    raise exception 'reporting_primitives lost a per-side capability gate (D-164)';
  end if;
  if v_src ~ 'expense\.view\.own' then
    raise exception 'reporting_primitives accepts expense.view.own for a P&L side';
  end if;
  if v_src !~ 'pnl_date' then
    raise exception 'reporting_primitives does not filter on pnl_date';
  end if;
  if v_src ~ '\mcaptured_at\M' or v_src ~ '\mpayment_date\M'
     or v_src ~ '\mcreated_at\M' or v_src ~ '\mbusiness_date\M' then
    raise exception 'reporting_primitives filters on a date basis other than pnl_date';
  end if;
  if v_src ~ '\mtax_rate_bp\M' or v_src ~ '\mrate_bp\M'
     or v_src ~ '\mtax_rule_id\M' or v_src ~ 'revenue_tax_rates' then
    raise exception 'reporting_primitives reaches for tax configuration';
  end if;
  if v_src ~* '\mfloat\M' or v_src ~* '\mreal\M' or v_src ~* 'double precision' then
    raise exception 'reporting_primitives uses binary floating point on money';
  end if;
  if v_src !~ 'coalesce\(p_business_unit_ids' then
    raise exception 'an omitted unit set could widen a report to the whole organisation';
  end if;

  -- And the property this migration exists for: each projection is named once in a `from`,
  -- so a breakdown no longer costs a second pass over the expensive one.
  if (length(v_src) - length(replace(v_src, 'from public.expense_period_contributions', '')))
       / length('from public.expense_period_contributions') <> 1 then
    raise exception
      'the expense projection is scanned more than once; the headline figure rolls up from '
      'the hierarchy subtotals precisely so that it is not';
  end if;
  if (length(v_src) - length(replace(v_src, 'from public.revenue_period_contributions', '')))
       / length('from public.revenue_period_contributions') <> 1 then
    raise exception 'the revenue projection is scanned more than once';
  end if;
end $inv$;

-- Grants are unchanged by `create or replace`, and are asserted rather than assumed.
do $inv$
begin
  if has_function_privilege('anon', 'public.reporting_primitives(uuid[], date, date, boolean)', 'EXECUTE') then
    raise exception 'anon can call the reporting boundary';
  end if;
  if not has_function_privilege('authenticated', 'public.reporting_primitives(uuid[], date, date, boolean)', 'EXECUTE') then
    raise exception 'the reporting boundary is not callable by an authenticated client';
  end if;
end $inv$;
