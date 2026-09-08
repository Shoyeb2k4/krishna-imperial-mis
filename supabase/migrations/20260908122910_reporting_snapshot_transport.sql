-- Phase 5 Slice 6 corrective · one authoritative reporting snapshot per synchronisation.
--
-- **The defect this closes, proven before it was closed.** Slice 4's reporting delta ran
-- one HTTP query per dataset:
--
--     t0  GET revenue_period_contributions?change_seq=gt.X    -> snapshot A
--     t1  ... ordinary concurrent financial writes ...
--     t2  GET expense_period_contributions?change_seq=gt.Y    -> snapshot B
--
-- Two statements are two MVCC snapshots. Between them a sale and a cost can both be
-- recorded, and the cache then holds revenue as it stood at A beside expenses as they
-- stood at B. There is no instant at which the hotel's books looked like that, so the
-- pair is not a snapshot of anything — and nothing in the stored evidence could say so.
--
-- Two further findings made the evidence unable to express coherence even when it held:
--
--   * the certified generation was `max(change_seq)` over the **rows the delta returned**,
--     which is a property of the data rather than a boundary the server stated. It cannot
--     distinguish "expenses complete through 19658 and unchanged since" from "expenses
--     complete through 19658 and possibly stale after";
--   * `reporting_coverage_markers.server_confirmed_at` existed and **no writer ever set
--     it**, so there was no server-confirmed time at all.
--
-- Measured on this project from one unchanging server state: revenue's newest document
-- sat at change_seq 19981 and expenses' at 19658, so a run certified the two sides to
-- different numbers with no way to tell a coherent pair from an incoherent one.
--
-- ── What replaces it ─────────────────────────────────────────────────────────
--
-- `reporting_snapshot` returns **both datasets from one SQL statement**, so both come
-- from one MVCC snapshot by construction rather than by timing. With them it returns the
-- snapshot's own identity and the server's own clock, from that same statement — never a
-- second `select now()` afterwards, which would describe a different moment.
--
-- ── What this is not ─────────────────────────────────────────────────────────
--
-- It is **synchronisation transport**, not the P&L boundary. It returns canonical
-- contribution facts and no derived arithmetic: no tax re-rating, no Net Sales, no
-- Operating Profit, no margin. `reporting_primitives` remains the authoritative
-- aggregation core (D-184, D-187) and is untouched.
--
-- ── `change_seq` is a cursor, not a clock ────────────────────────────────────
--
-- A sequence value is allocated when a row is written and becomes visible only when its
-- transaction commits, so `change_seq <= G` does **not** mean "everything ≤ G was visible
-- here" (ARCHITECTURE §5.2). This function therefore states the snapshot identity for
-- coherence and leaves `change_seq` doing the one job it can do honestly: telling the next
-- delta where to resume, re-read below its watermark by the client's safety overlap. The
-- two concepts stay separate and neither is asked to be the other.

create or replace function public.reporting_snapshot(
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
  -- D-164's per-unit reporting rule, the same three capabilities the P&L boundary
  -- enforces (D-187). A unit the caller may not report on contributes no rows and is
  -- never certified, so the cache cannot hold facts for a report that would be refused.
  --
  -- The **consolidated** unscoped rule is deliberately not applied here: this fetches one
  -- property's facts at a time, and whether several of them may be added together is a
  -- question the report boundary answers, not the transport.
  authority as (
    select r.business_unit_id,
           public.has_capability('reports.view', r.business_unit_id)
             and public.has_capability('revenue.view', r.business_unit_id)
             and public.has_capability('expense.view.all', r.business_unit_id)
             as reporting_authorised
      from requested r
  )
  select jsonb_build_object(
    -- The MVCC snapshot these facts jointly represent. Opaque to the client, identical
    -- across every coverage segment this response certifies, and different for the next
    -- run — which is all a coherence check needs.
    'snapshot_id', pg_current_snapshot()::text,

    -- The server's own transaction timestamp, from this statement. `now()` rather than
    -- `clock_timestamp()`: PostgREST runs one RPC in one transaction, so `now()` is the
    -- moment this snapshot was taken, and it does not drift between the two datasets
    -- below the way a per-row clock read would.
    'server_time', now(),

    'units', coalesce((
      select jsonb_agg(jsonb_build_object(
               'business_unit_id',     a.business_unit_id,
               'reporting_authorised', a.reporting_authorised)
             order by a.business_unit_id)
        from authority a), '[]'::jsonb),

    'revenue', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.change_seq)
        from public.revenue_period_contributions c
        join authority a
          on a.business_unit_id = c.business_unit_id and a.reporting_authorised
       where c.change_seq > coalesce(p_revenue_since, 0)), '[]'::jsonb),

    'expense', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.change_seq)
        from public.expense_period_contributions p
        join authority a
          on a.business_unit_id = p.business_unit_id and a.reporting_authorised
       where p.change_seq > coalesce(p_expense_since, 0)), '[]'::jsonb))
