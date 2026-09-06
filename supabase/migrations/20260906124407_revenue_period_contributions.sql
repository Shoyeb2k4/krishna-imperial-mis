-- Phase 4 Slice 12 - revenue reporting contributions (D-087)
-- Derived, not stored. Full reasoning in ARCHITECTURE section 26 and D-157.

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
  e.voided_at
from public.revenue_components c
join public.revenue_entries e on e.id = c.revenue_entry_id
where e.org_id = public.current_org_id()
  and public.has_capability('revenue.view', e.business_unit_id);

comment on view public.revenue_period_contributions is
  'The canonical source for revenue profitability: one row per component, already scoped '
  'by the caller''s revenue.view grants. Derived from the accepted component snapshots '
  'rather than stored, so a business-date correction moves a period and a void removes an '
  'effect with nothing to maintain and nothing to drift. Voided documents carry voided_at '
  'and must be excluded by every aggregate; they stay visible to audit.';

revoke all on public.revenue_period_contributions from anon, public;
grant select on public.revenue_period_contributions to authenticated;

-- Reporting reads period, then property, then category, and never voided rows.
create index if not exists revenue_entries_reporting_idx
  on public.revenue_entries (org_id, pnl_period_key, business_unit_id, revenue_category_id)
  where voided_at is null;

-- ── Invariants ───────────────────────────────────────────────────────────────

-- There is exactly one revenue reporting source, and it is not writable.
do $inv$
begin
  if exists (select 1 from information_schema.tables
              where table_schema = 'public'
                and table_name = 'revenue_period_contributions'
                and table_type = 'BASE TABLE') then
    raise exception
      'revenue_period_contributions is a table - a stored copy of facts the components '
      'already carry is a second financial truth source (D-157)';
  end if;

  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'revenue_period_contributions'
                    and c.relkind = 'v'
                    and array_to_string(c.reloptions, ',') like '%security_barrier=true%') then
    raise exception
      'the revenue contribution projection is not a security_barrier view, so its '
      'predicate can be outrun by a cheaper user-supplied one';
  end if;
end $inv$;

-- No client role may read the base tables. The projection is the only way in, exactly as
-- it is for revenue_document and for expenses (D-062).
do $inv$
declare v_bad text;
begin
  select string_agg(t, ', ') into v_bad
    from unnest(array['revenue_entries', 'revenue_components']) as t
   where has_table_privilege('authenticated', 'public.' || t, 'SELECT');
  if v_bad is not null then
    raise exception 'authenticated can read a revenue base table directly: %', v_bad;
  end if;
end $inv$;

-- The capability the projection names must actually be held by some role. D-116 shipped
-- three rules requiring a capability nobody had, and they refused everybody silently.
do $inv$
declare v_missing text;
begin
  select string_agg(distinct m[1], ', ') into v_missing
    from (select regexp_matches(pg_get_viewdef('public.revenue_period_contributions'::regclass, true),
                                'has_capability\(''([a-z._]+)''', 'g') as m) f
   where not exists (select 1 from public.role_capabilities rc
                      where rc.capability_code = f.m[1]);
  if v_missing is not null then
    raise exception
      'the revenue contribution projection requires a capability no role holds: %',
      v_missing;
  end if;
end $inv$;

-- Every contribution reconciles, and every document reconciles to its contributions.
-- Asserted over the live rows rather than argued: this is the property Phase 5 will sum.
do $inv$
declare v_bad bigint;
begin
  select count(*) into v_bad
    from public.revenue_components
   where net_amount_minor <> gross_amount_minor - tax_amount_minor;
  if v_bad > 0 then
    raise exception 'a revenue component does not reconcile: % row(s)', v_bad;
  end if;

  select count(*) into v_bad
    from public.revenue_entries e
    join lateral (select coalesce(sum(c.gross_amount_minor), 0) as g,
                         coalesce(sum(c.tax_amount_minor), 0)   as t,
                         coalesce(sum(c.net_amount_minor), 0)   as n
                    from public.revenue_components c
                   where c.revenue_entry_id = e.id) s on true
   where s.n <> s.g - s.t;
  if v_bad > 0 then
    raise exception
      'a revenue document does not reconcile to the sum of its components: % row(s)',
      v_bad;
  end if;

  -- And the period key a contribution reports is the one the business date implies. The
  -- table CHECK already says so; this asserts it has never been bypassed by a write path
  -- that predates it.
  select count(*) into v_bad
    from public.revenue_entries
   where pnl_period_key is distinct from to_char(business_date, 'YYYY-MM');
  if v_bad > 0 then
    raise exception
      'a revenue entry reports a period its business date does not imply: % row(s)',
      v_bad;
  end if;
end $inv$;
