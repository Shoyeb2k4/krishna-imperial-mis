-- Server migration ledger: 20260901132659  revenue_projection_security_barrier
--
-- One file per ledger version (A0). The previous Slice 4 commit collapsed seven
-- ledger versions into two files, which is not provenance.
--
-- The read boundary. `security_barrier`, not `security_invoker`: the view runs as its
-- owner and carries its OWN authorisation predicate, so the base tables stay ungranted
-- and the projection is the only way in. (security_invoker was tried first and failed for
-- every authorised user, because the caller holds no SELECT on revenue_entries — caught
-- by the live security test.)
drop view if exists public.revenue_component_detail;
drop view if exists public.revenue_document;

create view public.revenue_document
with (security_barrier = true) as
select
  e.id, e.org_id, e.txn_number, e.financial_year,
  e.business_unit_id, e.revenue_category_id,
  e.business_date, e.pnl_period_key, e.entry_kind,
  e.source_reference, e.notes, e.created_by, e.created_at, e.updated_at,
  e.voided_at, e.void_reason, e.row_version, e.change_seq,
  coalesce(t.gross_minor, 0)     as gross_amount_minor,
  coalesce(t.tax_minor, 0)       as tax_amount_minor,
  coalesce(t.net_minor, 0)       as net_amount_minor,
  coalesce(t.component_count, 0) as component_count
from public.revenue_entries e
left join lateral (
  select sum(c.gross_amount_minor) as gross_minor,
         sum(c.tax_amount_minor)   as tax_minor,
         sum(c.net_amount_minor)   as net_minor,
         count(*)                  as component_count
    from public.revenue_components c
   where c.revenue_entry_id = e.id
) t on true
where e.org_id = public.current_org_id()
  and public.has_capability('revenue.view.all', e.business_unit_id);

comment on view public.revenue_document is
  'The only revenue header a client reads. Totals are SUMS OF COMPONENTS, never a stored header value (D-078). Never grant SELECT on public.revenue_entries to a client role.';

create view public.revenue_component_detail
with (security_barrier = true) as
select c.* from public.revenue_components c
 where exists (
   select 1 from public.revenue_entries e
    where e.id = c.revenue_entry_id
      and e.org_id = public.current_org_id()
      and public.has_capability('revenue.view.all', e.business_unit_id)
 );

comment on view public.revenue_component_detail is
  'Components, visible only through an authorised parent document. One predicate, in one place.';

revoke all on public.revenue_document         from anon, public;
revoke all on public.revenue_component_detail from anon, public;
grant select on public.revenue_document         to authenticated;
grant select on public.revenue_component_detail to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
