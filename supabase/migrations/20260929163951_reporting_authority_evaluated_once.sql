-- Server migration ledger name: reporting_authority_evaluated_once
--
-- Phase 8 · D-318 R1 and R2, approved by the project lead (D-320). An optimisation of HOW
-- the existing authorisation is evaluated on the two reporting projections. It is not a
-- new authorisation model: every principal sees exactly the rows it saw before, which the
-- local harness proves by exact row-identity comparison against the previous definitions
-- (tool/perf/equivalence.sql).
--
-- ── R1 · the caller's authority is resolved once per statement ──────────────────────
--
-- `expense_period_contributions` evaluated `may_read_expense(p.expense_id)` once per row:
-- three nested SECURITY DEFINER calls (~0.335 ms a row on krishna-mis-dev), on voided
-- rows, on unrequested properties and on the whole history for a delta (D-318). The rule
-- `may_read_expense` states is unchanged and is restated here verbatim in set form:
--
--   may_read_expense(d) ⟺ d.org_id = current_org_id()
--                          ∧ ( ∃ line of d in a property where
--                                has_capability('expense.view.all', property)
--                            ∨ ( d.created_by = auth.uid()
--                                ∧ ∃ line of d in a property where
--                                    has_capability('expense.view.own', property) ) )
--
-- The two property sets are computed ONCE, by `has_capability` itself, over every row of
-- `business_units`, as scalar InitPlans (`= any((select array_agg …))`). Equivalence rests
-- on one fact, which the schema enforces: every allocation's and every revenue entry's
-- business unit is a `business_units` row (the composite FK ladder, D-040:
-- expense_categories → sections → departments → business_units; revenue_categories →
-- business_units). For such a unit, `unit = any(set)` is true exactly when
-- `has_capability(cap, unit)` is. `array_agg` over no rows is NULL and `x = any(NULL)` is
-- NULL, which a WHERE treats as false — the same answer `has_capability` gives.
--
-- `current_org_id()` and `auth.uid()` become InitPlans too: the same value, evaluated once.
-- `may_read_expense` itself is untouched and still guards every single-document path (the
-- RLS policies, attachments, Storage, the expense RPCs).
--
-- The revenue projection gets the same treatment for its per-row
-- `has_capability('revenue.view', e.business_unit_id)`.
--
-- `expense_period_contributions` gains one trailing column, `document_change_seq`
-- (= expenses.change_seq): the document's own generation, which the paged reporting
-- transport orders by (D-320). The existing columns, their order and types are unchanged,
-- so `create or replace view` keeps every grant.
--
-- ── R2 · a report scans only the properties it asked for and may see ────────────────
--
-- `reporting_primitives` applied the requested property through a join to its `authority`
-- CTE, so a Crystal-Canopy-only report authorised Hotel Krishna's rows and threw them
-- away, and a refused consolidated request still scanned everything. The authorised,
-- requested units are now also a scan predicate on each projection, so a report touches
-- only rows it may return and an empty authorised set scans nothing. The join stays: the
-- predicate narrows, it never widens. Nothing else in the function changes.

begin;

create or replace view public.expense_period_contributions
  with (security_barrier = true) as
select p.id,
       p.org_id,
       p.expense_id,
       p.allocation_id,
       p.business_unit_id,
       a.department_id,
       a.section_id,
       a.category_id,
       p.accounting_period_start,
       p.accounting_period_end,
       p.pnl_date,
       p.pnl_period_key,
       p.amount_minor,
       p.is_derived,
       e.business_date,
       e.payment_status,
       e.payment_date,
       e.vendor_id,
       e.voided_at,
       greatest(e.change_seq, a.change_seq, p.change_seq) as change_seq,
       e.txn_number,
       e.change_seq as document_change_seq
  from public.expense_period_allocations p
  join public.expense_allocations a on a.id = p.allocation_id
  join public.expenses e on e.id = p.expense_id
 where p.org_id = (select public.current_org_id())
   and p.business_unit_id in (select public.expense_visible_units())
   and e.org_id = (select public.current_org_id())
   and (
     exists (
       select 1 from public.expense_allocations x
        where x.expense_id = e.id
          and x.business_unit_id = any ((
            select array_agg(bu.id) from public.business_units bu
             where public.has_capability('expense.view.all', bu.id))::uuid[]))
     or (e.created_by = (select auth.uid())
         and exists (
           select 1 from public.expense_allocations x
            where x.expense_id = e.id
              and x.business_unit_id = any ((
                select array_agg(bu.id) from public.business_units bu
                 where public.has_capability('expense.view.own', bu.id))::uuid[])))
   );

