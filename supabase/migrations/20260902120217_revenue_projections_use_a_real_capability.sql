-- The revenue read projections have never returned a row to anybody.
--
-- `revenue_document`, `revenue_component_detail` and the `revenue_entries` read policy all
-- gate on `has_capability('revenue.view.all', ...)`. **No such capability exists.** The
-- catalogue holds `revenue.view`; `revenue.view.all` is a name that was never granted to
-- any role, so the predicate is false for every caller including the Owner, and the only
-- sanctioned way to read revenue returns nothing at all.
--
-- This is the same mistake as the two D-110 records — a rule naming a capability nobody
-- holds — in three more places. It survived because the datasets were empty, and because
-- "the base tables are not the client API" passes trivially against a view that returns
-- nothing to anyone. It was found the first time a revenue entry existed to read back.
--
-- Corrected to `revenue.view`, which manager, accountant and owner hold. Access stays per
-- business unit and the base tables stay ungranted: the projection is still the only way
-- in. The generalised assertion at the foot is what makes another instance impossible —
-- and it earned that on its first run, by refusing this migration until the policy below
-- was fixed too.
--
-- The views are dropped rather than replaced, because `create or replace` cannot change a
-- column's type and the aggregate columns were `numeric`.

drop view if exists public.revenue_component_detail;
drop view if exists public.revenue_document;

create view public.revenue_document
with (security_barrier = true) as
select e.id, e.org_id, e.txn_number, e.financial_year,
       e.business_unit_id, e.revenue_category_id, e.business_date, e.pnl_period_key,
       e.entry_kind, e.source_reference, e.notes,
       e.created_by, e.created_at, e.updated_at,
       e.voided_at, e.void_reason, e.row_version, e.change_seq,
       coalesce(t.gross_minor, 0)::bigint as gross_amount_minor,
       coalesce(t.tax_minor, 0)::bigint   as tax_amount_minor,
       coalesce(t.net_minor, 0)::bigint   as net_amount_minor,
       coalesce(t.component_count, 0)     as component_count
  from public.revenue_entries e
  left join lateral (
    select sum(c.gross_amount_minor) as gross_minor,
           sum(c.tax_amount_minor)   as tax_minor,
           sum(c.net_amount_minor)   as net_minor,
           count(*)                  as component_count
      from public.revenue_components c
     where c.revenue_entry_id = e.id) t on true
 where e.org_id = public.current_org_id()
   and public.has_capability('revenue.view', e.business_unit_id);

create view public.revenue_component_detail
with (security_barrier = true) as
select c.id, c.org_id, c.revenue_entry_id,
       c.entered_amount_minor, c.entered_basis,
       c.gross_amount_minor, c.tax_amount_minor, c.net_amount_minor,
       c.tax_rule_id, c.tax_rate_bp, c.tax_treatment,
       c.value_band_id, c.value_band_label,
       c.value_band_floor_minor, c.value_band_ceiling_minor,
       c.supply_subtype_id, c.supply_subtype_label, c.premises_status_code
  from public.revenue_components c
  join public.revenue_entries e on e.id = c.revenue_entry_id
 where c.org_id = public.current_org_id()
   and public.has_capability('revenue.view', e.business_unit_id);

comment on view public.revenue_document is
  'The authorised read of a revenue entry, with its totals derived from its components. The base tables carry no client grant; this is the only way in.';

grant select on public.revenue_document to authenticated;
grant select on public.revenue_component_detail to authenticated;
revoke all on public.revenue_document from anon;
revoke all on public.revenue_component_detail from anon;

drop policy if exists revenue_entries_read on public.revenue_entries;
create policy revenue_entries_read on public.revenue_entries
  for select to authenticated
  using (
    org_id = (select public.current_org_id())
    and (select public.has_capability('revenue.view', business_unit_id))
  );

-- A capability nobody holds is a rule nobody can satisfy, and it fails silently rather
-- than loudly. Asserted generally now, so this class cannot reach another instance.
do $$
declare v_missing text;
begin
  select string_agg(distinct found.m[1], ', ') into v_missing
    from (
      select regexp_matches(pg_get_viewdef(c.oid, true),
                            'has_capability\(''([a-z._]+)''', 'g') as m
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'revenue%'
      union all
      select regexp_matches(coalesce(p.qual, ''),
                            'has_capability\(''([a-z._]+)''', 'g')
        from pg_policies p
       where p.schemaname = 'public'
         and (p.tablename like 'revenue%' or p.tablename = 'business_unit_tax_statuses')
    ) as found
   where not exists (
     select 1 from public.role_capabilities rc where rc.capability_code = found.m[1]);

  if v_missing is not null then
    raise exception
      'a revenue policy or projection requires a capability no role holds: %. It can never be satisfied, and it fails silently rather than loudly.',
      v_missing;
  end if;
end $$;
