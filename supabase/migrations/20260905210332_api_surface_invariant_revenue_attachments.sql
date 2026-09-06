-- The reviewed API surface, restated in full because it grew (D-044).
--
-- Three additions, all Phase 4 Slice 11, and each is on the surface for a reason worth
-- naming rather than for convenience:
--
--   * `revenue_attachment_register` — the only writer of `revenue_attachments`. A client
--     calls it after the object lands, which is the second of the two writes that make an
--     upload finished (D-073a).
--   * `may_read_revenue_attachments` — a **Storage policy** predicate, and a storage
--     policy is evaluated with the querying user's privileges exactly like a table
--     policy. It has to be reachable by `authenticated` for the same reason
--     `may_read_expense_attachments` is (D-045, D-109).
--   * `storage_revenue_id` — the other half of that predicate, parsing the object path.
--
-- The list is restated whole rather than amended, because a diff against a list nobody
-- can see is not a review.
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
    -- table policies, so the predicates they call have to be reachable by
    -- `authenticated` for the same reason `current_org_id` is (D-045).
    'storage_expense_id', 'may_read_expense_attachments',
    'storage_revenue_id', 'may_read_revenue_attachments',
    -- D-073: a client registers an uploaded file as canonical metadata. One endpoint per
    -- parent document, because each re-checks its own parent's authority and a single
    -- endpoint taking the document kind from the caller would let a client choose which
    -- rules apply to it.
    'attachment_register', 'revenue_attachment_register',
    -- Phase 4 revenue. Configuration and mutation only: resolution, the arithmetic, the
    -- numbering and the advisory lock stay in `app`, which no client role can reach.
    'revenue_tax_rule_create', 'revenue_tax_rule_end_date',
    'revenue_create', 'revenue_update', 'revenue_void',
    -- Slice 6: the revenue configuration read policies resolve a category's business
    -- unit, and a policy runs with the caller's privileges, so the helper must be
    -- published for the same reason `current_org_id` is (D-045, D-109).
    'revenue_category_unit'];
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

-- Every SECURITY DEFINER function added this slice fixes its search_path, which the host
-- audit also asserts over the migration text. Checked here against the live catalogue as
-- well, because the two answer different questions: one is "what did we write", the other
-- "what is installed".
do $$
declare v_loose text;
begin
  select string_agg(p.proname, ', ') into v_loose
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app')
     and p.prosecdef
     and p.proname in ('revenue_attachment_register', 'may_read_revenue_attachments')
     and not exists (
       select 1 from unnest(coalesce(p.proconfig, array[]::text[])) as c
        where c like 'search_path=%');
  if v_loose is not null then
    raise exception 'a SECURITY DEFINER function has no fixed search_path: %', v_loose;
  end if;
end $$;
