-- The reviewed API surface, restated in full because it grew (D-044).
--
-- One addition: `reporting_primitives`, the Slice 5 aggregation core. It is client-callable
-- deliberately and narrowly:
--
--   * it is `security invoker`, so it runs with the caller's own privileges over the two
--     `security_barrier` contribution projections and returns nothing that caller could not
--     already have selected row by row and added up. It grants **no new data access**;
--   * it gates each side of the P&L on D-164's data half — `revenue.view` for revenue,
--     `expense.view.all` for expenses, per property — and returns null rather than zero for
--     a side the caller may not read, so a Data Entry user holding own-only expense
--     visibility cannot be handed a plausible P&L built from a revenue side of nothing;
--   * what it does not check is `reports.view`, which has no evaluator anywhere yet and
--     stays on D-139's exemption list until Slice 7 builds the reporting capability model.
--     Its absence creates no exposure for the reason above; it is a third gate on top of a
--     boundary that already holds, not the boundary itself.
--
-- The list is restated whole rather than amended, because a diff against a list nobody can
-- see is not a review.
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
    'may_read_expense',
    'storage_expense_id', 'may_read_expense_attachments',
    'storage_revenue_id', 'may_read_revenue_attachments',
    'may_attach_to_expense', 'may_attach_to_revenue',
    'attachment_object_is_registered',
    'attachment_register', 'revenue_attachment_register',
    'revenue_tax_rule_create', 'revenue_tax_rule_end_date',
    'revenue_create', 'revenue_update', 'revenue_void',
    'revenue_category_unit',
    -- Phase 5 Slice 5 (D-184): the authoritative reporting aggregation core.
    'reporting_primitives'];
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

-- Every security definer function pins its search_path. Restated because a function was
-- added above, and an addition is where a `set search_path` gets left off.
do $$
declare v_bad text;
begin
  select string_agg(p.proname, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app')
     and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, array[]::text[])) as c
                      where c like 'search_path=%');
  if v_bad is not null then
    raise exception 'security definer function without a pinned search_path: %', v_bad;
  end if;
end $$;

-- And the one that matters most for this addition, asserted where it is easy to find: the
-- only new client-callable function in Slice 5 is not `security definer`. A later
-- `create or replace` that flipped it would run the projections as the owner and silently
-- remove every scope predicate from a report.
do $$
declare v_secdef boolean;
begin
  select p.prosecdef into v_secdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reporting_primitives';
  if v_secdef is null then
    raise exception 'reporting_primitives does not exist';
  end if;
  if v_secdef then
    raise exception
      'reporting_primitives became security definer: a reporting read must never see more '
      'than the person asking for it';
  end if;
end $$;
