-- Server migration ledger name: api_surface_invariant_owner_settlement
--
-- Phase 5 OA-3 · the reviewed API surface, restated because it grew by one, and the OA-3
-- security contract asserted over the catalogue.
--
-- The header names no ledger version (D-203); `LEDGER.md` maps it.
--
-- `owner_settlement_start_set` is client-callable, so it is on the surface whether or not
-- anybody thinks of it as an API (D-044). The list is restated **whole** rather than
-- amended, because a diff against a list nobody can see is not a review. Every other
-- assertion is restated from what the objects **are now** — the owner reads from
-- `20260909112045`, not from the migration that first created them (D-174).

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
    'owner_movement_create', 'owner_movement_update', 'owner_movement_void',
    -- Phase 5 OA-2: the canonical owner data a settlement is computed from. Transport,
    -- not calculation — and since OA-3 closed to anybody without owner_settlement.view.
    'owner_ledger_snapshot',
    -- Phase 5 OA-3: the one writer of the date 50:50 ownership and settlement begin.
    'owner_settlement_start_set'];
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

-- Every security definer function still pins its search_path.
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

-- ── The owner reads, asserted as they actually are ──────────────────────────
do $inv$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'owner_ledger_entries'
       and coalesce(qual, '') like '%owner_ledger.view%') then
    raise exception 'the owner ledger read policy is not gated on owner_ledger.view';
  end if;
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'ownership_shares'
       and coalesce(qual, '') like '%owner_ledger.view%') then
    raise exception 'the ownership share read policy is not gated on owner_ledger.view';
  end if;

  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('owner_ledger_entries', 'ownership_shares',
                         'owner_settlement_settings')
       and coalesce(qual, '') like '%business_unit_id%') then
    raise exception
      'an owner read policy filters by business unit. That shows part of an owner '
      'position with nothing saying so (D-196)';
  end if;

  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('owner_ledger_entries', 'ownership_shares',
                         'owner_settlement_settings')
       and coalesce(qual, '') like '%has_unscoped_capability%') then
    raise exception
      'an owner read policy requires an unscoped capability, which only the Owner can '
      'ever hold (D-200)';
  end if;

  if not exists (
    select 1 from pg_trigger tg
      join pg_class c on c.oid = tg.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_proc p on p.oid = tg.tgfoid
     where n.nspname = 'public' and c.relname = 'expense_categories'
       and p.proname = 'refuse_owner_drawings_expense_category'
       and not tg.tgisinternal) then
    raise exception 'the owner-drawings expense guard is not installed (OA-1 section 25)';
  end if;
end $inv$;

-- ── The OA-3 settlement contract, over the catalogue ─────────────────────────
do $oa3$
declare v_src text;
begin
  -- Owner bundle only (OA-3 Q2).
  if exists (
    select 1 from public.role_capabilities rc
      join public.roles r on r.id = rc.role_id
     where rc.capability_code = 'owner_settlement.view'
       and r.code <> 'owner') then
    raise exception 'owner_settlement.view is held outside the Owner bundle';
  end if;
  if not exists (
    select 1 from public.role_capabilities rc
      join public.roles r on r.id = rc.role_id
     where rc.capability_code = 'owner_settlement.view' and r.code = 'owner') then
    raise exception 'owner_settlement.view is granted to nobody';
  end if;

  -- The settlement transport is gated on it, on the body that acts.
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_ledger_snapshot';
  if v_src not like '%owner_settlement.view%' then
    raise exception 'the settlement transport is not gated on owner_settlement.view';
  end if;

  -- No client writes the start date except through the reviewed RPC.
  if has_table_privilege('authenticated', 'public.owner_settlement_settings', 'insert')
     or has_table_privilege('authenticated', 'public.owner_settlement_settings', 'update')
     or has_table_privilege('authenticated', 'public.owner_settlement_settings', 'delete')
     or has_table_privilege('authenticated', 'public.owner_settlement_settings', 'truncate') then
    raise exception 'a client can write owner_settlement_settings directly';
  end if;
end $oa3$;

-- ── No capability is granted and evaluated nowhere (D-127 section 3, D-139) ──
--
-- Restated whole. `owner_settlement.view` is not on the exemption list: it is evaluated by
-- the settlement transport and by the start-date read policy, and a capability created
-- without its evaluator is the defect this search exists for.
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
      'the not-yet-built exemption list names a capability that now HAS an evaluator: %',
      v_dead;
  end if;
end $$;
