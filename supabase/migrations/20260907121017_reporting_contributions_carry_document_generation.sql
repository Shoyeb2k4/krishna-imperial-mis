-- Phase 5 Slice 4 · the reporting delta surface.
--
-- The narrowest thing that lets a device synchronise canonical reporting facts: the two
-- contribution projections gain the **effective document generation**, so a client can ask
-- `where change_seq > :since` and get every contribution of every document that has changed.
--
-- No new relation, no new RPC, and no new grant. The projections already carry the RLS a
-- reporting read needs — `may_read_expense` plus `expense_visible_units` on one side,
-- `has_capability('revenue.view', unit)` on the other — so the delta inherits exactly the
-- visibility the detail reads have, and Slice 7 tightens both at once when `reports.view`
-- acquires its evaluator. A bespoke delta RPC would have been a second place for that
-- boundary to live.
--
-- ── The effective document generation (D-177) ────────────────────────────────
--
--   Revenue:  revenue_entries.change_seq
--             Components carry no generation, and only `revenue_create` and
--             `revenue_update` write them — both of which write the entry, which since the
--             D-172 corrective stamps on every update.
--
--   Expense:  greatest(expenses.change_seq,
--                      expense_allocations.change_seq,
--                      expense_period_allocations.change_seq)
--             The parent always advances, so it alone would *detect* every change; but a
--             child can carry a higher generation than its own parent, because the header
--             is written before the lines are replaced (13004 < 13006 < 13008 in the
--             audit). Taking the maximum keeps the watermark from claiming a document is
--             older than it is.
--
-- ── Why the client still needs a safety overlap ──────────────────────────────
--
-- A sequence value is allocated when a row is written and becomes visible only when its
-- transaction commits, so a naive `> max(seen)` can step over a transaction that committed
-- late (ARCHITECTURE §5.2). Nothing here can fix that on the server; the mitigation is the
-- documented one and belongs to the client: re-request an overlap below the watermark and
-- apply idempotently by document identity. Stated here so the next reader of this view does
-- not conclude the generation alone is sufficient.

create or replace view public.revenue_period_contributions
with (security_barrier = true) as
select
  c.id,
  c.org_id,
  c.revenue_entry_id,
  e.business_unit_id,
  e.revenue_category_id,
  c.supply_subtype_id,
  c.value_band_id,
  c.value_band_floor_minor   as value_band_min_minor,
  c.value_band_ceiling_minor as value_band_max_minor,
  c.premises_status_code,
  e.business_date,
  e.business_date            as pnl_date,
  e.pnl_period_key,
  c.gross_amount_minor       as gross_minor,
  c.tax_amount_minor         as tax_minor,
  c.net_amount_minor         as net_minor,
  c.tax_rule_id,
  c.tax_rate_bp,
  c.tax_treatment,
  c.entered_basis,
  e.entry_kind,
  e.txn_number,
  e.business_date_source,
  e.voided_at,
  -- The effective document generation. A client filters on this and replaces the whole
  -- contribution set of every document it comes back for.
  e.change_seq
from public.revenue_components c
join public.revenue_entries e on e.id = c.revenue_entry_id
where e.org_id = public.current_org_id()
  and public.has_capability('revenue.view', e.business_unit_id);

comment on view public.revenue_period_contributions is
  'The canonical source for revenue profitability: one row per component, already scoped '
  'by the caller''s revenue.view grants. Derived from the accepted component snapshots '
  'rather than stored, so a business-date correction moves a period and a void removes an '
  'effect with nothing to maintain and nothing to drift. Voided documents carry voided_at '
  'and must be excluded by every aggregate; they stay visible to audit. change_seq is the '
  'document generation a reporting delta filters on (D-177).';

revoke all on public.revenue_period_contributions from anon, public;
grant select on public.revenue_period_contributions to authenticated;

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
  greatest(e.change_seq, a.change_seq, p.change_seq) as change_seq
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
  'voided_at and are excluded by every aggregate; they stay visible to audit. change_seq '
  'is the effective document generation — the greatest of the header, line and period rows '
  '— which a reporting delta filters on (D-177).';

revoke all on public.expense_period_contributions from anon, public;
grant select on public.expense_period_contributions to authenticated;

-- ── Invariants ───────────────────────────────────────────────────────────────

-- Both projections expose a generation, or a delta cannot be expressed at all.
do $inv$
declare v_missing text;
begin
  select string_agg(v, ', ') into v_missing
    from unnest(array['revenue_period_contributions', 'expense_period_contributions']) as v
   where not exists (
     select 1 from information_schema.columns
      where table_schema = 'public' and table_name = v and column_name = 'change_seq');
  if v_missing is not null then
    raise exception 'a reporting projection exposes no document generation: %', v_missing;
  end if;
end $inv$;

-- The expense generation is the greatest of the three, not the header alone. A view that
-- selected `e.change_seq` would satisfy the check above and still understate every
-- document whose lines were replaced.
do $inv$
begin
  if pg_get_viewdef('public.expense_period_contributions'::regclass, true)
       not like '%GREATEST(e.change_seq, a.change_seq, p.change_seq)%' then
    raise exception
      'the expense projection does not take the greatest generation across header, line '
      'and period rows, so a replaced line can report a generation older than it is';
  end if;
end $inv$;

-- The boundary is unchanged: base tables ungranted, projections readable, anon nothing.
do $inv$
begin
  if has_table_privilege('authenticated', 'public.expenses', 'SELECT')
     or has_table_privilege('authenticated', 'public.revenue_entries', 'SELECT')
     or has_table_privilege('authenticated', 'public.revenue_components', 'SELECT') then
    raise exception 'a client role can read a financial base table directly';
  end if;
  if not has_table_privilege('authenticated', 'public.revenue_period_contributions', 'SELECT')
     or not has_table_privilege('authenticated', 'public.expense_period_contributions', 'SELECT') then
    raise exception 'a client can no longer read a reporting projection';
  end if;
  if has_table_privilege('anon', 'public.revenue_period_contributions', 'SELECT')
     or has_table_privilege('anon', 'public.expense_period_contributions', 'SELECT') then
    raise exception 'anon can read financial data';
  end if;
end $inv$;

-- And the scope predicates survived the rewrite. A projection that dropped its own
-- authority clause would pass every check above and hand one property's figures to the
-- other property's manager.
do $inv$
declare v_rev text := pg_get_viewdef('public.revenue_period_contributions'::regclass, true);
        v_exp text := pg_get_viewdef('public.expense_period_contributions'::regclass, true);
begin
  if v_rev not like '%has_capability(''revenue.view''%' then
    raise exception 'the revenue projection lost its scope predicate';
  end if;
  if v_exp not like '%expense_visible_units()%' or v_exp not like '%may_read_expense(%' then
    raise exception 'the expense projection lost a scope predicate';
  end if;
  if v_rev not like '%current_org_id()%' or v_exp not like '%current_org_id()%' then
    raise exception 'a projection lost its organisation predicate';
  end if;
end $inv$;