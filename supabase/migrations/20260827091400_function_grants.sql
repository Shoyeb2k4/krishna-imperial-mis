-- ─────────────────────────────────────────────────────────────────────────────
-- 0015 · Least privilege on functions
--
-- Postgres grants `EXECUTE` on a new function to `PUBLIC` **by default**. Writing
-- `grant execute … to authenticated` therefore does not restrict anything — it merely
-- restates an access that `anon` already had. Every RPC in 0009 through 0014 was
-- reachable by an unauthenticated caller holding nothing but the publishable key.
--
-- In practice each mutation refused: they all call `app.require_actor()` first, which
-- raises `KM011` when `auth.uid()` is null. But "it happens to fail closed" is not the
-- same claim as "it cannot be called", and only the second is worth making. A future
-- function that forgets that first line would have been wide open with no other guard.
--
-- So `PUBLIC` loses `EXECUTE` on everything in `public` and `app`, `authenticated` keeps
-- only the explicitly intended list, and the migration **fails** if anything is still
-- reachable that should not be. The assertion matters more than the revoke: it turns
-- this from a fix into a property that stays true.
--
-- The `app` schema was already gated by `revoke all on schema app from public` (0001).
-- This is the second lock on that door, not the first.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Strip the default ────────────────────────────────────────────────────────
-- Only functions this project created: anything belonging to an extension is left
-- exactly as its extension installed it.
do $$
declare fn record;
begin
  for fn in
    select p.oid::regprocedure as signature
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app')
       and not exists (
         select 1 from pg_depend d
          where d.objid = p.oid and d.deptype = 'e'
       )
  loop
    execute format('revoke all on function %s from public', fn.signature);
    execute format('revoke all on function %s from anon', fn.signature);
  end loop;
end $$;

-- ── Re-grant exactly what a signed-in client needs ───────────────────────────
-- Read-only predicates the client uses to shape its UI honestly. Each re-derives
-- everything from auth.uid(); none of them accepts a caller's opinion about who it is.
grant execute on function public.has_capability(text, uuid)    to authenticated;
grant execute on function public.has_capability_anywhere(text) to authenticated;
grant execute on function public.scoped_units_for(text)        to authenticated;
grant execute on function public.period_state(text, uuid)      to authenticated;
grant execute on function public.tax_rule_for(uuid, date)      to authenticated;
grant execute on function public.master_usage(text, uuid)      to authenticated;

-- Administrative mutations. Every one re-checks capability, unit scope, record state and
-- row version server-side before it touches anything.
grant execute on function public.master_create(text, uuid, text, text, jsonb, uuid, uuid) to authenticated;
grant execute on function public.master_rename(text, uuid, text, integer, boolean, uuid)  to authenticated;
grant execute on function public.master_archive(text, uuid, integer, uuid)                to authenticated;
grant execute on function public.master_restore(text, uuid, integer, uuid)                to authenticated;
grant execute on function public.vendor_create(text, text, jsonb, uuid, uuid)             to authenticated;
grant execute on function public.vendor_update(uuid, integer, jsonb, uuid)                to authenticated;
grant execute on function public.tax_rule_create(uuid, integer, text, date, date, text, uuid, uuid) to authenticated;
grant execute on function public.tax_rule_supersede(uuid, integer, integer, text, date, text, uuid, uuid) to authenticated;
grant execute on function public.tax_rule_archive(uuid, integer, uuid)                    to authenticated;
grant execute on function public.period_close(text, uuid, uuid)                           to authenticated;
grant execute on function public.period_reopen(text, text, uuid, integer, uuid)           to authenticated;
grant execute on function public.user_role_grant(uuid, text, uuid, uuid)                  to authenticated;
grant execute on function public.user_role_revoke(uuid, uuid)                             to authenticated;

-- ── Prove it, rather than assert it in a comment ─────────────────────────────
do $$
declare
  v_anon_reachable text;
  v_app_reachable  text;
  v_unexpected     text;
begin
  -- Nothing at all may be callable without signing in.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_anon_reachable
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_reachable is not null then
    raise exception 'anon can still execute: %', v_anon_reachable;
  end if;

  -- The internal helpers are internal. `app` is not an API surface.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_app_reachable
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE');

  if v_app_reachable is not null then
    raise exception 'authenticated can execute internal helpers: %', v_app_reachable;
  end if;

  -- And in particular, the one that hands out ownership.
  if has_function_privilege('authenticated',
       'app.bootstrap_owner(text, text, boolean)'::regprocedure, 'EXECUTE')
     or has_function_privilege('anon',
       'app.bootstrap_owner(text, text, boolean)'::regprocedure, 'EXECUTE') then
    raise exception 'bootstrap_owner is client-reachable — this is a privilege-escalation route';
  end if;

  -- Anything in `public` that a signed-in client can call but that is not on the list
  -- above is a function somebody added without deciding who may run it.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_unexpected
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.proname not in (
       'has_capability', 'has_capability_anywhere', 'scoped_units_for', 'period_state',
       'tax_rule_for', 'master_usage', 'master_create', 'master_rename', 'master_archive',
       'master_restore', 'vendor_create', 'vendor_update', 'tax_rule_create',
       'tax_rule_supersede', 'tax_rule_archive', 'period_close', 'period_reopen',
       'user_role_grant', 'user_role_revoke');

  if v_unexpected is not null then
    raise exception 'unreviewed function is callable by authenticated: %', v_unexpected;
  end if;

  raise notice 'function privileges verified: anon reaches nothing, authenticated reaches only the reviewed API';
end $$;

-- ── And keep it true for anything added later ────────────────────────────────
-- New functions in these schemas start with no PUBLIC grant at all, so the next one
-- written is closed until somebody deliberately opens it.
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema app    revoke execute on functions from public;
