-- Server migration ledger name: reporting_snapshot_paged
--
-- Phase 8 · D-318 R3, approved with modification by the project lead; contract D-320.
--
-- `reporting_snapshot` answered every synchronisation — first or delta — with one JSON
-- document holding every changed contribution the caller may see, over ALL history. At
-- SCALE a delta exceeded the 8 s `authenticated` statement timeout; at STRESS a first
-- sync exceeded PostgreSQL's 256 MB jsonb limit (D-318). It is replaced by a paged,
-- restartable transport. NO retention cutoff is introduced: a run still delivers every
-- authorised document the caller asks about, in bounded pages, until there are no more.
--
-- ── The contract (D-320) ─────────────────────────────────────────────────────────────
--
--   reporting_snapshot_page(units, financial_years, revenue_since, expense_since,
--                           revenue_after_seq, revenue_after_id,
--                           expense_after_seq, expense_after_id, page_documents)
--
--   * A DOCUMENT is the unit of paging, exactly as it is the unit of replacement (D-178):
--     a page never splits a document's rows.
--   * Documents are ordered by (document generation, document id): expenses.change_seq,
--     revenue_entries.change_seq. Every contribution change advances its document's own
--     generation (D-177; every line writer is expense_create/_update or the revenue RPCs,
--     each of which writes the header), so a document changed during a run reappears LATER
--     in the same ordered pass.
--   * A page returns, per dataset, up to `page_documents` documents after the cursor with
--     generation above `since`, their rows inside the requested financial years, the
--     documents themselves (id and generation — so a delta can clear a document whose rows
--     all left the requested years), and `has_more`.
--   * A first synchronisation (since = 0) lists only documents with a row in the requested
--     financial years; a delta (since > 0) lists every changed document. The client clears
--     the requested scope before a first synchronisation, so nothing it holds can be left
--     stale by a document that is not listed.
--   * The page whose datasets BOTH report has_more = false certifies the run: its snapshot
--     identity and server time are the evidence the markers carry. Because the pass is
--     ordered by generation, the cache then equals that page's snapshot — every document
--     changed after an earlier page was delivered again, later, at its newer version — with
--     exactly the residual late-commit hazard the safety overlap already mitigates
--     (ARCHITECTURE §5.2, D-180).
--   * Authority is decided per unit on every page: `reports.view` ∩ `revenue.view` ∩
--     `expense.view.all` (D-164, D-187), SECURITY INVOKER over the two projections, so it
--     can return nothing the caller could not already select. The client abandons a run
--     whose authorised set changes between pages.
--
-- Indexes, each for one read this transport makes:
--   expenses (org_id, change_seq, id)             — the ordered expense document pass
--   revenue_entries (org_id, change_seq, id)      — the ordered revenue document pass
--   expense_period_allocations (expense_id)       — a page's rows by document
--
-- `reporting_newer_than` asks the same question as before over document generations, so
-- it uses the first two indexes instead of evaluating every historical row.

begin;

create index if not exists expenses_org_change_seq_idx
  on public.expenses (org_id, change_seq, id);
create index if not exists revenue_entries_org_change_seq_idx
  on public.revenue_entries (org_id, change_seq, id);
create index if not exists expense_period_allocations_expense_idx
  on public.expense_period_allocations (expense_id);

revoke all on function public.reporting_snapshot(uuid[], bigint, bigint)
  from public, anon, authenticated;
drop function public.reporting_snapshot(uuid[], bigint, bigint);

