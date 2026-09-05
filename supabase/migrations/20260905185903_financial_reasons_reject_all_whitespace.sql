-- A mandatory financial reason rejects every whitespace-only value, on both engines
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.2 · pre-Slice-11 corrective
--
-- `20260905142059_correction_reason_rejects_all_whitespace` established the rule for a
-- business-date correction reason and recorded, deliberately unfixed, that the two void
-- boundaries had the same weakness. This closes it, and makes the rule canonical rather
-- than repeated.
--
-- **The defect, proven against the shipped functions before anything was changed.**
-- One-argument `btrim`/`trim` strips **spaces only** — not tabs, not newlines, not a
-- carriage return:
--
--     expense_void(p_reason => E'\t')   applied, row_version 3
--                                       audit reason: "\t"
--     revenue_void(p_reason => E'\t')   applied, row_version 2
--                                       revenue_entries.void_reason: "\t"
--
-- A financial document was permanently voided, and the only record of *why* is a tab.
-- Spec §14 requires corrections to carry a reason; a value that says nothing is not one,
-- and the rule that a void always states why was satisfiable by pressing one key.
--
-- Repository forms before this migration, all spaces-only:
--
--     expense_void    p_reason is null or length(btrim(p_reason)) = 0
--     revenue_void    coalesce(trim(p_reason), '') = ''
--     period_reopen   btrim(coalesce(p_reason, ''))          <- see the note at the foot
--
-- ## One rule, in one place
--
-- `app.stated_reason` is the canonical normalisation: it removes every leading and
-- trailing whitespace character and returns what is left, which is the empty string when
-- nothing is. Both voids call it, so neither carries its own regex to drift from the
-- other — which is what the correction migration's own finding was about.
--
-- It is `immutable` so it can be reasoned about, and it lives in `app`, which no client
-- role can reach. It is **not** an addition to the reviewed API surface (D-044).
--
-- ## What is stored
--
-- The **normalised** reason, which is the project's existing trimming convention:
-- `period_reopen` has always stored `btrim(...)` and the correction reason stores its
-- regexp-trimmed form. Storing `'  Duplicate  '` verbatim on a void while a correction
-- stores `'Duplicate'` would be exactly the inconsistency this migration exists to
-- remove. Nothing else about the text is touched: internal spacing, punctuation and case
-- are the operator's.
--
-- ## The table constraints are tightened too, and are NOT VALID on purpose
--
-- Both tables carry a void-reason CHECK written with the same spaces-only trim, so the
-- backstop was weaker than the boundary it backs. The expression is **inlined** there
-- rather than calling the helper: a CHECK that calls a function is not re-validated when
-- the function changes, which would quietly make the constraint a comment. Inlining
-- duplicates the expression once — and the assertion at the foot proves the two forms
-- agree on a value table, so the duplication is checked rather than trusted.
--
-- They are added `NOT VALID`, which enforces the rule on every future INSERT and UPDATE
-- and does not re-check rows that already exist. That is not a shortcut; it is the only
-- available answer, and the reason is worth reading.
--
-- The probe that proved this defect voided two development fixtures with a tab as their
-- stated reason, and those two rows now hold values the new rule forbids:
--
--     expenses         0669cc5f-b547-4152-be17-bf6d688bc621  KI-EXP-26-27-000446
--     revenue_entries  01a072ec-057b-7077-bf06-59bdc874b110  KI-REV-26-27-000306
--
-- They cannot be repaired. `app.refuse_voided_mutation` refuses every update to a voided
-- financial document — including one issued as the table owner — and it was right to:
-- financial history is corrected by void and re-entry, never by rewriting a row (D-006).
-- So the choice was between rewriting voided history to make a constraint validate, and
-- enforcing the rule from here on while leaving two voided development fixtures as the
-- evidence of what was wrong. The second is obviously correct, and it is a good sign
-- rather than a bad one: two guarantees held at once, and the older one won.
--
-- Nothing else in either table violates it — those two rows are the only ones, checked.
-- The constraint is a backstop against a future writer that bypasses the RPC; no client
-- role holds UPDATE on either table, so its enforcement is not reachable from any client
-- path and is therefore asserted structurally below rather than by a live test.

