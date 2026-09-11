-- Server migration ledger name: owner_ledger_snapshot_requires_settlement_view
--
-- Phase 5 OA-3 · the settlement transport is closed to anybody who may not read a
-- settlement, and it now carries the settlement start date.
--
-- The header names no ledger version (D-203); `LEDGER.md` maps it.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- The defect, proven RED against the shipped function before this file was written
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Signed in as the development Accountant — who holds `owner_ledger.view` and, by the
-- project lead's OA-3 ruling, must have **no** owner settlement access — the OA-2
-- `owner_ledger_snapshot()` returned:
--
--     movements          159
--     owners               3
--     ownership_shares    34      <- the profit ratio a settlement allocates by
--     family_members       2
--
-- That is the whole of a settlement's input, handed to a principal the settlement is
-- closed to. OA-2 made it `security invoker` so that it grants no *new data access*, and
-- that remains true: every row it returns, the caller could already select under
-- `owner_ledger.view`. But it is the transport the settlement surface certifies
-- completeness from, and a settlement surface a capability does not gate on the server is a
-- button hidden in the client — which `CLAUDE.md` says is not security (D-187's lesson,
-- applied one domain over).
--
-- ═════════════════════════════════════════════════════════════════════════════
-- The contract now
-- ═════════════════════════════════════════════════════════════════════════════
--
--     settlement_authorised = owner_settlement.view
--                             AND owner_ledger.view
--                             AND reports.view                  (each held anywhere)
--
-- When false, every dataset and the start date come back **null** — never an empty array
-- and never zero. An empty array would be certified by the client as "complete history
-- with no movements", which is exactly a missing side replaced with zero (D-163).
--
-- `owner_ledger.view` is required as well as the settlement capability because RLS is
-- what returns the rows: a settlement holder who could not read the ledger would receive
-- empty arrays and a device would certify them as complete. `reports.view` is D-197's
-- intersection — the statement is a report, and reporting is its own privilege.
--
-- **The distinction the project lead asked to be preserved.** Authorisation to see a
-- settlement is not authorisation to read the underlying financial data, and neither
-- implies the other. This gates the *settlement transport* only. A holder of
-- `owner_ledger.view` still reads ledger rows through RLS exactly as before, and the
-- Accountant's operational ledger authority (OA-1) is untouched.
--
-- **The start date travels here** rather than as a second read, so the settlement's owner
-- inputs still come from one MVCC snapshot (D-188). Null with `settlement_authorised` true
-- means "not configured", and the client refuses on it; it is never defaulted.
--
-- Everything OA-2 asserted still holds and is asserted again below: `language sql`, one
-- statement, `security invoker`, canonical movements only, `voided_at` carried, no
-- settlement arithmetic, no role-name branch.

create or replace function public.owner_ledger_snapshot()
returns jsonb
language sql
volatile
security invoker
set search_path = public, pg_temp
as $fn$
  with authority as (
    select public.has_capability_anywhere('owner_settlement.view')
       and public.has_capability_anywhere('owner_ledger.view')
       and public.has_capability_anywhere('reports.view') as settlement_authorised
  )
  select jsonb_build_object(
    'snapshot_id', pg_current_snapshot()::text,
    'server_time', now(),
    'settlement_authorised', a.settlement_authorised,

    'ownership_start_date', case when a.settlement_authorised then (
      select st.ownership_start_date
        from public.owner_settlement_settings st
       where st.org_id = public.current_org_id()
    ) end,

    'movements', case when a.settlement_authorised then coalesce((
      select jsonb_agg(to_jsonb(m) order by m.business_date, m.id)
        from (
          select e.id, e.org_id, e.business_unit_id, e.owner_id,
                 e.txn_number, e.financial_year,
                 e.business_date, e.business_date_source, e.pnl_period_key,
                 e.movement_type, e.direction, e.amount_minor,
                 e.family_member_id, e.collected_by_family_member_id,
                 e.nc_bill_reference, e.reference_number, e.remarks, e.reason,
                 e.created_by, e.captured_at, e.row_version, e.change_seq,
                 e.voided_at, e.void_reason
            from public.owner_ledger_entries e
           where e.txn_number is not null
        ) m
    ), '[]'::jsonb) end,

    'owners', case when a.settlement_authorised then coalesce((
      select jsonb_agg(to_jsonb(o) order by o.code)
        from (
          select w.id, w.org_id, w.code, w.display_name, w.active, w.archived_at,
                 w.row_version, w.change_seq
            from public.owners w
        ) o
    ), '[]'::jsonb) end,

    'ownership_shares', case when a.settlement_authorised then coalesce((
      select jsonb_agg(to_jsonb(s) order by s.owner_id, s.effective_from)
        from (
          select h.id, h.org_id, h.owner_id, h.share_basis_points,
                 h.effective_from, h.effective_to, h.note,
                 h.row_version, h.change_seq
            from public.ownership_shares h
        ) s
    ), '[]'::jsonb) end,

    'family_members', case when a.settlement_authorised then coalesce((
      select jsonb_agg(to_jsonb(f) order by f.owner_id, f.display_name)
        from (
          select fm.id, fm.org_id, fm.owner_id, fm.display_name, fm.relationship_label,
                 fm.is_self, fm.may_use_nc, fm.effective_from, fm.effective_to, fm.active,
                 fm.row_version, fm.change_seq
            from public.owner_family_members fm
        ) f
    ), '[]'::jsonb) end
  )
  from authority a