$fn$;

comment on function public.reporting_snapshot(uuid[], bigint, bigint) is
  'Reporting synchronisation transport. Returns both canonical contribution datasets for '
  'the named business units from ONE statement, so they share one MVCC snapshot, together '
  'with that snapshot''s identity and the server''s own transaction time. security invoker '
  'over the two security_barrier projections, gated per unit on D-164''s three reporting '
  'capabilities. Carries canonical facts only — no derived P&L arithmetic and no tax '
  're-rating. change_seq remains a delta cursor and is never a commit-order clock.';

-- ── Is there anything newer for this scope? ──────────────────────────────────
--
-- The second freshness condition needs a check that is **relevant to reporting facts**.
-- Comparing a local watermark against the global sequence head would report a P&L as
-- outdated because somebody edited a vendor or a tax rule, which changed no contribution.
-- This asks the only question that matters — does a contribution I may report on carry a
-- generation above my cursor — over the indexed `change_seq`, and returns no financial
-- figures at all.

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
  )
  select jsonb_build_object(
    'server_time', now(),
    'revenue_newer', exists (
      select 1 from public.revenue_period_contributions c
        join authority a
          on a.business_unit_id = c.business_unit_id and a.reporting_authorised
       where c.change_seq > coalesce(p_revenue_since, 0)),
    'expense_newer', exists (
      select 1 from public.expense_period_contributions p
        join authority a
          on a.business_unit_id = p.business_unit_id and a.reporting_authorised
       where p.change_seq > coalesce(p_expense_since, 0)))
$fn$;

comment on function public.reporting_newer_than(uuid[], bigint, bigint) is
  'Whether canonical reporting contributions the caller may report on carry a generation '
  'above the given cursors. Scope-relevant by construction: a master, tax-configuration '
  'or audit-only mutation changes no contribution and therefore cannot mark a P&L newer. '
  'Returns no financial figures.';

revoke all on function public.reporting_snapshot(uuid[], bigint, bigint)
  from public, anon;
revoke all on function public.reporting_newer_than(uuid[], bigint, bigint)
  from public, anon;
grant execute on function public.reporting_snapshot(uuid[], bigint, bigint)
  to authenticated;
grant execute on function public.reporting_newer_than(uuid[], bigint, bigint)
  to authenticated;

-- ── Invariants, restated over both new functions ─────────────────────────────

do $inv$
declare
  r record;
  v_src text;
