-- ─────────────────────────────────────────────────────────────────────────────
-- 0009 · Server-authoritative authorisation
--
-- D-037: the Dart `Authorizer` exists to give immediate, offline, testable UX — a
-- disabled control, an honest error message, a form that cannot be submitted. **It is
-- not the security boundary.** These functions are. A modified APK or a rebuilt .exe
-- gains nothing, because every rule is decided again here from rows the client cannot
-- reach and cannot assert.
--
-- Two rules govern everything below:
--
--  1. **The organisation is read, never accepted.** It comes from the caller's `profiles`
--     row. A client-supplied `org_id` is a parameter to be validated against that, never
--     proof of anything.
--  2. **A capability is meaningless without a unit.** `has_capability(cap, null)` is
--     false, not "any unit" — a caller that has not said which property it means has not
--     asked a complete question. `has_capability_anywhere` exists for the genuinely
--     organisation-level cases and is named so nobody reaches for it by accident.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Who is calling ───────────────────────────────────────────────────────────
create or replace function app.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
    from public.profiles p
   where p.id = (select auth.uid())
     and p.is_active;
$$;

create or replace function app.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.org_id
    from public.profiles p
   where p.id = (select auth.uid())
     and p.is_active;
$$;

comment on function app.current_org_id() is
  'The caller organisation, read from their profile. Never taken from a request payload.';

-- Raises when there is no active profile behind the request. An anonymous or deactivated
-- caller is refused before any business rule is even consulted.
create or replace function app.require_actor()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  v_id := app.current_profile_id();
  if v_id is null then
    perform app.refuse('KM011', 'not_authenticated',
      'You are not signed in, or this account has been deactivated.');
  end if;
  return v_id;
end;
$$;

