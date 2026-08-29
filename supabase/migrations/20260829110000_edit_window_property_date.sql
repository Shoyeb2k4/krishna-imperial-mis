-- ─────────────────────────────────────────────────────────────────────────────
-- 0033 · The edit window counts days under the property's date, not the server's
--
-- Found by the Phase 3 acceptance, in the one place the whole schema used a wall clock.
--
-- `expense_update` decided the 7-day edit window with `current_date - business_date`.
-- `current_date` is the **database session's** calendar date, and this database's session
-- timezone is UTC:
--
--     select current_setting('TimeZone')        →  UTC
--
-- The properties are `Asia/Kolkata` (UTC+05:30) with a 05:00 business-day cut-off, so the
-- UTC calendar date lags the property's business date for part of every night. Measured
-- against the real configuration, `current_date` disagreed with the property's own
-- business date for **30 minutes every day, 05:00–05:29 IST**, and during that window an
-- entry that was D+8 old was counted as D+7 and **wrongly accepted for edit**.
--
-- Thirty minutes is not the point. The window is narrow only because the +05:30 offset
-- and the 05:00 cut-off happen to cancel out, and both are *configuration* (spec §9): a
-- unit with a midnight cut-off is misjudged for **5½ hours a day**, and a unit in a zone
-- west of UTC would be misjudged in the opposite direction, refusing edits that are still
-- inside the window. Correctness must not rest on a coincidence between two independently
-- editable settings.
--
-- The rule, stated once and for good (D-065, amended):
--
--     elapsed = (the property's business date **now**) − business_date, in whole
--               calendar days
--     elapsed <= edit_window_days   permitted
--     elapsed >  edit_window_days   refused KM021
--
-- and "the property's business date now" is derived exactly as spec §9 derives it for a
-- new entry — `now()` in the unit's IANA timezone, stepped back one calendar day when the
-- local time is before that unit's cut-off. This is the same rule
-- `BusinessDate.fromInstant` applies on the client, so the two layers agree by
-- construction rather than by luck, and an expense recorded this second always has
-- `elapsed = 0` instead of having already spent a day of its window.
--
-- A shared bill touches more than one property, and each property's books are protected
-- separately (the same reasoning as D-034's per-period checks). The window must be open
-- for **every** unit the document charges, so the comparison uses the greatest business
-- date among them — the strictest reading, never the most permissive.
--
-- No API surface changes: both helpers live in `app`, which `authenticated` cannot reach,
-- and `expense_update` is restated with two lines different. The assertion at the foot
-- proves the restatement did not disturb its grant.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── The rule itself, as a pure function of an instant ────────────────────────
--
-- Taking the instant as a parameter rather than reading the clock is what makes the rule
-- testable at 04:59, at 05:00, at 23:59 and at 00:01 without waiting for those times to
-- arrive (spec §33, D-019). `stable` rather than `immutable` because `at time zone` on a
-- named zone depends on the timezone database.
create or replace function app.business_date_at(
  p_instant   timestamptz,
  p_timezone  text,
  p_cutoff    time
)
returns date
language sql
stable
set search_path = ''
as $$
  select case
           when (p_instant at time zone p_timezone)::time < p_cutoff
           then (p_instant at time zone p_timezone)::date - 1
           else (p_instant at time zone p_timezone)::date
         end;
$$;

comment on function app.business_date_at(timestamptz, text, time) is
  'Spec §9 / D-019: the business date an instant falls in, under a unit''s timezone and '
  'cut-off. The server half of BusinessDate.fromInstant.';

-- ── "Today", for one expense document ────────────────────────────────────────
--
-- The greatest current business date among the properties the document charges, so a
-- shared bill is editable only while the window is open for all of them. The coalesce is
-- unreachable while `SUM(allocations) = total` holds — a document always has at least one
-- line — and is there so a future caller cannot get a silent NULL, which would compare
-- as "not greater than the window" and disable the guard entirely.
create or replace function app.expense_window_today(p_expense_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select max(app.business_date_at(now(), bu.timezone, bu.business_day_cutoff))
       from public.expense_allocations a
       join public.business_units bu on bu.id = a.business_unit_id
      where a.expense_id = p_expense_id),
    (select app.business_date_at(now(), o.timezone, time '00:00')
       from public.expenses e
       join public.organizations o on o.id = e.org_id
      where e.id = p_expense_id));
$$;

comment on function app.expense_window_today(uuid) is
  'The property business date the edit window is measured against. Greatest across the '
  'units a shared document charges, so every property''s window must still be open.';

-- ── Neither helper is reachable from a client ────────────────────────────────
--
-- 0024 set `alter default privileges in schema app revoke execute on functions from
-- public`, and it did **not** cover these two. `ALTER DEFAULT PRIVILEGES` applies only
-- to objects created by the role that ran it, so it silently stops protecting anything
-- created through a different connection — which is exactly how a function acquires the
-- default `PUBLIC EXECUTE` grant without anybody choosing it. The assertion at the foot
-- of this file caught that on the first attempt to apply it, and refused the migration.
--
-- The revoke is therefore explicit and belongs to the same file that creates the
-- functions, so it cannot depend on who is holding the connection. `revoke all on schema
-- app from public` (0001) remains the first lock; this is the second.
revoke all on function app.business_date_at(timestamptz, text, time) from public, anon, authenticated;
revoke all on function app.expense_window_today(uuid)                 from public, anon, authenticated;

-- ── `expense_update`, restated with the corrected comparison ─────────────────
create or replace function public.expense_update(
  p_id              uuid,
  p_base_row_version integer,
  p_business_date   date,
  p_total_minor     bigint,
  p_allocations     jsonb,
  p_period_start    date default null,
  p_period_end      date default null,
  p_vendor_id       uuid default null,
  p_payment_status  text default 'unpaid',
  p_payment_date    date default null,
  p_payment_method_id uuid default null,
  p_reference_number text default null,
  p_notes           text default null,
  p_tax_amount_minor bigint default null,
  p_mutation_id     uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor   uuid;
  v_org     uuid;
  v_replay  jsonb;
  v_result  jsonb;
  v_before  jsonb;
  e         record;
  v_window  integer;
  v_unit    uuid;
  v_today   date;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Permission before existence (D-046): a caller who may edit nothing anywhere learns
  -- nothing about which documents exist.
  --
  -- **Either** form counts. An Accountant holds `expense.edit.all` and not
  -- `expense.edit.own`, so asking for the latter specifically refused the one role that
  -- exists to correct other people's entries. Caught by the live edit-window test.
  perform app.require_any_edit_capability();

  select * into e from public.expenses where id = p_id and org_id = v_org;
  if e.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That expense does not exist.',
      jsonb_build_object('expense_id', p_id));
  end if;

  if e.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This expense has been voided. Corrections are made by entering a new expense.',
      jsonb_build_object('expense_id', p_id));
  end if;

  -- Ownership, per unit, and the edit window.
  for v_unit in
    select distinct a.business_unit_id from public.expense_allocations a
     where a.expense_id = p_id
  loop
    if not public.has_capability('expense.edit.all', v_unit) then
      perform app.require_capability('expense.edit.own', v_unit);
      if e.created_by <> v_actor then
        perform app.refuse('KM001', 'missing_capability',
          'You may only change entries you recorded yourself.',
          jsonb_build_object('expense_id', p_id));
      end if;
    end if;
  end loop;

  -- Configuration, not a constant (spec §13.3). Absent, the seeded default applies.
  select coalesce((os.value)::text::integer, 7) into v_window
    from public.org_settings os
   where os.org_id = v_org and os.key = 'edit_window_days';

  -- "Today" is the property's current **business date**, never the database session's
  -- calendar date. The session runs in UTC, so `current_date` lagged the property date
  -- for part of every night and quietly granted an extra day of window (see 0033).
  v_today := app.expense_window_today(p_id);

  -- Inclusive of its last day: a business date of D is editable on D+7 and refused on
  -- D+8, counted in whole calendar days under the property's own business-date policy.
  -- `transaction.correct.beyond_window` lifts the *age* rule and nothing else — the
  -- period lock is checked afterwards and is never bypassed.
  if (v_today - e.business_date) > coalesce(v_window, 7)
     and not public.has_capability_anywhere('transaction.correct.beyond_window') then
    perform app.refuse('KM021', 'edit_window_expired',
      format('This entry is more than %s days old and can no longer be changed here.',
             coalesce(v_window, 7)),
      jsonb_build_object('business_date', e.business_date,
                         'days_elapsed', v_today - e.business_date,
                         'window_days', coalesce(v_window, 7)));
  end if;

  -- Concurrency, after authority and state, so a caller without permission never learns
  -- the current version (D-021, D-046).
  if e.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'Somebody else changed this expense while you were working on it.',
      jsonb_build_object('expected', p_base_row_version, 'actual', e.row_version));
  end if;

  perform app.validate_expense_allocations(
    v_org, p_business_date, p_period_start, p_period_end,
    p_total_minor, p_allocations);

  v_before := to_jsonb(e);

  -- The old lines stop being live. Their historical usage is untouched (see 0032).
  perform app.record_master_usage(v_org, 'expense_category', a.category_id,
                                  e.business_date, 0, -1)
     from public.expense_allocations a where a.expense_id = p_id;

  delete from public.expense_period_allocations where expense_id = p_id;
  delete from public.expense_allocations        where expense_id = p_id;

  update public.expenses
     set business_date = p_business_date,
         accounting_period_start = p_period_start,
         accounting_period_end   = p_period_end,
         total_amount_minor = p_total_minor,
         vendor_id = p_vendor_id,
         payment_status = p_payment_status,
         payment_date = p_payment_date,
         payment_method_id = p_payment_method_id,
         reference_number = p_reference_number,
         notes = p_notes,
         tax_amount_minor = p_tax_amount_minor
   where id = p_id;

  perform app.write_expense_allocations(
    v_org, p_id, p_business_date, p_period_start, p_period_end, p_allocations);

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'expense', 'entity_id', p_id,
    'row_version', (select row_version from public.expenses where id = p_id));

  perform app.write_audit(v_org, 'expense', p_id, 'expense_edited', v_actor,
    v_before, to_jsonb((select e2 from public.expenses e2 where e2.id = p_id)),
    null, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'expense', p_id,
                               'update', v_result);
