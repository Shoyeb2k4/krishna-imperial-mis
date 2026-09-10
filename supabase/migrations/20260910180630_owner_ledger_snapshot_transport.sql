-- Server migration ledger name: owner_ledger_snapshot_transport
--
-- Phase 5 OA-2 §18, §19, §20 · the canonical owner data a device needs for a settlement,
-- in one coherent read.
--
-- The header names no ledger version: the version is assigned at apply time, so a file
-- naming it cannot be the text that was submitted (D-203). `LEDGER.md` maps it.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What the audit found, and why this exists
-- ═════════════════════════════════════════════════════════════════════════════
--
-- `test/remote/owner_settlement_completeness_audit_test.dart` proved, against this
-- database with a fresh device, that a second device sees **nothing**: not the owner
-- movements another device recorded, and not the owners, ownership shares or family links
-- a settlement needs to allocate by at all. The client held only what it had itself
-- recorded, and `ownershipShares()` read a local table nothing in production writes.
--
-- **The gap was entirely client-side.** The same session that could not see a movement
-- locally was handed it by the server through the ordinary projections. So this adds a
-- caller's read, not a boundary — which is exactly the finding D-173 recorded for
-- reporting, arriving in a second domain.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Why one statement rather than four reads
-- ═════════════════════════════════════════════════════════════════════════════
--
-- A settlement needs movements **and** the ownership vector **and** the family links. Four
-- separate PostgREST reads are four MVCC snapshots under READ COMMITTED, and a settlement
-- assembled from them would be a position of a moment that never existed — which is
-- precisely the defect D-188 had to correct for reporting, and knowingly repeating it
-- would be worse than the first time.
--
-- So: one `language sql` function, one statement, `pg_current_snapshot()` and `now()` read
-- from that same statement. An invariant below refuses a body containing more than one
-- statement or rewritten as `plpgsql`, where two statements would take two snapshots.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Why this is not the settlement RPC OA-2 §44 says to stop for
-- ═════════════════════════════════════════════════════════════════════════════
--
-- It **calculates nothing**. It returns canonical facts — movements, owners, shares,
-- family links — and no entitlement, no position, no balance and no P&L. The settlement
-- arithmetic lives in `domain/owner_accounts/settlement/`, on the client, and is fed by
-- this.
--
-- It is `security invoker`, so it runs with the caller's own privileges over tables whose
-- RLS already governs exactly these rows under `owner_ledger.view`. **Anything it can
-- return, the caller could already have selected row by row** — it grants no new access,
-- and it therefore needs no new capability. `owner_settlement.view` stays reserved for
-- OA-3 and is not created here (§44).
--
-- Two invariants assert `prosecdef = false`, because a `security definer` version would
-- run as the owner against tables the caller may deliberately not read.

create or replace function public.owner_ledger_snapshot()
returns jsonb
language sql
volatile
security invoker
set search_path = public, pg_temp
as $fn$
  select jsonb_build_object(
    -- The MVCC snapshot every dataset below jointly represents. Opaque to the client and
    -- meaningful under equality: two reads that saw the same view really are one moment.
    'snapshot_id', pg_current_snapshot()::text,

    -- The server's own transaction timestamp, from this statement. Never a second
    -- `select now()`, which would date one moment with another's clock, and never a
    -- device reading, which is not evidence about a server (spec §9).
    'server_time', now(),

    -- **Every** canonical owner movement the caller may read, with no period filter and
    -- no watermark. The ledger is small — a handful of movements a month — and a full
    -- read makes a correction and a void propagate by themselves: the row comes back
    -- changed, or it comes back carrying `voided_at`. That removes the entire
    -- document-grain replacement and lowest-watermark apparatus the reporting delta needs
    -- (D-178, D-180), which is the simplest correct thing rather than the cheapest.
    --
    -- `voided_at` is carried rather than filtered, for the same reason the contribution
    -- projections carry it (D-179): a filtered read would make a voided movement vanish
    -- with nothing left to name it, and the client would keep a stale one for ever.
    'movements', coalesce((
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
    ), '[]'::jsonb),

    'owners', coalesce((
      select jsonb_agg(to_jsonb(o) order by o.code)
        from (
          select w.id, w.org_id, w.code, w.display_name, w.active, w.archived_at,
                 w.row_version, w.change_seq
            from public.owners w
        ) o
    ), '[]'::jsonb),

    'ownership_shares', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.owner_id, s.effective_from)
        from (
          select h.id, h.org_id, h.owner_id, h.share_basis_points,
                 h.effective_from, h.effective_to, h.note,
                 h.row_version, h.change_seq
            from public.ownership_shares h
        ) s
    ), '[]'::jsonb),

    'family_members', coalesce((
      select jsonb_agg(to_jsonb(f) order by f.owner_id, f.display_name)
        from (
          select m.id, m.org_id, m.owner_id, m.display_name, m.relationship_label,
                 m.is_self, m.may_use_nc, m.effective_from, m.effective_to, m.active,
                 m.row_version, m.change_seq
            from public.owner_family_members m
        ) f
    ), '[]'::jsonb)
  );
