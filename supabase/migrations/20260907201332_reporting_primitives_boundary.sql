-- Phase 5 Slice 5 · the authoritative server reporting boundary.
--
-- One function that returns the **primitive canonical sums** a P&L is built from, for a
-- named set of business units over one inclusive P&L-date range. It is the authoritative
-- comparison point the D-020 parity suite measures the offline cache against.
--
-- ── What it deliberately is not ──────────────────────────────────────────────
--
-- It is **not a second financial truth source**. It re-runs no tax rule, reads no rate,
-- derives no business date, reinterprets no accounting period, and computes no Net Sales,
-- Operating Profit or margin. Those live once, in `domain/finance`, and both engines feed
-- them from here (spec §21.1, §21.2, D-020). What it returns is what an engine is allowed
-- to return: summed integer paise and the counts behind them.
--
-- It therefore also needs **no tax configuration to answer a historical P&L**. Every figure
-- is the snapshot the component recorded when the server accepted it, so deleting every
-- rule in the organisation leaves a past month's report unchanged (D-080, D-122).
--
-- ── Authorization: what this adds, which is nothing ──────────────────────────
--
-- `security invoker`. It runs with the **caller's** privileges, over the two
-- `security_barrier` projections and nothing else, so every predicate that already governs
-- a reporting read governs this: `current_org_id()`, `has_capability('revenue.view', unit)`
-- on one side, `expense_visible_units()` plus `may_read_expense()` on the other. Anything
-- it can return, the caller could already have selected row by row and added up.
--
-- That is the whole reason it is safe to expose in Slice 5, and an invariant below asserts
-- it: `prosecdef = false`, and no financial base table named in the body. A
-- `security definer` version would have run as the owner and handed one property's figures
-- to the other property's manager.
--
-- **It enforces D-164's data half now** — `revenue.view` for the revenue side,
-- `expense.view.all` for the expense side, per property, and `expense.view.own` never
-- qualifies. An unauthorised side comes back **null**, never zero, so a Data Entry user
-- holding own-only expense visibility and no revenue grant cannot receive a plausible
-- looking P&L assembled from their own costs and a revenue side of nothing. The client maps
-- null to an unavailable side and the report is refused (D-163).
--
-- What it does **not** enforce is `reports.view`, which today has no evaluator anywhere and
-- is on D-139's exemption list. That is Slice 7's, deliberately: adding a third gate here
-- would move the reporting capability boundary forward inside a parity slice, and the
-- absence of that gate creates no exposure, because the function is incapable of returning
-- a row its caller could not already read.
--
-- ── One snapshot (§4) ────────────────────────────────────────────────────────
--
-- Revenue and expenses are read in **one SQL statement**, so under Postgres MVCC both sides
-- come from one snapshot. That is what excludes the dangerous shape the brief names — read
-- revenue, let a transaction commit, read expenses, and call the pair one P&L — and it is
-- excluded structurally rather than by care: the invariant below refuses a body containing
-- more than one statement, and refuses a `plpgsql` rewrite, where two statements under READ
-- COMMITTED would take two snapshots.
--
-- ── Dates ────────────────────────────────────────────────────────────────────
--
-- `pnl_date`, on both sides, always. Never `captured_at`, `created_at`, `payment_date` or
-- any device clock. For revenue that is the canonical business date under the property's
-- cut-off (D-019, D-067); for an expense it is the accrual attribution, so a June salary
-- paid on 5 July is a June cost (D-016, spec §5.3). One inclusive range serves every period
-- the client can ask for — a day, a Monday-to-Sunday week, a month, a financial year, a
-- custom range — because normalisation happens once, in `domain/finance`, and arrives here
-- as two dates (§10).
--
-- ── Scope ────────────────────────────────────────────────────────────────────
--
-- The unit set is explicit and there is no branch in which null or empty means "the whole
-- organisation": `unnest(coalesce(p_business_unit_ids, '{}'))` over an empty array yields
-- no units, and the client refuses a report over no permitted property. Accidental whole-org
-- expansion from an omitted id is structurally unavailable rather than guarded against (§11).

-- ── 1 · The expense projection states canonical acceptance ───────────────────
--
-- Recreated to carry `txn_number`, so the canonical rule D-168 settled — accepted, not
-- voided — is expressed on the server in the same words it is expressed in on the client,
-- rather than resting on the observation that the server happens to number every document
-- it accepts. Every other column, the generation and all three scope predicates are
-- unchanged, and the invariants at the foot of this file re-assert them.
--
-- It is **appended**, after `change_seq`, and not put beside `voided_at` where it reads
-- better. `create or replace view` may add columns only at the end — inserting one renames
-- every column after it, which Postgres refuses outright — and the alternative, dropping and
-- recreating the view, would drop its grants and its `security_barrier` setting for the
-- length of a transaction on a relation that is the only way a client reads expense
-- reporting at all. Position is cosmetic; the grant boundary is not.