end;
$$;

-- ── The restatement did not change who may call it, and added nothing ────────
do $$
declare
  v_leaked text;
begin
  -- The reviewed API surface is unchanged: `expense_update` still callable, both new
  -- helpers unreachable from any client role.
  if not has_function_privilege('authenticated', 'public.expense_update(uuid,integer,'
       'date,bigint,jsonb,date,date,uuid,text,date,uuid,text,text,bigint,uuid)',
       'EXECUTE') then
    raise exception
      'expense_update lost its EXECUTE grant to authenticated during the restatement';
  end if;

  select string_agg(format('%s(%s) → %s', p.proname,
                           pg_get_function_identity_arguments(p.oid), r.rolname), ', ')
    into v_leaked
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   cross join (values ('anon'), ('authenticated')) as r(rolname)
   where n.nspname = 'app'
     and p.proname in ('business_date_at', 'expense_window_today')
     and has_function_privilege(r.rolname, p.oid, 'EXECUTE');
  if v_leaked is not null then
    raise exception 'app helper reachable by a client role: %', v_leaked;
  end if;
end;
$$;

-- ── The cut-off boundaries, asserted rather than assumed ────────────────────
--
-- Spec §33 requires 04:59, 05:00, 23:59 and 00:01 to be tested. They are tested here, in
-- the database, against the function the guard actually calls — so the rule is proven at
-- the boundary on every deploy rather than only in the Dart suite.
do $$
declare
  v_tz   constant text := 'Asia/Kolkata';
  v_cut  constant time := '05:00';
  v_case record;