$fn$;

revoke all on function public.owner_ledger_snapshot() from public, anon;
grant execute on function public.owner_ledger_snapshot() to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- Assertions
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
    raise exception
      'owner_ledger_snapshot is security definer. It would then run as the owner over '
      'tables the caller may deliberately not read, and would grant access nothing '
      'reviewed';
  end if;

  if v_lang <> 'sql' then
    raise exception
      'owner_ledger_snapshot is no longer `language sql`. A plpgsql rewrite takes one '
      'snapshot per statement, and the whole point of this function is that every dataset '
      'it returns belongs to one (D-188)';
  end if;

  -- One statement. Counting semicolons outside the dollar-quoted body is not available
  -- here, so this counts them in the body and allows exactly the one terminator.
  if (length(v_src) - length(replace(v_src, ';', ''))) > 1 then
    raise exception
      'owner_ledger_snapshot contains more than one statement, so its datasets no longer '
      'come from one MVCC snapshot (D-188)';
  end if;

  -- It returns facts, not a calculation. A settlement RPC would need the capability OA-3
  -- reserves, and adding one here would be shipping an under-authorized boundary (§44).
  if v_src ~* '\mentitlement\M' or v_src ~* '\mposition\M'
     or v_src ~* 'operating_profit' or v_src ~* '\mbalance\M' then
    raise exception
      'owner_ledger_snapshot appears to calculate a settlement figure. It transports '
      'canonical facts; the arithmetic is the client domain''s, and a client-callable '
      'settlement boundary needs the capability OA-3 owns';
  end if;

  -- And no role-name branch, the guard three reporting migrations already assert.
  if v_src ~ '\mowner\M\s*=' or v_src ~ 'roles?\.code' then
    raise exception
      'owner_ledger_snapshot branches on a role name rather than a capability';
  end if;
end $$;

-- Only canonical movements leave the server. An attempt the server never accepted is
-- somebody's intent, and a settlement over it would report money the business does not
-- have (§16, §17, D-168).
do $$
declare v_src text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_ledger_snapshot';

  if v_src not like '%txn_number is not null%' then
    raise exception
      'owner_ledger_snapshot does not restrict itself to server-accepted movements';
  end if;
  if v_src not like '%voided_at%' then
    raise exception
      'owner_ledger_snapshot drops voided_at. A filtered read makes a voided movement '
      'vanish with nothing left to name it, and the client keeps a stale one for ever '
      '(D-179)';
  end if;
end $$;

-- `anon` executes nothing, restated for the one function this migration adds.
do $$
begin
  if has_function_privilege('anon', 'public.owner_ledger_snapshot()', 'execute') then
    raise exception 'public.owner_ledger_snapshot is executable by anon';
  end if;
  if exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where n.nspname = 'public' and p.proname = 'owner_ledger_snapshot'
       and a.privilege_type = 'EXECUTE' and a.grantee = 0
  ) then
    raise exception 'public.owner_ledger_snapshot is executable by PUBLIC';
  end if;
end $$;

-- No new capability was created. `owner_settlement.view` is OA-3's boundary, and a
-- capability granted and evaluated by nothing is the family this project keeps recording
-- (D-068, D-071, D-077, D-116, D-139).
do $$
begin
  if exists (select 1 from public.capabilities where code = 'owner_settlement.view') then
    raise exception
      'owner_settlement.view exists. OA-1 and OA-2 reserve that boundary for OA-3, which '
      'creates it together with the surface that reads it';
  end if;
end $$;