create or replace function public.reporting_snapshot_page(
  p_business_unit_ids uuid[],
  p_financial_years   integer[],
  p_revenue_since     bigint  default 0,
  p_expense_since     bigint  default 0,
  p_revenue_after_seq bigint  default null,
  p_revenue_after_id  uuid    default null,
  p_expense_after_seq bigint  default null,
  p_expense_after_id  uuid    default null,
  p_page_documents    integer default 1000
) returns jsonb
language sql
volatile
security invoker
set search_path = public, pg_temp
as $fn$
  with requested as (
    select distinct u as business_unit_id
      from unnest(coalesce(p_business_unit_ids, '{}'::uuid[])) as u
     where u is not null
  ),
  authority as (
    select r.business_unit_id,
           public.has_capability('reports.view', r.business_unit_id)
             and public.has_capability('revenue.view', r.business_unit_id)
             and public.has_capability('expense.view.all', r.business_unit_id)
             as reporting_authorised
      from requested r
  ),
  params as (
    select array(select a.business_unit_id from authority a where a.reporting_authorised)
             as units,
           array(select distinct y from unnest(coalesce(p_financial_years, '{}'::int[])) y
                  where y is not null) as years,
           least(greatest(coalesce(p_page_documents, 1000), 1), 2000) as n,
           coalesce(p_revenue_since, 0) as rev_since,
           coalesce(p_expense_since, 0) as exp_since
  ),
  -- ── Expenses ──────────────────────────────────────────────────────────────────────
  exp_cand as (
    select c.expense_id as id, c.document_change_seq as seq
      from public.expense_period_contributions c
     where c.business_unit_id = any ((select units from params)::uuid[])
       and c.document_change_seq > (select exp_since from params)
       and (c.document_change_seq, c.expense_id)
             > (coalesce(p_expense_after_seq, -1),
                coalesce(p_expense_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
       and ((select exp_since from params) > 0
            or (case when extract(month from c.pnl_date) >= 4
                     then extract(year from c.pnl_date)
                     else extract(year from c.pnl_date) - 1 end)::int
                 = any ((select years from params)::int[]))
     order by c.document_change_seq, c.expense_id
     limit (select n * 4 + 1 from params)
  ),
  exp_docs as (
    select d.id, d.seq
      from (select distinct id, seq from exp_cand) d
     order by d.seq, d.id
     limit (select n from params)
  ),
  exp_rows as (
    select c.*
      from public.expense_period_contributions c
     where c.expense_id in (select id from exp_docs)
       and c.business_unit_id = any ((select units from params)::uuid[])
       and (case when extract(month from c.pnl_date) >= 4
                 then extract(year from c.pnl_date)
                 else extract(year from c.pnl_date) - 1 end)::int
             = any ((select years from params)::int[])
  ),
  -- ── Revenue ───────────────────────────────────────────────────────────────────────
  rev_cand as (
    select c.revenue_entry_id as id, c.change_seq as seq
      from public.revenue_period_contributions c
     where c.business_unit_id = any ((select units from params)::uuid[])
       and c.change_seq > (select rev_since from params)
       and (c.change_seq, c.revenue_entry_id)
             > (coalesce(p_revenue_after_seq, -1),
                coalesce(p_revenue_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
       and ((select rev_since from params) > 0
            or (case when extract(month from c.pnl_date) >= 4
                     then extract(year from c.pnl_date)
                     else extract(year from c.pnl_date) - 1 end)::int
                 = any ((select years from params)::int[]))
     order by c.change_seq, c.revenue_entry_id
     limit (select n * 4 + 1 from params)
  ),
  rev_docs as (
    select d.id, d.seq
      from (select distinct id, seq from rev_cand) d
     order by d.seq, d.id
     limit (select n from params)
  ),
  rev_rows as (
    select c.*
      from public.revenue_period_contributions c
     where c.revenue_entry_id in (select id from rev_docs)
       and c.business_unit_id = any ((select units from params)::uuid[])
       and (case when extract(month from c.pnl_date) >= 4
                 then extract(year from c.pnl_date)
                 else extract(year from c.pnl_date) - 1 end)::int
             = any ((select years from params)::int[])
  )
  select jsonb_build_object(
    -- The MVCC snapshot this page was read from, and the server's own time for it. The
    -- final page's pair is the run's evidence (D-188, D-320).
    'snapshot_id', pg_current_snapshot()::text,
    'server_time', now(),
    'page_documents', (select n from params),
    'units', coalesce((
      select jsonb_agg(jsonb_build_object(
               'business_unit_id',     a.business_unit_id,
               'reporting_authorised', a.reporting_authorised)
             order by a.business_unit_id)
        from authority a), '[]'::jsonb),
    'revenue', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.change_seq, r.revenue_entry_id, r.id)
        from rev_rows r), '[]'::jsonb),
    'revenue_documents', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq) order by d.seq, d.id)
        from rev_docs d), '[]'::jsonb),
    'revenue_has_more',
      (select count(*) from rev_cand) > (select n * 4 from params)
      or (select count(distinct id) from rev_cand) > (select n from params),
    'expense', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.document_change_seq, x.expense_id, x.id)
        from exp_rows x), '[]'::jsonb),
    'expense_documents', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq) order by d.seq, d.id)
        from exp_docs d), '[]'::jsonb),
    'expense_has_more',
      (select count(*) from exp_cand) > (select n * 4 from params)
      or (select count(distinct id) from exp_cand) > (select n from params))
$fn$;

comment on function public.reporting_snapshot_page(
  uuid[], integer[], bigint, bigint, bigint, uuid, bigint, uuid, integer) is
  'One bounded page of the canonical reporting transport (D-320). Documents are paged in '
  '(generation, id) order and never split; the page on which both datasets report '
  'has_more = false certifies the run. D-164 authority per unit, SECURITY INVOKER over the '
  'two reporting projections. Canonical facts only - no derived P&L arithmetic.';

