-- Server migration ledger: 20260909111136  api_surface_invariant_owner_accounts
--
-- The reviewed API surface, restated in full because it grew (D-044).
--
-- Seven additions, all of them the Owner Accounts mutation boundary:
--
--   * `owner_create`, `owner_share_set`, `owner_family_member_create` and
--     `owner_family_member_end` administer who the owners are, what each is entitled to
--     and which people consume against which account. All four require the **unscoped**
--     `owner_masters.manage`: an owner is not a property's owner, and a grant scoped to
--     one building cannot authorise a statement about the organisation.
--   * `owner_movement_create`, `owner_movement_update` and `owner_movement_void` are the
--     financial write path. Each re-checks capability, unit scope, period lock, edit
--     window and `base_row_version` server-side, exactly as their expense and revenue
--     counterparts do.
--
-- All seven are `security definer` with a pinned `search_path`, and none of them takes an
-- organisation id, a role or an authority claim from the caller. There is deliberately no
-- `owner_movement_correct_business_date`: a date correction is an **update**, decided from
-- canonical state inside `owner_movement_update`, which is the one contract lesson D-127
-- and D-137 paid for and this domain starts from rather than repeating.
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
    'reporting_primitives',
    'reporting_snapshot', 'reporting_newer_than',
    -- Phase 5 OA-1: the Owner Accounts boundary.
    'owner_create', 'owner_share_set',
    'owner_family_member_create', 'owner_family_member_end',
    'owner_movement_create', 'owner_movement_update', 'owner_movement_void'];
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

-- Every security definer function pins its search_path. Restated because seven were added
-- above, and an addition is where a `set search_path` gets left off.
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

-- ── No capability is granted and evaluated nowhere (D-127 section 3, D-139) ──
--
-- Restated whole against the catalogue the Owner Accounts capabilities have now joined.
-- The exemption list is unchanged and is reproduced rather than referenced: reading a
-- list from an earlier migration would be a guard keyed on an incidental occurrence of
-- the right thing, which is D-103's failure and has already happened twice in this file's
-- own machinery.
do $$
declare
  v_dead text;
  v_unbuilt constant text[] := array[
    'reports.export',    -- Phase 7 · no export path exists
    'reports.print',     -- Phase 7 · no print path exists
    'settings.manage'];  -- no settings RPC exists
begin
  select string_agg(distinct rc.capability_code, ', ') into v_dead
    from public.role_capabilities rc
   where not (rc.capability_code = any(v_unbuilt))
     and not exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'app') and p.prokind = 'f'
              and pg_get_functiondef(p.oid) like '%' || rc.capability_code || '%')
     and not exists (
           select 1 from pg_policies pol
            where coalesce(pol.qual, '') like '%' || rc.capability_code || '%'
               or coalesce(pol.with_check, '') like '%' || rc.capability_code || '%');
  if v_dead is not null then
    raise exception
      'granted in production and evaluated nowhere: %. Either the check was never '
      'written or the grant was never meant (D-127 section 3)', v_dead;
  end if;

  select string_agg(c, ', ') into v_dead
    from unnest(v_unbuilt) as c
   where exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'app') and p.prokind = 'f'
              and pg_get_functiondef(p.oid) like '%' || c || '%')
      or exists (
           select 1 from pg_policies pol
            where coalesce(pol.qual, '') like '%' || c || '%'
               or coalesce(pol.with_check, '') like '%' || c || '%');
  if v_dead is not null then
    raise exception
      'the not-yet-built exemption list names a capability that now HAS an evaluator: %. '
      'Delete the line — an excuse that has stopped being true is worse than no list',
      v_dead;
  end if;
end $$;

-- ── Stated positively for the Owner Accounts domain ─────────────────────────
--
-- The two assertions above would both pass if every owner capability were simply granted
-- to nobody, which is the D-139 defect in reverse. This says what must be true.
do $inv$
declare v_missing text;
begin
  select string_agg(c.code, ', ') into v_missing
    from public.capabilities c
   where c.category = 'owner_accounts'
     and not exists (select 1 from public.role_capabilities rc
                      where rc.capability_code = c.code);
  if v_missing is not null then
    raise exception 'owner-account capability granted to no role at all: %', v_missing;
  end if;

  -- The two sensitive reads are gated on the **unscoped** form, and that is asserted
  -- rather than described: a per-property slice of an owner's current account is not a
  -- narrower view but a misleading one, showing part of an account with nothing saying so.
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'owner_ledger_entries'
       and coalesce(qual, '') like '%has_unscoped_capability%owner_ledger.view%') then
    raise exception
      'the owner ledger read policy does not require the unscoped owner_ledger.view; a '
      'scoped reader would see part of an account and could not tell';
  end if;
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'ownership_shares'
       and coalesce(qual, '') like '%has_unscoped_capability%owner_ledger.view%') then
    raise exception
      'the ownership share read policy is not gated on the unscoped owner_ledger.view; a '
      'profit ratio is what an entitlement is computed from';
  end if;

  -- And the owner-drawings guard is a control rather than a comment.
  if not exists (
    select 1 from pg_trigger tg
      join pg_class c on c.oid = tg.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_proc p on p.oid = tg.tgfoid
     where n.nspname = 'public' and c.relname = 'expense_categories'
       and p.proname = 'refuse_owner_drawings_expense_category'
       and not tg.tgisinternal) then
    raise exception
      'the owner-drawings expense guard is not installed; owner movements could be '
      'booked as operating expenses and would reduce Operating Profit (OA-1 section 25)';
  end if;
end $inv$;
