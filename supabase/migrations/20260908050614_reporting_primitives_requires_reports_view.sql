-- Phase 5 Slice 5 corrective · the reporting boundary enforces `reports.view`.
--
-- **A security corrective, proven red first.** `reporting_primitives` shipped enforcing
-- D-164's *data* half — `revenue.view` for the revenue side, `expense.view.all` for the
-- expense side — and not `reports.view`. The reasoning recorded in D-184 was that
-- `security invoker` prevents the function returning any row the caller could not already
-- select, so its absence "creates no exposure".
--
-- That reasoning is too narrow, and the project lead has ruled. D-164 is a binding
-- statement about the **reporting authorization contract**, not merely about row exposure:
--
--     Unit P&L requires  reports.view AND revenue.view AND expense.view.all  for that unit.
--     Consolidated P&L requires the corresponding UNSCOPED authority.
--     expense.view.own never qualifies.
--
-- A client-callable P&L RPC that skips the first of those three is under-authorized against
-- the approved contract however little it can expose.
--
-- ── The gap, proven before it was closed ─────────────────────────────────────
--
-- A controlled authority fixture — a principal holding `revenue.view` and
-- `expense.view.all` for Crystal Canopy and **no** `reports.view`, stated by capability and
-- never by role name, so the proof does not depend on today's role templates:
--
--     reports.view      false
--     revenue.view      true
--     expense.view.all  true
--     reporting_primitives(CCR, FY 2026-27)
--       -> expense.amount_minor  22808602   over 63 contributions
--          revenue_authorised    true
--          expense_authorised    true
--
-- Two lakh twenty-eight thousand rupees of a property's cost base, returned to a principal
-- the approved contract does not permit to read a report at all.
--
-- ── The corrected contract ───────────────────────────────────────────────────
--
--     reporting_ok(unit)  =  has_capability('reports.view', unit)
--                            AND (single-unit request OR unscoped reporting authority)
--
--     revenue_authorised  =  reporting_ok AND has_capability('revenue.view', unit)
--     expense_authorised  =  reporting_ok AND has_capability('expense.view.all', unit)
--
-- **Missing authority is never zero.** An unauthorised side comes back `null`, exactly as
-- before, so a principal without `reports.view` receives *no financial result at all* —
-- both sides null — and the client refuses. There is no combination of missing capabilities
-- that yields Revenue against Expenses of zero, or the reverse (D-163): a side is either a
-- summed figure or an absence, and `reports.view` removes both together.
--
-- `expense.view.own` is named nowhere and cannot qualify. Nothing branches on a role code.
--
-- ── Consolidated authority (D-164) ───────────────────────────────────────────
--
-- A request naming **more than one** business unit is a consolidated organisation report,
-- and requires the **unscoped** authority the approved rule names — all three capabilities
-- held without a business-unit scope. Two scoped grants do not silently add up to an
-- organisation-wide privilege.
--
-- A holder of two scoped grants keeps every per-property report their authority supports;
-- what they do not get is the organisation view. That is the canonical rule rather than a
-- reading of it, and the live matrix proves both halves.
--
-- ── Why this moved before Slice 7 ────────────────────────────────────────────
--
-- `reports.view` was on D-139's exemption list because *"the surface it governs does not
-- exist yet"*. Slice 5 built the first client-callable P&L surface, so that sentence stopped
-- being true the moment the RPC was granted to `authenticated`. The capability boundary
-- moves here, and only this much of it: Slice 7 still owns the comprehensive reporting
-- capability audit, the accumulated-state security acceptance, the `expense_sees_whole_org()`
-- dead-API review, and the export/print evaluators, none of which is touched.

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
  -- A consolidated organisation report needs unscoped authority, and a request naming more
  -- than one property is exactly that report (D-164).
  consolidated as (
    select (select count(*) from requested) > 1 as is_consolidated,
           public.has_unscoped_capability('reports.view')
             and public.has_unscoped_capability('revenue.view')
             and public.has_unscoped_capability('expense.view.all') as unscoped_ok
  ),
  authority as (
    select g.business_unit_id,
           g.reporting_ok                        as reports_authorised,
           g.reporting_ok and g.revenue_ok       as revenue_authorised,
           g.reporting_ok and g.expense_all_ok   as expense_authorised
      from (
        select r.business_unit_id,
               public.has_capability('reports.view', r.business_unit_id)
                 and (not c.is_consolidated or c.unscoped_ok)             as reporting_ok,
               public.has_capability('revenue.view', r.business_unit_id)  as revenue_ok,
               public.has_capability('expense.view.all', r.business_unit_id)
                                                                          as expense_all_ok
          from requested r cross join consolidated c
      ) g
  ),
  rev_rows as (
    select c.business_unit_id,
           c.revenue_category_id,
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
               'reports_authorised',  a.reports_authorised,
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

comment on function public.reporting_primitives(uuid[], date, date, boolean) is
  'Primitive canonical reporting sums for a named set of business units over one inclusive '
  'pnl_date range. security invoker over the two contribution projections, so it returns '
  'nothing the caller could not already select. Enforces D-164 in full: reports.view AND '
  'revenue.view AND expense.view.all per unit, unscoped authority for a consolidated '
  'request, expense.view.own never qualifying. An unauthorised side comes back null rather '
  'than zero. Derived P&L arithmetic is domain/finance''s (D-020, D-184, D-187).';

-- ── Invariants, restated in full over the replacement ────────────────────────
--
-- A `create or replace` is exactly where a `security definer`, a second statement or a lost
-- predicate gets in, and the earlier migrations' assertions ran against a body that no
-- longer exists (D-174).

do $inv$
declare
  v_secdef boolean;
  v_lang   text;
  v_vol    char;
  v_src    text;
  v_count  int;
begin
  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reporting_primitives';
  if v_count <> 1 then
    raise exception
      'there are % overloads of reporting_primitives; a superseded signature left callable '
      'is a second boundary nobody reviewed', v_count;
  end if;

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

  -- The corrective itself: all three capabilities, and the consolidated rule.
  if v_src !~ 'reports\.view' then
    raise exception
      'reporting_primitives does not require reports.view — the reporting authorization '
      'contract D-164 states is not enforced at the only client-callable P&L boundary';
  end if;
  if v_src !~ 'revenue\.view' or v_src !~ 'expense\.view\.all' then
    raise exception 'reporting_primitives lost a per-side capability gate (D-164)';
  end if;
  if v_src ~ 'expense\.view\.own' then
    raise exception 'reporting_primitives accepts expense.view.own for a P&L side';
  end if;
  if v_src !~ 'has_unscoped_capability' then
    raise exception
      'reporting_primitives does not require unscoped authority for a consolidated '
      'request, so two scoped grants would become an organisation-wide privilege (D-164)';
  end if;

  -- No role name decides anything (D-025, spec §13.1).
  if v_src ~* '\mowner\M' or v_src ~* '\mmanager\M' or v_src ~* '\maccountant\M'
     or v_src ~* '\mdata_entry\M' then
    raise exception 'reporting_primitives branches on a role name rather than a capability';
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

  -- D-186's property survives the security change: one pass per projection.
  if (length(v_src) - length(replace(v_src, 'from public.expense_period_contributions', '')))
       / length('from public.expense_period_contributions') <> 1 then
    raise exception 'the expense projection is scanned more than once';
  end if;
  if (length(v_src) - length(replace(v_src, 'from public.revenue_period_contributions', '')))
       / length('from public.revenue_period_contributions') <> 1 then
    raise exception 'the revenue projection is scanned more than once';
  end if;
end $inv$;

-- ── D-139, updated in the same corrective ────────────────────────────────────
--
-- `reports.view` now has an evaluator, so its exemption is a stale excuse and the line
-- goes. `reports.export`, `reports.print` and `settings.manage` stay: those surfaces are
-- Phase 7 and genuinely do not exist, which is the only thing the list is for.
--
-- The list is restated whole rather than amended, and the assertion below is the same one
-- `20260905141738` installed — it now runs against a catalogue in which `reports.view` must
-- be evaluated rather than excused.

do $$
declare
  v_dead text;
  v_unbuilt constant text[] := array[
    'reports.export',    -- Phase 7 · no export path exists
    'reports.print',     -- Phase 7 · no print path exists
    'settings.manage'];  -- no settings RPC exists
begin
  select string_agg(distinct rc.capability_code, ', ') into v_dead
    from public.role_capabilities rc
   where not (rc.capability_code = any(v_unbuilt))
     and not exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'app') and p.prokind = 'f'
              and pg_get_functiondef(p.oid) like '%' || rc.capability_code || '%')
     and not exists (
           select 1 from pg_policies pol
            where coalesce(pol.qual, '') like '%' || rc.capability_code || '%'
               or coalesce(pol.with_check, '') like '%' || rc.capability_code || '%');
  if v_dead is not null then
    raise exception
      'granted in production and evaluated nowhere: %. Either the check was never '
      'written or the grant was never meant (D-127 section 3)', v_dead;
  end if;

  -- And the list stays honest in the other direction.
  select string_agg(c, ', ') into v_dead
    from unnest(v_unbuilt) as c
   where exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'app') and p.prokind = 'f'
              and pg_get_functiondef(p.oid) like '%' || c || '%')
      or exists (
           select 1 from pg_policies pol
            where coalesce(pol.qual, '') like '%' || c || '%'
               or coalesce(pol.with_check, '') like '%' || c || '%');
  if v_dead is not null then
    raise exception
      'the not-yet-built exemption list names a capability that now HAS an evaluator: %. '
      'Delete the line — an excuse that has stopped being true is worse than no list',
      v_dead;
  end if;