create or replace function public.reporting_newer_than(
  p_business_unit_ids uuid[],
  p_revenue_since     bigint default 0,
  p_expense_since     bigint default 0
) returns jsonb
language sql
volatile
security invoker
set search_path = public, pg_temp
as $fn$
  with requested as (
    select distinct u as business_unit_id
      from unnest(coalesce(p_business_unit_ids, '{}'::uuid[])) as u
     where u is not null
  ),
  authority as (
    select r.business_unit_id,
           public.has_capability('reports.view', r.business_unit_id)
             and public.has_capability('revenue.view', r.business_unit_id)
             and public.has_capability('expense.view.all', r.business_unit_id)
             as reporting_authorised
      from requested r
  ),
  units as (
    select array(select a.business_unit_id from authority a where a.reporting_authorised)
             as ids
  )
  select jsonb_build_object(
    'server_time', now(),
    'revenue_newer', exists (
      select 1 from public.revenue_period_contributions c
       where c.business_unit_id = any ((select ids from units)::uuid[])
         and c.change_seq > coalesce(p_revenue_since, 0)),
    'expense_newer', exists (
      select 1 from public.expense_period_contributions p
       where p.business_unit_id = any ((select ids from units)::uuid[])
         and p.document_change_seq > coalesce(p_expense_since, 0)))
$fn$;

revoke all on function public.reporting_snapshot_page(
  uuid[], integer[], bigint, bigint, bigint, uuid, bigint, uuid, integer)
  from public, anon;
grant execute on function public.reporting_snapshot_page(
  uuid[], integer[], bigint, bigint, bigint, uuid, bigint, uuid, integer)
  to authenticated;
revoke all on function public.reporting_newer_than(uuid[], bigint, bigint)
  from public, anon;
grant execute on function public.reporting_newer_than(uuid[], bigint, bigint)
  to authenticated;

-- ── Invariants ─────────────────────────────────────────────────────────────────────
do $inv$
declare
  r            record;
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
    'expense_visible_units', 'may_read_expense',
    'storage_expense_id', 'may_read_expense_attachments',
    'storage_revenue_id', 'may_read_revenue_attachments',
    'may_attach_to_expense', 'may_attach_to_revenue',
    'attachment_object_is_registered',
    'attachment_register', 'revenue_attachment_register',
    'revenue_tax_rule_create', 'revenue_tax_rule_end_date',
    'revenue_create', 'revenue_update', 'revenue_void',
    'revenue_category_unit',
    'reporting_primitives', 'reporting_snapshot_page', 'reporting_newer_than',
    'owner_create', 'owner_share_set',
    'owner_family_member_create', 'owner_family_member_end',
    'owner_movement_create', 'owner_movement_update', 'owner_movement_void',
    'owner_ledger_snapshot', 'owner_settlement_start_set'];
begin
  -- Both reporting transports: SECURITY INVOKER, one SQL statement, a pinned search_path,
  -- the D-164 intersection, no role name, no base table, no float, no derived P&L.
  for r in
    select p.proname, p.prosecdef, l.lanname, p.prosrc, p.proconfig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and p.proname in ('reporting_snapshot_page', 'reporting_newer_than')
  loop
    if r.prosecdef then
      raise exception '% must be SECURITY INVOKER', r.proname;
    end if;
    if r.lanname <> 'sql' then
      raise exception '% must be one SQL statement (one MVCC snapshot)', r.proname;
    end if;
    if r.proconfig is null
       or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
      raise exception '% must pin search_path', r.proname;
    end if;
    if position('''reports.view''' in r.prosrc) = 0
       or position('''revenue.view''' in r.prosrc) = 0
       or position('''expense.view.all''' in r.prosrc) = 0 then
      raise exception '% lost part of the D-164 intersection', r.proname;
    end if;
    if r.prosrc ~* '\m(owner|manager|accountant|data_entry)\M' then
      raise exception '% branches on a role name', r.proname;
    end if;
    if r.prosrc ~* '\m(from|join)\s+public\.(expenses|expense_allocations|expense_period_allocations|revenue_entries|revenue_components)\M' then
      raise exception '% reads a financial base table', r.proname;
    end if;
    if r.prosrc ~* '\m(float|real|double\s+precision|numeric)\M'
       or r.prosrc ~* '\m(net_sales|operating_profit|margin|rate_bp\s*[*/])\M' then
      raise exception '% performs arithmetic a reporting transport must not', r.proname;
    end if;
  end loop;

  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'reporting_snapshot') then
    raise exception 'the unbounded reporting_snapshot still exists';
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
end $inv$;

commit;