create or replace function app.stated_reason(p_reason text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(coalesce(p_reason, ''), '^\s+|\s+$', '', 'g');
$$;

comment on function app.stated_reason(text) is
  'The canonical normalisation for every mandatory financial reason: all leading and '
  'trailing whitespace removed, empty when nothing remains. One-argument btrim strips '
  'spaces alone, so a lone tab satisfied the rule that a void always states why.';

revoke all on function app.stated_reason(text) from public, anon, authenticated;

-- ── Expense void ─────────────────────────────────────────────────────────────
--
-- Restated with two lines different: the reason is normalised through the helper, and the
-- normalised value is what is stored. Every other rule is the one it already had —
-- capability anywhere then per unit, period open on every period it reports into, the
-- version check after authority and state, historical usage kept and active usage
-- dropped, attachments untouched.
create or replace function public.expense_void(
  p_id               uuid,
  p_base_row_version integer,
  p_reason           text,
  p_mutation_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  v_replay jsonb;
  v_result jsonb;
  v_before jsonb;
  v_reason text;
  e        record;
  v_unit   uuid;
  v_period text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  perform app.require_capability_anywhere('expense.void');

  v_reason := app.stated_reason(p_reason);
  if length(v_reason) = 0 then
    perform app.refuse('KM008', 'reason_required',
      'A void always states why. The reason is recorded against the document.',
      jsonb_build_object('expense_id', p_id));
  end if;

  select * into e from public.expenses where id = p_id and org_id = v_org;
  if e.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That expense does not exist.',
      jsonb_build_object('expense_id', p_id));
  end if;

  if e.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This expense has already been voided.',
      jsonb_build_object('expense_id', p_id));
  end if;

  -- Scope on every unit it charges, and every period it reports into still open. A
  -- closed month refuses the void; the way back is the audited reopen workflow, and the
  -- lock is never bypassed.
  for v_unit in
    select distinct a.business_unit_id from public.expense_allocations a
     where a.expense_id = p_id
  loop
    perform app.require_capability('expense.void', v_unit);
  end loop;

  for v_unit, v_period in
    select distinct p.business_unit_id, p.pnl_period_key
      from public.expense_period_allocations p
     where p.expense_id = p_id
  loop
    perform app.require_period_open(v_period, v_unit);
  end loop;

  if e.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'Somebody else changed this expense while you were working on it.',
      jsonb_build_object('expected', p_base_row_version, 'actual', e.row_version));
  end if;

  v_before := to_jsonb(e);

  -- The immutability trigger refuses updates to an already-voided row; this is the one
  -- update that sets voided_at, and it runs while the row is still live.
  update public.expenses
     set voided_at = now(), voided_by = v_actor, void_reason = v_reason
   where id = p_id;

  -- Active references go; historical usage stays. A voided expense still happened, and
  -- the D-038 rename warning is built on that history. Attachments are untouched: the
  -- document and its evidence remain part of the record.
  perform app.record_master_usage(v_org, 'expense_category', a.category_id,
                                  e.business_date, 0, -1)
     from public.expense_allocations a where a.expense_id = p_id;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'expense', 'entity_id', p_id,
    'voided', true,
    'row_version', (select row_version from public.expenses where id = p_id));

  perform app.write_audit(v_org, 'expense', p_id, 'expense_voided', v_actor,
    v_before, to_jsonb((select e2 from public.expenses e2 where e2.id = p_id)),
    v_reason, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'expense', p_id,
                               'void', v_result);
end;
$$;

revoke all on function public.expense_void(uuid, integer, text, uuid) from public, anon;
grant execute on function public.expense_void(uuid, integer, text, uuid) to authenticated;

