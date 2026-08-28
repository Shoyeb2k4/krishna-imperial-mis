-- ─────────────────────────────────────────────────────────────────────────────
-- 0024 · The complete, current API surface, re-asserted
--
-- 0022 asserted this list when it was 23 functions long. `user_reactivate` (0023) has
-- since been added — the counterpart `user_deactivate` shipped without, which made
-- suspending somebody a one-way door through the API. Restated here in full, so there
-- is exactly one place that says what a signed-in client may call, and it fails the
-- migration if that stops being true.
--
-- It asserts in both directions on purpose. A function that becomes callable when it
-- should not be is a security defect; a reviewed function that quietly stops being
-- callable breaks the application just as completely, and is far easier to ship
-- unnoticed.
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare
  v_anon       text;
  v_app        text;
  v_unexpected text;
  v_missing    text;
  v_api        text[] := array[
    'current_org_id', 'my_authority', 'has_capability', 'has_capability_anywhere',
    'scoped_units_for', 'period_state', 'tax_rule_for', 'master_usage',
    'master_create', 'master_rename', 'master_archive', 'master_restore',
    'vendor_create', 'vendor_update',
    'tax_rule_create', 'tax_rule_supersede', 'tax_rule_archive',
    'period_close', 'period_reopen',
    'user_provision', 'user_deactivate', 'user_reactivate',
    'user_role_grant', 'user_role_revoke'];
begin
  -- Nothing at all may be callable without signing in.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_anon
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon is not null then
    raise exception 'anon can execute: %', v_anon;
  end if;

  -- The internal helpers stay internal.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_app
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  if v_app is not null then
    raise exception 'authenticated can execute internal helpers: %', v_app;
  end if;

  -- And in particular, the one that hands out ownership.
  if has_function_privilege('authenticated',
       'app.bootstrap_owner(text, text, boolean)'::regprocedure, 'EXECUTE')
     or has_function_privilege('anon',
       'app.bootstrap_owner(text, text, boolean)'::regprocedure, 'EXECUTE') then
    raise exception 'bootstrap_owner is client-reachable - this is a privilege-escalation route';
  end if;

  -- Nothing callable that has not been reviewed.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_unexpected
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and not (p.proname = any(v_api));
  if v_unexpected is not null then
    raise exception 'unreviewed function is callable by authenticated: %', v_unexpected;
  end if;

  -- And nothing reviewed that has quietly stopped being callable.
  select string_agg(name, ', ')
    into v_missing
    from unnest(v_api) as name
   where not exists (
     select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = name
        and has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  if v_missing is not null then
    raise exception 'reviewed API function is not callable by authenticated: %', v_missing;
  end if;

  raise notice 'API surface verified: % functions callable by authenticated, none by anon',
               array_length(v_api, 1);
end $$;