create or replace view public.revenue_period_contributions
  with (security_barrier = true) as
select c.id,
       c.org_id,
       c.revenue_entry_id,
       e.business_unit_id,
       e.revenue_category_id,
       c.supply_subtype_id,
       c.value_band_id,
       c.value_band_floor_minor as value_band_min_minor,
       c.value_band_ceiling_minor as value_band_max_minor,
       c.premises_status_code,
       e.business_date,
       e.business_date as pnl_date,
       e.pnl_period_key,
       c.gross_amount_minor as gross_minor,
       c.tax_amount_minor as tax_minor,
       c.net_amount_minor as net_minor,
       c.tax_rule_id,
       c.tax_rate_bp,
       c.tax_treatment,
       c.entered_basis,
       e.entry_kind,
       e.txn_number,
       e.business_date_source,
       e.voided_at,
       e.change_seq
  from public.revenue_components c
  join public.revenue_entries e on e.id = c.revenue_entry_id
 where e.org_id = (select public.current_org_id())
   and e.business_unit_id = any ((
     select array_agg(bu.id) from public.business_units bu
      where public.has_capability('revenue.view', bu.id))::uuid[]);

create or replace function public.reporting_primitives(
  p_business_unit_ids uuid[],
  p_from date,
  p_to date,
  p_breakdown boolean default false
) returns jsonb
language sql
stable
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
     where c.business_unit_id = any (array(
             select a2.business_unit_id from authority a2 where a2.revenue_authorised))
       and c.voided_at is null
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
     where p.business_unit_id = any (array(
             select a2.business_unit_id from authority a2 where a2.expense_authorised))
       and p.voided_at is null
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
    -- The server's own transaction time, from this same statement (D-188).
    'server_time', now(),
    'units', coalesce((
      select jsonb_agg(jsonb_build_object(
               'business_unit_id',    a.business_unit_id,
               'reports_authorised',  a.reports_authorised,
               'revenue_authorised',  a.revenue_authorised,
               'expense_authorised',  a.expense_authorised,
               -- null, never zero, for a side this caller may not read (D-163).
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

-- ── Invariants ─────────────────────────────────────────────────────────────────────
do $inv$
declare
  v_def text;
begin
  -- Both projections stay security-barrier views run as their owner, never invoker views.
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in ('expense_period_contributions', 'revenue_period_contributions')
       and (c.reloptions is null
            or not ('security_barrier=true' = any(c.reloptions))
            or 'security_invoker=true' = any(c.reloptions))) then
    raise exception 'a reporting projection lost security_barrier or became an invoker view';
  end if;

  -- The authority each projection applies is still the capability model, by name.
  v_def := pg_get_viewdef('public.expense_period_contributions'::regclass, true);
  if position('expense_visible_units()' in v_def) = 0
     or position('''expense.view.all''' in v_def) = 0
     or position('''expense.view.own''' in v_def) = 0
     or position('auth.uid()' in v_def) = 0
     or position('current_org_id()' in v_def) = 0 then
    raise exception 'expense_period_contributions no longer states the D-169 rule';
  end if;
  if v_def ~* '\m(owner|manager|accountant|data_entry)\M' then
    raise exception 'expense_period_contributions branches on a role name';
  end if;

  v_def := pg_get_viewdef('public.revenue_period_contributions'::regclass, true);
  if position('''revenue.view''' in v_def) = 0
     or position('current_org_id()' in v_def) = 0 then
    raise exception 'revenue_period_contributions no longer states its authority';
  end if;

  -- reporting_primitives: still SECURITY INVOKER, still one SQL statement, still the D-164
  -- intersection (D-184, D-187).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'reporting_primitives'
                and (p.prosecdef
                     or p.prolang <> (select oid from pg_language where lanname = 'sql'))) then
    raise exception 'reporting_primitives must stay a SECURITY INVOKER SQL function';
  end if;
  select p.prosrc into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reporting_primitives';
  if position('''reports.view''' in v_def) = 0
     or position('''revenue.view''' in v_def) = 0
     or position('''expense.view.all''' in v_def) = 0 then
    raise exception 'reporting_primitives lost part of the D-164 intersection';
  end if;
end $inv$;

commit;