-- ── Revenue void ─────────────────────────────────────────────────────────────
--
-- The same two lines, and nothing else. The Slice 10 state machine is untouched: the
-- already-voided-at-a-matching-version replay stays an audited no-op, a stale one stays a
-- conflict (D-021), the document and its components and their tax snapshots all remain,
-- and KI-REV is never restated.
create or replace function public.revenue_void(
  p_id uuid, p_base_row_version integer, p_reason text, p_mutation_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_entry public.revenue_entries; v_replay jsonb;
  v_reason text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_capability_anywhere('revenue.void');

  v_reason := app.stated_reason(p_reason);
  if length(v_reason) = 0 then
    perform app.refuse('KM008', 'reason_required', 'A void must state why.', '{}'::jsonb);
  end if;

  select * into v_entry from public.revenue_entries where id = p_id and org_id = v_org;
  if not found then
    perform app.refuse('KM015', 'unknown_entity', 'That revenue entry does not exist.', '{}'::jsonb);
  end if;

  perform app.require_capability('revenue.void', v_entry.business_unit_id);
  perform app.require_period_open(v_entry.pnl_period_key, v_entry.business_unit_id);

  -- A different mutation voiding an already-voided document with a matching version is an
  -- audited no-op; a stale one is a conflict (D-021).
  if v_entry.voided_at is not null and v_entry.row_version = p_base_row_version then
    return app.remember_mutation(p_mutation_id, v_org, v_actor,
      'revenue_entry', p_id, 'void',
      jsonb_build_object('id', p_id, 'row_version', v_entry.row_version,
                         'status', 'already_voided'));
  end if;

  if v_entry.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'This revenue entry changed since you loaded it. Review the latest version before voiding.',
      jsonb_build_object('expected', p_base_row_version, 'actual', v_entry.row_version));
  end if;

  update public.revenue_entries
     set voided_at = now(), voided_by = v_actor, void_reason = v_reason,
         row_version = row_version + 1, updated_at = now(), updated_by = v_actor
   where id = p_id;

  perform app.write_audit(v_org, 'revenue_entry', p_id, 'voided', v_actor,
    to_jsonb(v_entry), jsonb_build_object('void_reason', v_reason),
    v_reason, v_entry.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'void',
    jsonb_build_object('id', p_id, 'row_version', v_entry.row_version + 1, 'status', 'voided'));
end; $$;

revoke all on function public.revenue_void(uuid, integer, text, uuid) from public, anon;
grant execute on function public.revenue_void(uuid, integer, text, uuid) to authenticated;

-- ── The backstops, tightened to the same rule ────────────────────────────────
alter table public.expenses drop constraint if exists expenses_void_has_reason;
alter table public.expenses add constraint expenses_void_has_reason
  check (voided_at is null
         or (voided_by is not null
             and length(regexp_replace(coalesce(void_reason, ''),
                                       '^\s+|\s+$', '', 'g')) > 0))
  not valid;

alter table public.revenue_entries drop constraint if exists revenue_entries_void_states_why;
alter table public.revenue_entries add constraint revenue_entries_void_states_why
  check (voided_at is null
         or (voided_by is not null
             and length(regexp_replace(coalesce(void_reason, ''),
                                       '^\s+|\s+$', '', 'g')) > 0))
  not valid;

-- ── Invariants ───────────────────────────────────────────────────────────────
do $$
declare
  v_case record;
  v_leak text;
