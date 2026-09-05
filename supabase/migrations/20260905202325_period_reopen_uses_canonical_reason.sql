-- Reopening a closed period states why, and a tab is not why
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.2 · final pre-Slice-11 corrective
--
-- The last of the five mandatory financial reasons still on the weak rule. D-142 fixed the
-- two voids and recorded this one as outside its approved scope; this closes it.
--
-- **The defect, proven against the shipped function before anything was changed.**
-- `period_reopen` normalised its mandatory reason with `btrim(coalesce(p_reason, ''))`,
-- which strips spaces and nothing else:
--
--     period 2026-05 / Crystal Canopy, lock 6fce38ca-9a3d-4ec7-b2ce-e157199c38df
--     closed legitimately                       state: closed, row_version 1
--     period_reopen(p_reason => E'\t')          APPLIED, state: open, row_version 2
--     refusal                                   none
--     period_lock_events                        {action: reopen, reason: "\t"}
--     audit_logs                                {action: period_reopened, reason: "\t"}
--     period_locks.reopen_reason                "\t"
--     actor                                     the Owner
--
-- A **closed financial period was reopened** — the most privileged financial act this
-- system has, the one spec §13.4 reserves to the Owner and requires to carry a mandatory
-- reason — and the whole justification on record is a tab. Spec §13.4 and D-026 both say
-- the reopen "records actor, timestamp and a **mandatory reason**"; a value that says
-- nothing is not one.
--
-- ## One rule, and this function stops carrying its own
--
-- `app.stated_reason` (D-142) is now the rule for every mandatory financial reason. This
-- restatement changes **two lines**: the normalisation, and nothing else. Every other
-- protection is exactly what it was — the capability, unscoped for an organisation-wide
-- reopen and per-unit otherwise; the reason checked *after* the capability so somebody
-- with no permission is not told how to phrase a request they cannot make; the period
-- identity lookup; the not-closed refusal; optional `base_row_version`; the append-only
-- `period_lock_events` row; the audit row; and `mutation_id` replay.
--
-- ## The backstop, and why validation is conditional
--
-- `period_lock_events_reopen_needs_reason` carried the same spaces-only trim, so the
-- backstop was weaker than the boundary it backs. It now carries the canonical expression,
-- inlined for the reason D-142 gives — a CHECK that calls a function is not re-validated
-- when the function changes.
--
-- It is added `NOT VALID` **and then validated when the data allows**, which is the part
-- worth reading. `period_lock_events` is append-only by trigger, so the one event the RED
-- proof above created cannot be removed or rewritten — correctly, because that is what an
-- append-only financial record means. On `krishna-mis-dev` the constraint therefore stays
-- unvalidated and this migration says so out loud, naming the count. On **any environment
-- with no violating row — a fresh replay, staging, production — the same block validates
-- it**, so nothing inherits an unvalidated schema merely because a development database
-- accumulated immutable test residue.
--
-- The same block retries the two void constraints D-142 left `NOT VALID` for the identical
-- reason. Clean environments end up fully validated; development ends up explained.
--
-- Nothing here deletes a row, grants a DELETE, weakens D-006, or names a fixture id.