create or replace view public.expense_period_contributions
with (security_barrier = true) as
select
  p.id,
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
  -- greatest() over the three rows that can carry a reporting change, because the parent
  -- alone understates the document's true generation (D-177).
  greatest(e.change_seq, a.change_seq, p.change_seq) as change_seq,
  -- Appended, for the reason in the header: a replaced view may only grow at the end.
  e.txn_number
from public.expense_period_allocations p
join public.expense_allocations a on a.id = p.allocation_id
join public.expenses e on e.id = p.expense_id
where p.org_id = public.current_org_id()
  and p.business_unit_id in (select public.expense_visible_units())
  and public.may_read_expense(p.expense_id);

comment on view public.expense_period_contributions is
  'The canonical source for profitability. One row per allocation line per accounting '
  'period, already scoped by the underlying policies and, since D-169, by document '
  'authorship where the caller holds only expense.view.own. Voided documents carry '
  'voided_at and are excluded by every aggregate; they stay visible to audit. txn_number '
  'is the server-issued acceptance marker a canonical total requires (D-168). change_seq '
  'is the effective document generation — the greatest of the header, line and period rows '
  '— which a reporting delta filters on (D-177).';

revoke all on public.expense_period_contributions from anon, public;
grant select on public.expense_period_contributions to authenticated;

