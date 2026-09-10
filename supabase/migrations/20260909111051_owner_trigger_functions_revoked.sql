-- Server migration ledger: 20260909111051  owner_trigger_functions_revoked
--
-- Phase 5 OA-1 · a defect the API-surface invariant refused to let through.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What happened, stated plainly
-- ═════════════════════════════════════════════════════════════════════════════
--
-- `20260909090100_owner_accounts_schema` creates two trigger functions —
-- `app.refuse_family_owner_reassignment` and `app.refuse_voided_owner_movement` — and
-- wrote no revoke for either. Postgres grants `EXECUTE` to `PUBLIC` on every new
-- function, so both became callable by `authenticated`, and the next migration's
-- invariant refused to apply:
--
--     a client role can execute functions in app:
--       refuse_family_owner_reassignment, refuse_voided_owner_movement
--
-- **This is D-044 exactly, and D-101 is it happening a second time one phase later.**
-- The revokes in the schema migration covered the functions that were front of mind —
-- `owner_window_today`, `owner_movement_capability`, `next_owner_number` — and missed the
-- two that arrive as a side effect of installing a trigger. A default privilege is not a
-- guard; it is a default.
--
-- The exposure was narrow: both are `returns trigger`, so a direct call raises
-- `2F000 trigger functions can only be called as triggers` before any statement runs, and
-- neither reads anything the caller could not already reach. That is *"happens to fail
-- closed"*, which D-044 already refused as a standard. What matters is that a client role
-- could reach into `app` at all.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Why this is its own file rather than an edit to the schema migration
-- ═════════════════════════════════════════════════════════════════════════════
--
-- The schema migration has been applied. Rewriting it to look like something that never
-- ran is the substitution A0 and D-056 exist to prevent — and its `create policy`
-- statements are not idempotent, so it cannot simply be re-run either. The applied file
-- stays as it is and the correction gets its own commit, exactly as D-138 did when the
-- first business-date-correction migration's own live test found a defect in the fix.
--
-- On a fresh replay the ordering is identical: the schema migration creates the
-- functions, this one closes them, and the invariant that follows sees a clean surface.

revoke all on function app.refuse_family_owner_reassignment()
  from public, anon, authenticated;
revoke all on function app.refuse_voided_owner_movement()
  from public, anon, authenticated;

-- ── And no owner-account function anywhere in `app` is client-callable ───────
--
-- Stated as a search over the schema rather than as a list of the two that were wrong.
-- A list would pass for ever and catch nothing; the next trigger function added to this
-- domain would arrive exactly as these two did.

do $$
declare v_bad text;
begin
  select string_agg(p.proname, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (p.proname like 'owner%'
          or p.proname like '%owner_movement%'
          or p.proname like '%family_owner%'
          or p.proname = 'next_owner_number')
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_bad is not null then
    raise exception
      'an owner-account helper in app is callable by a client role: %. Postgres grants '
      'EXECUTE to PUBLIC on every new function, so the revoke has to be written (D-044, '
      'D-101)', v_bad;
  end if;
end $$;