begin
  -- The rule itself, on the values it exists for. The same table the correction-reason
  -- migration asserts, so the two boundaries are provably one standard (spec §14).
  for v_case in
    select * from (values
      (''::text            , true , 'empty'),
      ('   '               , true , 'spaces'),
      (E'\t'               , true , 'one tab, the case that got through'),
      (E'   \t  '          , true , 'spaces around a tab'),
      (E'\n'               , true , 'newline'),
      (E'\r'               , true , 'carriage return'),
      (E' \t\r\n '         , true , 'mixed whitespace'),
      (null::text          , true , 'null'),
      ('Duplicate of KI-EXP-26-27-000012', false, 'an actual reason'),
      ('  Duplicate entry  ', false, 'an actual reason, padded'),
      ('Duplicate entry for 15 June', false, 'internal spaces are content')
    ) as t(reason, must_refuse, why)
  loop
    if (length(app.stated_reason(v_case.reason)) = 0) <> v_case.must_refuse then
      raise exception 'app.stated_reason is wrong for % (%)',
        coalesce(quote_literal(v_case.reason), 'NULL'), v_case.why;
    end if;

    -- And the inlined constraint expression agrees with the helper, value for value.
    -- The duplication is deliberate — a CHECK that calls a function is not re-validated
    -- when the function changes — so it is checked rather than trusted.
    if (length(regexp_replace(coalesce(v_case.reason, ''), '^\s+|\s+$', '', 'g')) = 0)
       <> v_case.must_refuse then
      raise exception 'the inlined constraint expression disagrees for % (%)',
        coalesce(quote_literal(v_case.reason), 'NULL'), v_case.why;
    end if;
  end loop;

  -- Internal spacing is content, not whitespace to be squeezed. The operator's words are
  -- theirs; only the ends are trimmed.
  if app.stated_reason('  Duplicate  entry  ') <> 'Duplicate  entry' then
    raise exception 'stated_reason altered the text beyond trimming its ends';
  end if;

  -- The positive control: the rule that was there before fails this table on the very row
  -- it was written for. If this stops raising, one-argument btrim has changed meaning and
  -- the finding no longer reproduces.
  if length(btrim(E'\t')) = 0 then
    raise exception
      'btrim(text) now strips tabs — re-read this migration before trusting either form';
  end if;

  -- Both boundaries actually call the helper, rather than having quietly kept their own.
  if pg_get_functiondef('public.expense_void(uuid,integer,text,uuid)'::regprocedure)
       not like '%app.stated_reason(p_reason)%' then
    raise exception 'expense_void does not use the canonical reason rule';
  end if;
  if pg_get_functiondef('public.revenue_void(uuid,integer,text,uuid)'::regprocedure)
       not like '%app.stated_reason(p_reason)%' then
    raise exception 'revenue_void does not use the canonical reason rule';
  end if;

  -- The helper is internal. It is not on the reviewed API surface and must not become
  -- reachable by adding it (D-044, D-101).
  select string_agg(p.proname, ', ') into v_leak
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_leak is not null then
    raise exception 'a client role can execute functions in app: %', v_leak;
  end if;

  -- Both backstops exist and carry the strict expression. Their enforcement is not
  -- reachable from any client path — no client role holds UPDATE on either table — so it
  -- is asserted here rather than by a live test that could not exist.
  for v_case in
    select * from (values
      ('expenses',        'expenses_void_has_reason'),
      ('revenue_entries', 'revenue_entries_void_states_why')
    ) as t(tbl, con)
  loop
    if not exists (
      select 1 from pg_constraint
       where conname = v_case.con
         and conrelid = ('public.' || v_case.tbl)::regclass
         and pg_get_constraintdef(oid) like '%regexp_replace%') then
      raise exception
        'the % backstop is missing or still trims spaces only', v_case.tbl;
    end if;
  end loop;

  if not has_function_privilege('authenticated',
        'public.expense_void(uuid,integer,text,uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated',
        'public.revenue_void(uuid,integer,text,uuid)', 'EXECUTE') then
    raise exception 'a void boundary lost its EXECUTE grant during the restatement';
  end if;
  if has_function_privilege('anon', 'public.expense_void(uuid,integer,text,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.revenue_void(uuid,integer,text,uuid)', 'EXECUTE') then
    raise exception 'a void boundary is reachable by anon';
  end if;
end $$;

-- ── Recorded, and deliberately not changed here ──────────────────────────────
--
-- `public.period_reopen` takes a mandatory reason (D-026) and normalises it with
-- `btrim(coalesce(p_reason, ''))`, so a lone tab satisfies it exactly as it satisfied the
-- two voids. `period_lock_events` carries the same spaces-only CHECK.
--
-- It is the same defect class and it is **outside the two approved items** of this
-- corrective, which name the Expense and Revenue void boundaries. Reopening a period is a
-- different governance act with its own decision record, and widening a reviewed scope
-- because the fix would be small is how a scope stops being reviewable (D-127). It is
-- reported rather than fixed in passing, and `app.stated_reason` is deliberately shaped so
-- that closing it later is one call per site.
