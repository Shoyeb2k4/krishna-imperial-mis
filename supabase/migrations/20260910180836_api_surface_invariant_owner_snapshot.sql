-- Server migration ledger name: api_surface_invariant_owner_snapshot
--
-- Phase 5 OA-2 · the reviewed API surface, restated because it grew by one.
--
-- The header names no ledger version (D-203); `LEDGER.md` maps it.
--
-- `owner_ledger_snapshot` is client-callable, so it is on the surface whether or not
-- anybody thinks of it as an API (D-044). The list is restated **whole** rather than
-- amended, because a diff against a list nobody can see is not a review.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- One assertion is deliberately NOT copied forward, and that is the point
-- ═════════════════════════════════════════════════════════════════════════════
--
-- `20260909111136` asserted that the two owner read policies require the **unscoped**
-- `owner_ledger.view`. `20260909112045` then replaced that gate with
-- `has_capability_anywhere`, because D-025 forces every non-Owner grant to name a business
-- unit and the unscoped form was therefore satisfiable by the Owner and by nobody else —
-- the Accountant could write and read nothing (D-200).
--
-- Copying the older assertion into this file would have restated a rule the database no
-- longer satisfies, from the migration that **first** defined the policy rather than the
-- one that last replaced it. That is D-174 exactly, and it is the reason a restatement is
-- built from what the object is rather than from the file it came from. The corrected
-- form is below, and the all-or-nothing property it was really protecting is asserted
-- explicitly beside it.

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
    -- not calculation — it returns facts and no entitlement, no position, no balance.
    'owner_ledger_snapshot'];
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

-- Every security definer function still pins its search_path. Restated because the
-- surface grew, and an addition is where a `set search_path` gets left off.
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
  -- All-or-nothing, which is the property that matters: an owner's current account spans
  -- both properties, so a per-property slice is not a narrower view but a misleading one.
  -- Checked as "gated on owner_ledger.view and filtering by no business unit" rather than
  -- by naming a helper, so the next correction to the helper does not silently pass.
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
    raise exception
      'the ownership share read policy is not gated on owner_ledger.view; a profit ratio '
      'is what an entitlement is computed from';
  end if;

  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('owner_ledger_entries', 'ownership_shares')
       and coalesce(qual, '') like '%business_unit_id%') then
    raise exception
      'an owner read policy filters by business unit. That shows part of an owner '
      'position with nothing saying so (D-196)';
  end if;

  -- And the gate has to be one a holder can actually satisfy. D-025 makes every non-Owner
  -- grant scoped, so an unscoped requirement is satisfiable by the Owner alone, for ever —
  -- which is D-110, D-116 and D-200, three times in this project.
  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('owner_ledger_entries', 'ownership_shares')
       and coalesce(qual, '') like '%has_unscoped_capability%owner_ledger.view%') then
    raise exception
      'an owner read policy requires the unscoped owner_ledger.view again. Only the Owner '
      'can ever hold that, so every other grant of the capability reads nothing (D-200)';
  end if;

  -- The owner-drawings guard is still a control rather than a comment.
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

-- ── No capability is granted and evaluated nowhere (D-127 section 3, D-139) ──
--
-- Restated whole. The exemption list is unchanged and is reproduced rather than
-- referenced: reading it from an earlier migration would be a guard keyed on an incidental
-- occurrence of the right thing, which is D-103's failure.
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