-- ── Capabilities ─────────────────────────────────────────────────────────────
-- One capability, held over one business unit. An unscoped grant (Owner alone, D-025)
-- satisfies any unit; a scoped grant satisfies only its own.
create or replace function public.has_capability(
  p_capability       text,
  p_business_unit_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_business_unit_id is not null and exists (
    select 1
      from public.user_roles ur
      join public.role_capabilities rc on rc.role_id = ur.role_id
     where ur.user_id = (select auth.uid())
       and ur.revoked_at is null
       and rc.capability_code = p_capability
       and (ur.business_unit_id is null or ur.business_unit_id = p_business_unit_id)
  );
$$;

comment on function public.has_capability(text, uuid) is
  'user x capability x business unit. Deliberately false when the unit is null: a check '
  'that has not named a property has not asked a complete question (D-025).';

-- For the genuinely organisation-level cases only — vendors, payment methods, settings.
create or replace function public.has_capability_anywhere(p_capability text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.user_roles ur
      join public.role_capabilities rc on rc.role_id = ur.role_id
     where ur.user_id = (select auth.uid())
       and ur.revoked_at is null
       and rc.capability_code = p_capability
  );
$$;

-- The units a capability covers, for the client to shape its UI honestly. Returns no
-- rows for an unscoped Owner grant, together with the flag saying so — "every unit" is
-- an absence of restriction, not a list.
create or replace function public.scoped_units_for(p_capability text)
returns table (business_unit_id uuid, is_org_wide boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select ur.business_unit_id, ur.business_unit_id is null
    from public.user_roles ur
    join public.role_capabilities rc on rc.role_id = ur.role_id
   where ur.user_id = (select auth.uid())
     and ur.revoked_at is null
     and rc.capability_code = p_capability;
$$;

-- ── The enforcement helpers every RPC uses ───────────────────────────────────
-- Refusals are distinguished exactly as the Dart `DenialReason` distinguishes them, so
-- the two layers give the user the same sentence: "you cannot do this at all" is a
-- different fact from "not for this property", and only the second is actionable.
create or replace function app.require_capability(
  p_capability       text,
  p_business_unit_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.has_capability(p_capability, p_business_unit_id) then
    return;
  end if;

  if public.has_capability_anywhere(p_capability) then
    perform app.refuse('KM002', 'out_of_unit_scope',
      'You do not have permission to do this for this business unit.',
      jsonb_build_object('capability', p_capability,
                         'business_unit_id', p_business_unit_id));
  else
    perform app.refuse('KM001', 'missing_capability',
      'You do not have permission to do this.',
      jsonb_build_object('capability', p_capability));
  end if;
end;
$$;

create or replace function app.require_capability_anywhere(p_capability text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_capability_anywhere(p_capability) then
    perform app.refuse('KM001', 'missing_capability',
      'You do not have permission to do this.',
      jsonb_build_object('capability', p_capability));
  end if;
end;
$$;

-- ── Period state ─────────────────────────────────────────────────────────────
-- A closed period refuses every write touching it, including the Owner's, and including
-- a back-dated create. An organisation-wide lock closes the period for every property;
-- a unit-scoped lock closes it for one and leaves the other open (spec §13.4).
create or replace function public.period_state(
  p_period_key       text,
  p_business_unit_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1
      from public.period_locks pl
     where pl.org_id = app.current_org_id()
       and pl.period_key = p_period_key
       and pl.state = 'closed'
       and (pl.business_unit_id is null or pl.business_unit_id = p_business_unit_id)
  ) then 'closed' else 'open' end;
$$;

create or replace function app.require_period_open(
  p_period_key       text,
  p_business_unit_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.period_state(p_period_key, p_business_unit_id) = 'closed' then
    perform app.refuse('KM004', 'period_closed',
      'This period has been closed. The owner must reopen it before it can be changed.',
      jsonb_build_object('period_key', p_period_key,
                         'business_unit_id', p_business_unit_id));
  end if;
end;
$$;

-- ── Optimistic concurrency (D-021) ───────────────────────────────────────────
-- Idempotency and concurrency are separate mechanisms and are never conflated. This one
-- answers only "is this intent still based on current state?".
create or replace function app.require_version(
  p_entity_type  text,
  p_entity_id    uuid,
  p_actual       integer,
  p_base_version integer
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_base_version is distinct from p_actual then
    perform app.refuse('KM003', 'version_conflict',
      'Someone else changed this record while you were working on it. Review the current '
      'version before applying your change.',
      jsonb_build_object('entity_type', p_entity_type, 'entity_id', p_entity_id,
                         'expected_row_version', p_base_version,
                         'current_row_version', p_actual));
  end if;
end;
$$;

-- ── Idempotency (D-004) ──────────────────────────────────────────────────────
-- Re-delivery of the *same* mutation replays the stored result and changes nothing. A
-- *different* mutation based on a stale version is a conflict, handled above.
create or replace function app.replay_mutation(p_mutation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pm.result
    from public.processed_mutations pm
   where pm.mutation_id = p_mutation_id;
$$;

create or replace function app.remember_mutation(
  p_mutation_id uuid,
  p_org_id      uuid,
  p_actor_id    uuid,
  p_entity_type text,
  p_entity_id   uuid,
  p_op          text,
  p_result      jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_mutation_id is not null then
    insert into public.processed_mutations (
      mutation_id, org_id, actor_id, entity_type, entity_id, op, result)
    values (p_mutation_id, p_org_id, p_actor_id, p_entity_type, p_entity_id, p_op, p_result)
    on conflict (mutation_id) do nothing;
  end if;
  return p_result;
end;
$$;

-- ── Grants ───────────────────────────────────────────────────────────────────
-- The `app` helpers are internal. Only the read-only predicates a client legitimately
-- needs to shape its UI are exposed, and each of them re-derives everything from
-- auth.uid().
revoke all on function app.current_profile_id()          from public;
revoke all on function app.current_org_id()              from public;
revoke all on function app.require_actor()               from public;
revoke all on function app.require_capability(text, uuid) from public;
revoke all on function app.require_capability_anywhere(text) from public;
revoke all on function app.require_period_open(text, uuid) from public;
revoke all on function app.replay_mutation(uuid)         from public;
revoke all on function app.remember_mutation(uuid, uuid, uuid, text, uuid, text, jsonb) from public;
revoke all on function app.write_audit(uuid, text, uuid, text, uuid, jsonb, jsonb, text, uuid, uuid) from public;
revoke all on function app.record_master_usage(uuid, text, uuid, date, integer) from public;
revoke all on function app.active_child_count(text, uuid) from public;

grant execute on function public.has_capability(text, uuid)      to authenticated;
grant execute on function public.has_capability_anywhere(text)   to authenticated;
grant execute on function public.scoped_units_for(text)          to authenticated;
grant execute on function public.period_state(text, uuid)        to authenticated;
grant execute on function public.tax_rule_for(uuid, date)        to authenticated;
