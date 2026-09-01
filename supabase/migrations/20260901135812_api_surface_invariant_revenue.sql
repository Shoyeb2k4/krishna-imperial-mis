-- The reviewed API surface, restated in full to include the Phase 4 revenue boundary.
--
-- D-044: the list is declared in ONE place and restated whenever it grows, and the
-- assertion fails in BOTH directions — an unreviewed function that is callable, and a
-- reviewed one that has quietly stopped being callable.
--
-- It earned its keep again here. The first attempt to apply this file was REFUSED with
-- `a client role can execute functions in app: refuse_band_redefinition,
-- assert_revenue_has_components, revenue_rules_overlap, guard_revenue_rule_write`.
-- Postgres grants EXECUTE to PUBLIC on every new function, so the explicit revokes
-- written for the helpers I remembered restricted nothing for the four I did not. That is
-- precisely the D-044 finding, arriving in a new place a phase later, and caught by an
-- assertion rather than by review.
--
-- Trigger functions need no EXECUTE grant to fire: a trigger runs as the table owner, so
-- revoking these breaks nothing.
revoke all on function app.refuse_band_redefinition() from public, anon, authenticated;
revoke all on function app.assert_revenue_has_components() from public, anon, authenticated;
revoke all on function app.guard_revenue_rule_write() from public, anon, authenticated;
revoke all on function app.revenue_rules_overlap(public.revenue_tax_rates, public.revenue_tax_rates) from public, anon, authenticated;

do $$
declare
  v_anon       text;
  v_app        text;
  v_unexpected text;
  v_missing    text;
  v_api        text[] := array[
    'current_org_id', 'my_authority', 'has_capability', 'has_capability_anywhere',
    'has_unscoped_capability', 'scoped_units_for', 'period_state', 'tax_rule_for',
    'master_usage',
    'master_create', 'master_rename', 'master_archive', 'master_restore',
    'vendor_create', 'vendor_update',
    'tax_rule_create', 'tax_rule_supersede', 'tax_rule_archive',
    'period_close', 'period_reopen',
    'user_provision', 'user_deactivate', 'user_reactivate',
    'user_role_grant', 'user_role_revoke',
    'expense_create', 'expense_update', 'expense_void',
    'expense_visible_units', 'expense_sees_whole_org',
    -- Storage policies are evaluated with the querying user's privileges, exactly like
    -- table policies, so the two predicates they call have to be reachable by
    -- `authenticated` for the same reason `current_org_id` is (D-045).
    'storage_expense_id', 'may_read_expense_attachments',
    -- D-073: a client registers an uploaded bill as canonical metadata.
    'attachment_register',
    -- Phase 4 revenue. Configuration and mutation only: resolution, the arithmetic, the
    -- numbering and the advisory lock stay in `app`, which no client role can reach.
    'revenue_tax_rule_create', 'revenue_tax_rule_end_date',
    'revenue_create', 'revenue_void'];
begin
  select string_agg(p.proname, ', ') into v_anon
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if v_anon is not null then
    raise exception 'anon can execute functions in public: %', v_anon;
  end if;

  select string_agg(p.proname, ', ') into v_app
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_app is not null then
    raise exception 'a client role can execute functions in app: %', v_app;
  end if;

  select string_agg(p.proname, ', ') into v_unexpected
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and has_function_privilege('authenticated', p.oid, 'execute')
     and not (p.proname = any(v_api));
  if v_unexpected is not null then
    raise exception 'unreviewed function is callable by authenticated: %', v_unexpected;
  end if;

  select string_agg(name, ', ') into v_missing
    from unnest(v_api) as name
   where not exists (
     select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = name
        and has_function_privilege('authenticated', p.oid, 'execute'));
  if v_missing is not null then
    raise exception 'reviewed API function is not callable by authenticated: %', v_missing;
  end if;
end $$;
