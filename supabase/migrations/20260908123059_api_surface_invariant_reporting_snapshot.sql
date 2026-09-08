-- The reviewed API surface, restated in full because it grew (D-044).
--
-- Two additions, both **synchronisation transport** rather than reporting boundaries:
--
--   * `reporting_snapshot` returns the two canonical contribution datasets for a named set
--     of properties from ONE statement, with the MVCC snapshot's own identity and the
--     server's own transaction time. It replaces two independent per-dataset queries whose
--     results could not be shown to represent one authoritative moment;
--   * `reporting_newer_than` answers whether a contribution the caller may report on
--     carries a generation above a given cursor, and returns no financial figures.
--
-- Both are `security invoker` over the two `security_barrier` projections, so they return
-- nothing the caller could not already have selected. Both gate per unit on the full
-- reporting contract D-164 states and the Slice 5 corrective enforces — `reports.view`,
-- `revenue.view`, `expense.view.all` — so a property the caller may not report on yields
-- no rows and can never be certified into the cache. Neither requires `reports.export` or
-- `reports.print`, which remain Phase 7 and remain on D-139's exemption list.
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
    -- Phase 5 Slice 5 (D-184, D-187): the authoritative reporting aggregation core.
    'reporting_primitives',
    -- Phase 5 Slice 6: reporting synchronisation transport, one coherent snapshot.
    'reporting_snapshot', 'reporting_newer_than'];
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

-- Every security definer function pins its search_path. Restated because functions were
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

-- The three client-callable reporting functions are all `security invoker`, asserted where
-- a reviewer looking for it will find it. A later `create or replace` that flipped any of
-- them would run the projections as the owner and silently remove every scope predicate
-- from a report or from the cache a report is built on.
do $$
declare
  r record;
  v_seen int := 0;
begin
  for r in
    select p.proname, p.prosecdef
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('reporting_primitives', 'reporting_snapshot',
                         'reporting_newer_than')
  loop
    v_seen := v_seen + 1;
    if r.prosecdef then
      raise exception
        '% became security definer: a reporting read must never see more than the person '
        'asking for it', r.proname;
    end if;
  end loop;
  if v_seen <> 3 then
    raise exception
      'expected three client-callable reporting functions and found %; the surface moved '
      'without this invariant moving with it', v_seen;
  end if;
end $$;