begin
  for v_case in
    select * from (values
      -- instant (property-local wall clock)      expected business date   why
      (timestamptz '2026-06-16 04:59+05:30', date '2026-06-15', 'one minute before cut-off'),
      (timestamptz '2026-06-16 05:00+05:30', date '2026-06-16', 'exactly at the cut-off'),
      (timestamptz '2026-06-16 00:01+05:30', date '2026-06-15', 'just after midnight'),
      (timestamptz '2026-06-16 23:59+05:30', date '2026-06-16', 'last minute of the day'),
      (timestamptz '2026-06-16 01:00+05:30', date '2026-06-15', 'the rooftop 01:00 case, spec §9'),
      -- The half hour this migration exists to fix: property date 16 June, UTC date 15.
      (timestamptz '2026-06-16 05:15+05:30', date '2026-06-16', 'the window UTC got wrong')
    ) as t(instant, expected, why)
  loop
    if app.business_date_at(v_case.instant, v_tz, v_cut) <> v_case.expected then
      raise exception 'business_date_at(%) = %, expected % (%)',
        v_case.instant, app.business_date_at(v_case.instant, v_tz, v_cut),
        v_case.expected, v_case.why;
    end if;
  end loop;

  -- And the defect itself, stated as an assertion: at 05:15 IST the server's own
  -- calendar date is *not* the property's business date. If this ever stops being true
  -- the session timezone has changed, and this migration's reasoning must be re-read.
  if (timestamptz '2026-06-16 05:15+05:30' at time zone 'UTC')::date
     = app.business_date_at(timestamptz '2026-06-16 05:15+05:30', v_tz, v_cut) then
    raise exception
      'the UTC calendar date and the property business date no longer differ at 05:15 '
      'IST — re-read migration 0033 before trusting current_date anywhere';
  end if;
end;
$$;