$fn$;

revoke all on function public.owner_ledger_snapshot() from public, anon;
grant execute on function public.owner_ledger_snapshot() to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- Assertions — OA-2's, restated over the replacement (D-174), and OA-3's own
-- ═════════════════════════════════════════════════════════════════════════════

do $$
declare v_src text; v_secdef boolean; v_lang text;
begin
  select p.prosrc, p.prosecdef, l.lanname
    into v_src, v_secdef, v_lang
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
   where n.nspname = 'public' and p.proname = 'owner_ledger_snapshot';

  if v_secdef then
    raise exception 'owner_ledger_snapshot is security definer; it must run with the caller''s privileges';
  end if;
  if v_lang <> 'sql' then
    raise exception 'owner_ledger_snapshot is no longer language sql (D-188)';
  end if;
  if (length(v_src) - length(replace(v_src, ';', ''))) > 1 then
    raise exception 'owner_ledger_snapshot contains more than one statement (D-188)';
  end if;
  if v_src ~* '\mentitlement\M' or v_src ~* '\mposition\M'
     or v_src ~* 'operating_profit' or v_src ~* '\mbalance\M' then
    raise exception 'owner_ledger_snapshot appears to calculate a settlement figure';
  end if;
  if v_src ~ '\mowner\M\s*=' or v_src ~ 'roles?\.code' then
    raise exception 'owner_ledger_snapshot branches on a role name rather than a capability';
  end if;
  if v_src not like '%txn_number is not null%' then
    raise exception 'owner_ledger_snapshot does not restrict itself to server-accepted movements';
  end if;
  if v_src not like '%voided_at%' then
    raise exception 'owner_ledger_snapshot drops voided_at (D-179)';
  end if;

  -- OA-3: the transport is gated on the settlement capability, and on the two it composes
  -- with. Asserted on the function body, which is the thing that acts.
  if v_src not like '%has_capability_anywhere(''owner_settlement.view'')%'
     or v_src not like '%has_capability_anywhere(''owner_ledger.view'')%'
     or v_src not like '%has_capability_anywhere(''reports.view'')%' then
    raise exception
      'owner_ledger_snapshot is not gated on owner_settlement.view AND owner_ledger.view '
      'AND reports.view';
  end if;
  if v_src not like '%''settlement_authorised''%' then
    raise exception 'owner_ledger_snapshot does not state whether the caller was authorised';
  end if;
  if v_src not like '%ownership_start_date%' then
    raise exception 'owner_ledger_snapshot does not carry the settlement start date';
  end if;
  -- Missing authority is never zero: an unauthorised caller receives null datasets, not
  -- empty arrays, so a device cannot certify an empty history as complete.
  -- Counted, not merely found: one dataset inside the case would satisfy a presence check
  -- while another leaked outside it.
  if (length(v_src) - length(replace(v_src, 'coalesce((', ''))) / length('coalesce((')
     <> (length(v_src) - length(replace(v_src, 'case when a.settlement_authorised then coalesce((', '')))
        / length('case when a.settlement_authorised then coalesce((') then
    raise exception 'owner_ledger_snapshot returns a dataset outside the authority case';
  end if;
end $$;

-- `anon` executes nothing, restated for the replaced function.
do $$
begin
  if has_function_privilege('anon', 'public.owner_ledger_snapshot()', 'execute') then
    raise exception 'public.owner_ledger_snapshot is executable by anon';
  end if;
end $$;