create or replace function public.period_reopen(
  p_period_key       text,
  p_reason           text,
  p_business_unit_id uuid default null,
  p_base_row_version integer default null,
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
  v_lock   record;
  v_replay jsonb;
  v_result jsonb;
  -- The canonical rule for every mandatory financial reason (D-142). One-argument `btrim`
  -- strips spaces alone, which let a lone tab justify reopening a closed period.
  v_reason text := app.stated_reason(p_reason);
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  if p_business_unit_id is null then
    perform app.require_unscoped_capability('period.reopen');
  else
    perform app.require_capability('period.reopen', p_business_unit_id);
  end if;

  -- Checked after the capability, so somebody with no permission is not told how to
  -- phrase a request they cannot make anyway.
  if length(v_reason) = 0 then
    perform app.refuse('KM008', 'reason_required',
      'Reopening a closed period requires a reason. It is written to the audit trail.',
      jsonb_build_object('period_key', p_period_key));
  end if;

  select * into v_lock from public.period_locks
   where org_id = v_org and period_key = p_period_key
     and coalesce(business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(p_business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid);

  if v_lock.id is null or v_lock.state <> 'closed' then
    perform app.refuse('KM015', 'period_not_closed',
      'That period is not closed.',
      jsonb_build_object('period_key', p_period_key,
                         'business_unit_id', p_business_unit_id));
  end if;

  if p_base_row_version is not null then
    perform app.require_version('period_lock', v_lock.id, v_lock.row_version,
                                p_base_row_version);
  end if;

  update public.period_locks
     set state = 'open', reopened_by = v_actor, reopened_at = now(), reopen_reason = v_reason
   where id = v_lock.id;

  insert into public.period_lock_events (org_id, period_lock_id, action, reason,
                                         actor_id, mutation_id)
  values (v_org, v_lock.id, 'reopen', v_reason, v_actor, p_mutation_id);

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'period_lock', 'entity_id', v_lock.id,
    'period_key', p_period_key, 'business_unit_id', p_business_unit_id,
    'state', 'open', 'row_version', v_lock.row_version + 1);

  perform app.write_audit(v_org, 'period_lock', v_lock.id, 'period_reopened', v_actor,
    jsonb_build_object('state', 'closed'), jsonb_build_object('state', 'open'),
    v_reason, p_business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'period_lock', v_lock.id,
                               'reopen', v_result);
end;
$$;

revoke all on function public.period_reopen(text, text, uuid, integer, uuid)
  from public, anon;
grant execute on function public.period_reopen(text, text, uuid, integer, uuid)
  to authenticated;

-- ── The backstop, tightened to the same rule ─────────────────────────────────
alter table public.period_lock_events
  drop constraint if exists period_lock_events_reopen_needs_reason;
alter table public.period_lock_events
  add constraint period_lock_events_reopen_needs_reason
  check (action <> 'reopen'
         or (reason is not null
             and length(regexp_replace(reason, '^\s+|\s+$', '', 'g')) > 0))
  not valid;

-- ── Validate every reason constraint the data allows ─────────────────────────
--
-- Environment-adaptive by *counting the rows*, not by naming an environment and not by
-- naming a fixture id. A clean database has nothing to count and ends up validated; a
-- development database with immutable historical residue ends up unvalidated **and says
-- how many rows and why**. Both outcomes are honest, and neither fabricates the other.
do $$
declare
  v_case  record;
  v_bad   bigint;
  v_left  text := '';
begin
  for v_case in
    select * from (values
      ('public.expenses', 'expenses_void_has_reason',
       'voided_at is not null', 'void_reason'),
      ('public.revenue_entries', 'revenue_entries_void_states_why',
       'voided_at is not null', 'void_reason'),
      ('public.period_lock_events', 'period_lock_events_reopen_needs_reason',
       'action = ''reopen''', 'reason')
    ) as t(tbl, con, applies_when, col)
  loop
    execute format(
      'select count(*) from %s where %s and length(regexp_replace(coalesce(%I, ''''), '
      '''^\s+|\s+$'', '''', ''g'')) = 0',
      v_case.tbl, v_case.applies_when, v_case.col) into v_bad;

    if v_bad = 0 then
      execute format('alter table %s validate constraint %I',
                     v_case.tbl, v_case.con);
      raise notice 'validated % (no violating rows)', v_case.con;
    else
      v_left := v_left || format('%s: %s row(s); ', v_case.con, v_bad);
      raise notice
        '% left NOT VALID: % row(s) predate the rule and cannot be repaired — the '
        'append-only and voided-document guards refuse to rewrite them (D-006). New and '
        'updated rows are still checked.', v_case.con, v_bad;
    end if;
  end loop;

  if v_left <> '' then
    raise notice
      'This environment keeps unvalidated reason constraints: %. That is expected on '
      'krishna-mis-dev, whose development probes deliberately produced the rows that '
      'prove the defect. A clean environment validates all three.', v_left;
  end if;
end $$;

-- ── Invariants ───────────────────────────────────────────────────────────────
do $$
declare
  v_weak text;
  v_leak text;
  v_count integer;
begin
  -- Exactly one `period_reopen`. A restatement that left an overload behind would make
  -- every call ambiguous and PostgREST would refuse them all.
  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'period_reopen';
  if v_count <> 1 then
    raise exception 'period_reopen has % overloads; exactly one is the contract', v_count;
  end if;

  -- **The general form.** Every function that can refuse for a missing reason must decide
  -- it by the canonical rule — the helper, or the identical expression inlined. This is
  -- what stops a sixth mandatory reason arriving on the weak rule, and it is written as a
  -- search over the catalogue rather than as a list somebody has to remember to extend.
  select string_agg(n.nspname || '.' || p.proname, ', ') into v_weak
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app') and p.prokind = 'f'
     and pg_get_functiondef(p.oid) like '%reason_required%'
     and pg_get_functiondef(p.oid) not like '%app.stated_reason(%'
     and pg_get_functiondef(p.oid) not like '%regexp_replace(coalesce(p\_%'
     and pg_get_functiondef(p.oid) not like '%regexp_replace(coalesce(p_%';
  if v_weak is not null then
    raise exception
      'a mandatory financial reason is not decided by the canonical rule: %', v_weak;
  end if;

  -- And this one specifically calls the helper rather than having kept its own.
  if pg_get_functiondef(
       'public.period_reopen(text,text,uuid,integer,uuid)'::regprocedure)
       not like '%app.stated_reason(p_reason)%' then
    raise exception 'period_reopen does not use the canonical reason rule';
  end if;

  -- Every protection it had, still named. A restatement is exactly where one goes missing.
  if pg_get_functiondef(
       'public.period_reopen(text,text,uuid,integer,uuid)'::regprocedure)
       not like '%require_unscoped_capability(''period.reopen'')%'
     or pg_get_functiondef(
       'public.period_reopen(text,text,uuid,integer,uuid)'::regprocedure)
       not like '%require_capability(''period.reopen'', p_business_unit_id)%'
     or pg_get_functiondef(
       'public.period_reopen(text,text,uuid,integer,uuid)'::regprocedure)
       not like '%period_not_closed%'
     or pg_get_functiondef(
       'public.period_reopen(text,text,uuid,integer,uuid)'::regprocedure)
       not like '%period_lock_events%'
     or pg_get_functiondef(
       'public.period_reopen(text,text,uuid,integer,uuid)'::regprocedure)
       not like '%replay_mutation%' then
    raise exception 'a period_reopen protection was lost during the restatement';
  end if;

  -- The helper is internal, and adding a caller must not have changed that.
  select string_agg(p.proname, ', ') into v_leak
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_leak is not null then
    raise exception 'a client role can execute functions in app: %', v_leak;
  end if;

  if not has_function_privilege('authenticated',
        'public.period_reopen(text,text,uuid,integer,uuid)', 'EXECUTE') then
    raise exception 'period_reopen lost its EXECUTE grant during the restatement';
  end if;
  if has_function_privilege('anon',
        'public.period_reopen(text,text,uuid,integer,uuid)', 'EXECUTE') then
    raise exception 'period_reopen is reachable by anon';
  end if;
end $$;

-- ── Recorded, and deliberately not changed ───────────────────────────────────
--
-- `expense_attachments_removal_has_reason` also trims spaces only. It is **not** one of
-- the five mandatory financial reasons: no function raises `reason_required` for it, and
-- V1 ships no destructive attachment removal at all (D-072a), so nothing can write the
-- column. Tightening a constraint whose writer does not exist would be changing a rule
-- nothing evaluates, which is the opposite of what this project keeps learning. It is
-- reported so that whoever builds attachment removal starts from the canonical rule.
--
-- `expense_update` decides its correction reason with the canonical expression **inlined**
-- rather than through the helper, because it predates the helper by one migration. Its
-- semantics are identical — the invariant above accepts either form and would fail on a
-- weaker one — so it is left alone rather than restated, which would mean rewriting a
-- large financial function for no behavioural change.