end $$;

-- Stated positively as well, because the two assertions above would both pass if
-- `reports.view` were simply never granted to anybody.
do $inv$
begin
  if not exists (select 1 from public.role_capabilities
                  where capability_code = 'reports.view') then
    raise exception 'reports.view is granted to no role at all';
  end if;
  if not exists (
        select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'reporting_primitives'
           and p.prosrc like '%reports.view%') then
    raise exception
      'reports.view has no evaluator at the reporting boundary; the exemption was removed '
      'without the check being written, which is the D-139 defect in reverse';
  end if;
end $inv$;

-- The boundary is otherwise untouched: no new grant, no raw table access, anon nothing.
do $inv$
declare v_bad text;
begin
  if has_function_privilege('anon', 'public.reporting_primitives(uuid[], date, date, boolean)', 'EXECUTE') then
    raise exception 'anon can call the reporting boundary';
  end if;
  if not has_function_privilege('authenticated', 'public.reporting_primitives(uuid[], date, date, boolean)', 'EXECUTE') then
    raise exception 'the reporting boundary is not callable by an authenticated client';
  end if;
  if has_table_privilege('authenticated', 'public.expenses', 'SELECT')
     or has_table_privilege('authenticated', 'public.revenue_entries', 'SELECT')
     or has_table_privilege('authenticated', 'public.revenue_components', 'SELECT') then
    raise exception 'a client role can read a financial base table directly';
  end if;

  select string_agg(format('%s:%s:%s', grantee, table_name, privilege_type), ', ')
    into v_bad
    from information_schema.role_table_grants
   where table_schema = 'public'
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_bad is not null then
    raise exception 'a client role holds a write privilege in public: %', v_bad;
  end if;
end $inv$;