begin
  for r in
    select p.proname, p.prosecdef, l.lanname, p.prosrc
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and p.proname in ('reporting_snapshot', 'reporting_newer_than')
  loop
    v_src := r.prosrc;

    if r.prosecdef then
      raise exception '% became security definer', r.proname;
    end if;
    if r.lanname <> 'sql' then
      raise exception
        '% is no longer a single sql statement; two statements under READ COMMITTED '
        'would take two snapshots, which is the defect this corrective closes', r.proname;
    end if;
    if (length(regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g'))
        - length(replace(regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g'), ';', ''))) > 1 then
      raise exception '% contains more than one statement', r.proname;
    end if;

    -- The whole reporting authorization contract, per unit (D-164, D-187).
    if v_src !~ 'reports\.view' or v_src !~ 'revenue\.view'
       or v_src !~ 'expense\.view\.all' then
      raise exception '% does not enforce the three reporting capabilities', r.proname;
    end if;
    if v_src ~ 'expense\.view\.own' then
      raise exception '% accepts expense.view.own for a reporting read', r.proname;
    end if;
    -- Slice 7 owns export and print, and a transport must not quietly require them.
    if v_src ~ 'reports\.export' or v_src ~ 'reports\.print' then
      raise exception '% requires an unbuilt Phase 7 capability', r.proname;
    end if;

    if v_src ~* '\mowner\M' or v_src ~* '\mmanager\M' or v_src ~* '\maccountant\M'
       or v_src ~* '\mdata_entry\M' then
      raise exception '% branches on a role name rather than a capability', r.proname;
    end if;

    -- Projections only. A transport that reached a base table would be a second read
    -- boundary nobody reviewed (D-062).
    if v_src ~ '\mpublic\.expenses\M'
       or v_src ~ '\mpublic\.revenue_entries\M'
       or v_src ~ '\mpublic\.revenue_components\M'
       or v_src ~ '\mpublic\.expense_allocations\M'
       or v_src ~ '\mpublic\.expense_period_allocations\M' then
      raise exception '% reads a financial base table directly', r.proname;
    end if;

    -- Transport, not arithmetic. No derived P&L figure may be computed here.
    if v_src ~* '\mnet_sales\M' or v_src ~* '\moperating_profit\M'
       or v_src ~* '\mmargin\M' or v_src ~ 'revenue_tax_rates' then
      raise exception '% derives P&L arithmetic or reaches for tax configuration',
        r.proname;
    end if;
    if v_src ~* '\mfloat\M' or v_src ~* '\mreal\M' or v_src ~* 'double precision' then
      raise exception '% uses binary floating point', r.proname;
    end if;

    if v_src !~ 'coalesce\(p_business_unit_ids' then
      raise exception
        'an omitted unit set could widen % to the whole organisation', r.proname;
    end if;
  end loop;
end $inv$;

-- The snapshot function specifically: both datasets in the one statement, and the server's
-- own time and snapshot identity carried with them.
do $inv$
declare v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reporting_snapshot';

  if v_src !~ 'revenue_period_contributions'
     or v_src !~ 'expense_period_contributions' then
    raise exception
      'reporting_snapshot does not read both datasets — one snapshot means both sides '
      'come from the same statement, which is the whole of the corrective';
  end if;
  if v_src !~ 'pg_current_snapshot' then
    raise exception
      'reporting_snapshot states no snapshot identity, so nothing downstream can prove '
      'that revenue and expense facts represent one authoritative moment';
  end if;
  if v_src !~ '\mnow\(\)' then
    raise exception
      'reporting_snapshot returns no server time; a device clock is not evidence about a '
      'server''s state';
  end if;
end $inv$;

-- The boundary is otherwise untouched: no new grant, no raw table access, anon nothing.
do $inv$
declare v_bad text;
begin
  if has_function_privilege('anon', 'public.reporting_snapshot(uuid[], bigint, bigint)', 'EXECUTE')
     or has_function_privilege('anon', 'public.reporting_newer_than(uuid[], bigint, bigint)', 'EXECUTE') then
    raise exception 'anon can call a reporting transport';
  end if;
  if not has_function_privilege('authenticated', 'public.reporting_snapshot(uuid[], bigint, bigint)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.reporting_newer_than(uuid[], bigint, bigint)', 'EXECUTE') then
    raise exception 'the reporting transport is not callable by an authenticated client';
  end if;
  if has_table_privilege('authenticated', 'public.expenses', 'SELECT')
     or has_table_privilege('authenticated', 'public.revenue_entries', 'SELECT')
     or has_table_privilege('authenticated', 'public.revenue_components', 'SELECT') then
    raise exception 'a client role can read a financial base table directly';
  end if;

  select string_agg(format('%s:%s:%s', grantee, table_name, privilege_type), ', ')
    into v_bad
    from information_schema.role_table_grants
   where table_schema = 'public'
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_bad is not null then
    raise exception 'a client role holds a write privilege in public: %', v_bad;
  end if;
end $inv$;

-- And `reporting_primitives` is unchanged by all of this: the P&L boundary still enforces
-- the contract the Slice 5 corrective gave it.
do $inv$
declare v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reporting_primitives';
  if v_src is null then
    raise exception 'reporting_primitives has gone';
  end if;
  if v_src !~ 'reports\.view' or v_src !~ 'has_unscoped_capability' then
    raise exception
      'reporting_primitives lost the reporting authorization contract while a transport '
      'was added beside it (D-187)';
  end if;
end $inv$;
