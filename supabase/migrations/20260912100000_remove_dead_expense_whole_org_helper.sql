-- Server migration ledger name: remove_dead_expense_whole_org_helper
--
-- Phase 5 Slice 7 · `expense_sees_whole_org()` has no policy, function or client
-- caller. It is therefore executable surface without an evaluator and is removed rather
-- than retained as a speculative convenience. The reviewed API is restated whole after
-- the drop so both omissions and accidental additions fail this migration.

begin;

revoke all on function public.expense_sees_whole_org() from public;
revoke all on function public.expense_sees_whole_org() from anon;
revoke all on function public.expense_sees_whole_org() from authenticated;
drop function public.expense_sees_whole_org();

do $$
declare
  v_anon       text;
  v_app        text;
  v_unexpected text;
  v_missing    text;
  v_dead       text;
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
    'expense_visible_units', 'may_read_expense',
    'storage_expense_id', 'may_read_expense_attachments',
    'storage_revenue_id', 'may_read_revenue_attachments',
    'may_attach_to_expense', 'may_attach_to_revenue',
    'attachment_object_is_registered',
    'attachment_register', 'revenue_attachment_register',
    'revenue_tax_rule_create', 'revenue_tax_rule_end_date',
    'revenue_create', 'revenue_update', 'revenue_void',
    'revenue_category_unit',
    'reporting_primitives', 'reporting_snapshot', 'reporting_newer_than',
    'owner_create', 'owner_share_set',
    'owner_family_member_create', 'owner_family_member_end',
    'owner_movement_create', 'owner_movement_update', 'owner_movement_void',
    'owner_ledger_snapshot', 'owner_settlement_start_set'];
begin
  select string_agg(p.proname, ', ') into v_dead
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'expense_sees_whole_org';
  if v_dead is not null then
    raise exception 'dead expense whole-organisation helper still exists: %', v_dead;
  end if;

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

commit;