-- ── 2 · The aggregation core ─────────────────────────────────────────────────

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
  rev as (
    select c.business_unit_id,
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
     group by c.business_unit_id
  ),
  exp as (
    select p.business_unit_id,
           sum(p.amount_minor)::bigint as amount_minor,
           count(*)::bigint            as contributions
      from public.expense_period_contributions p
      join authority a
        on a.business_unit_id = p.business_unit_id and a.expense_authorised
     where p.voided_at is null
       and p.txn_number is not null
       and p.pnl_date >= p_from
       and p.pnl_date <= p_to
     group by p.business_unit_id
  ),
  rev_cat_rows as (
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
     where p_breakdown
       and c.voided_at is null
       and c.txn_number is not null
       and c.pnl_date >= p_from
       and c.pnl_date <= p_to
     group by c.business_unit_id, c.revenue_category_id
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
      from rev_cat_rows r
     group by r.business_unit_id
  ),
  exp_cat_rows as (
    select p.business_unit_id,
           p.department_id,
           p.section_id,
           p.category_id,
           sum(p.amount_minor)::bigint as amount_minor,
           count(*)::bigint            as contributions
      from public.expense_period_contributions p
      join authority a
        on a.business_unit_id = p.business_unit_id and a.expense_authorised
     where p_breakdown
       and p.voided_at is null
       and p.txn_number is not null
       and p.pnl_date >= p_from
       and p.pnl_date <= p_to
     group by p.business_unit_id, p.department_id, p.section_id, p.category_id
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
      from exp_cat_rows e
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
               'revenue_by_category', case when a.revenue_authorised
                   then coalesce(rc.lines, '[]'::jsonb) else '[]'::jsonb end,
               'expense_by_hierarchy', case when a.expense_authorised
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
  'nothing the caller could not already select; an unauthorised side comes back null rather '
  'than zero. Derived P&L arithmetic is domain/finance''s and is not computed here (D-020, '
  'D-184).';

revoke all on function public.reporting_primitives(uuid[], date, date, boolean)
  from public, anon;
grant execute on function public.reporting_primitives(uuid[], date, date, boolean)
  to authenticated;

-- ── Invariants ───────────────────────────────────────────────────────────────

-- The function cannot see more than its caller, and reads only the projections.
do $inv$
declare
  v_secdef boolean;
  v_lang   text;
  v_vol    char;
  v_src    text;
  v_kind   char;
begin
  select p.prosecdef, l.lanname, p.provolatile, p.prosrc, p.prokind
    into v_secdef, v_lang, v_vol, v_src, v_kind
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
   where n.nspname = 'public' and p.proname = 'reporting_primitives';

  if v_secdef then
    raise exception
      'reporting_primitives is security definer: it would read the projections as the '
      'owner and hand one property''s figures to another property''s manager';
  end if;
  if v_vol <> 's' then
    raise exception 'reporting_primitives is not stable; a reporting read writes nothing';
  end if;
  if v_kind <> 'f' then
    raise exception 'reporting_primitives is not a plain function';
  end if;

  -- One statement, so both sides come from one snapshot under MVCC. A plpgsql body, or a
  -- sql body with two statements, would read revenue and expenses at two snapshots under
  -- READ COMMITTED and could return a pair that never existed together.
  if v_lang <> 'sql' then
    raise exception
      'reporting_primitives is % rather than sql: one snapshot across both sides is a '
      'property of it being a single statement', v_lang;
  end if;
  if (length(regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g'))
      - length(replace(regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g'), ';', ''))) > 1 then
    raise exception
      'reporting_primitives contains more than one statement; revenue and expenses would '
      'then be read at two snapshots';
  end if;

  -- The body names the two projections and no financial base table. A base-table read
  -- inside a security invoker function would simply fail (no client role may select one),
  -- but the assertion states the boundary rather than relying on the failure.
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

  -- D-164's data half, enforced now. expense.view.own must never qualify a P&L side,
  -- because a subset of one author's costs is not the property's cost base.
  if v_src !~ 'revenue\.view' or v_src !~ 'expense\.view\.all' then
    raise exception
      'reporting_primitives does not gate its two sides on revenue.view and '
      'expense.view.all per business unit (D-164)';
  end if;
  if v_src ~ 'expense\.view\.own' then
    raise exception 'reporting_primitives accepts expense.view.own for a P&L side';
  end if;

  -- pnl_date on both sides, and no other date basis anywhere.
  if v_src !~ 'pnl_date' then
    raise exception 'reporting_primitives does not filter on pnl_date';
  end if;
  if v_src ~ '\mcaptured_at\M' or v_src ~ '\mpayment_date\M'
     or v_src ~ '\mcreated_at\M' or v_src ~ '\mbusiness_date\M' then
    raise exception
      'reporting_primitives filters on a date basis other than pnl_date (spec §5.3)';
  end if;

  -- No re-rating, and no floating point. A rate in this body could turn a stored tax sum
  -- back into an arithmetic one, which is the paisa-a-day defect.
  if v_src ~ '\mtax_rate_bp\M' or v_src ~ '\mrate_bp\M'
     or v_src ~ '\mtax_rule_id\M' or v_src ~ 'revenue_tax_rates' then
    raise exception 'reporting_primitives reaches for tax configuration';
  end if;
  if v_src ~* '\mfloat\M' or v_src ~* '\mreal\M' or v_src ~* 'double precision' then
    raise exception 'reporting_primitives uses binary floating point on money';
  end if;

  -- No branch in which an omitted or empty unit set means the whole organisation.
  if v_src !~ 'coalesce\(p_business_unit_ids' then
    raise exception
      'reporting_primitives does not force an omitted unit set to empty; a null argument '
      'could then widen a report to the whole organisation (§11)';
  end if;
end $inv$;

-- The projection rewrite kept its generation and all three scope predicates.
do $inv$
declare v_exp text := pg_get_viewdef('public.expense_period_contributions'::regclass, true);
begin
  if v_exp not like '%GREATEST(e.change_seq, a.change_seq, p.change_seq)%' then
    raise exception 'the expense projection lost its effective document generation (D-177)';
  end if;
  if v_exp not like '%expense_visible_units()%' or v_exp not like '%may_read_expense(%'
     or v_exp not like '%current_org_id()%' then
    raise exception 'the expense projection lost a scope predicate';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public'
                    and table_name = 'expense_period_contributions'
                    and column_name = 'txn_number') then
    raise exception 'the expense projection does not expose the acceptance marker';
  end if;
end $inv$;

-- Every returned money figure is an exact integer. jsonb carries no float, and the sums
-- are cast to bigint rather than left as the numeric `sum()` returns, so nothing downstream
-- has to decide what an unbounded decimal means in paise (§32).
do $inv$
declare v_src text;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reporting_primitives';
  if (length(v_src) - length(replace(v_src, '::bigint', ''))) / length('::bigint') < 8 then
    raise exception
      'a reporting sum is not cast to bigint; sum(bigint) returns numeric and a report '
      'would carry an unbounded decimal where paise belong';
  end if;
end $inv$;

-- The boundary is unchanged: base tables ungranted, projections readable, anon nothing,
-- and the new function callable by exactly one client role.
do $inv$
begin
  if has_table_privilege('authenticated', 'public.expenses', 'SELECT')
     or has_table_privilege('authenticated', 'public.revenue_entries', 'SELECT')
     or has_table_privilege('authenticated', 'public.revenue_components', 'SELECT') then
    raise exception 'a client role can read a financial base table directly';
  end if;
  if not has_table_privilege('authenticated', 'public.expense_period_contributions', 'SELECT')
     or not has_table_privilege('authenticated', 'public.revenue_period_contributions', 'SELECT') then
    raise exception 'a client can no longer read a reporting projection';
  end if;
  if has_table_privilege('anon', 'public.expense_period_contributions', 'SELECT') then
    raise exception 'anon can read financial data';
  end if;
  if has_function_privilege('anon', 'public.reporting_primitives(uuid[], date, date, boolean)', 'EXECUTE') then
    raise exception 'anon can call the reporting boundary';
  end if;
  if not has_function_privilege('authenticated', 'public.reporting_primitives(uuid[], date, date, boolean)', 'EXECUTE') then
    raise exception 'the reporting boundary is not callable by an authenticated client';
  end if;
end $inv$;

-- No client role gained any write privilege on any financial relation (§35, D-162).
do $inv$
declare v_bad text;
begin
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
