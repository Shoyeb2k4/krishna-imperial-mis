-- Server migration ledger: 20260910161035  owner_share_set_refuses_backdating
--
-- Phase 5 OA-1 · a defect the live suite found on its **second** run, which is the only
-- run that could have found it.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What was wrong
-- ═════════════════════════════════════════════════════════════════════════════
--
-- `owner_share_set` closes an open share that started *earlier* and inserts the new one.
-- That is right, and it is the whole of what it does about the timeline. Asked to
-- configure a share at a date at or before one already configured, it fell through to the
-- exclusion constraint:
--
--     conflicting key value violates exclusion constraint "ownership_shares_no_overlap"
--     Key (org_id, owner_id, daterange(effective_from, effective_to, '[]'))=(...)
--
-- A SQLSTATE, a table name, a constraint name and a raw daterange, reaching a caller.
-- Every other refusal this domain raises carries a KM code and a sentence somebody can
-- act on, and spec section 13.1 has required that since Phase 2 -- no refusal message ever
-- contains SQL, a SQLSTATE, a table name or a constraint name. The mid-period rule is
-- refused here with a sentence "rather than only by the CHECK" (OA-1 section 5); the
-- backdating rule was left to the constraint.
--
-- **It is invisible to a suite that runs once.** The first run of the live acceptance
-- configures 5000 + 5000 from 2026-04-01 and then moves Owner A to 6000 from 2026-07-01,
-- and every assertion passes. The second run meets its own residue -- and the residue is
-- permanent, because no client role holds DELETE on `ownership_shares` (D-006) and OA-1
-- deliberately builds no share-removal RPC. That is D-076 exactly: a fixture identifier,
-- or here a fixture *date*, must survive everything the test does to the fixture, and in
-- this project financial fixtures cannot be removed.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- The rule, stated rather than implied by a constraint
-- ═════════════════════════════════════════════════════════════════════════════
--
-- **An ownership timeline moves forward only.** A share may be configured for a month
-- later than every share the owner already has, and for no earlier one. That is not a new
-- restriction invented to make a test pass -- it is what OA-1 section 37 already requires
-- and what the third live assertion already checks: a later change does not restate a
-- historical ratio. Rewriting a historical ownership ratio would silently restate every
-- settlement computed under it, and OA-1 builds no governance act for doing so.
--
-- Refused as `KM031`, which is already this domain's "the proposed ownership effective
-- date is not usable" class, under its own detail code. **The errcode is the class and the
-- detail code is the reason** -- that is the established convention, not a collision:
-- KM001 carries `missing_capability` and `not_permitted`, KM002 carries three names, and
-- the client maps on the detail code (`ServerRefusal._kinds`), never on the errcode.
--
-- The refusal names the next month that *would* work, so the sentence ends in an action
-- rather than in a complaint.

create or replace function public.owner_share_set(
  p_owner_id           uuid,
  p_share_basis_points integer,
  p_effective_from     date,
  p_note               text default null,
  p_mutation_id        uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_org uuid; v_replay jsonb; v_id uuid; v_closed integer;
        v_latest date;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_unscoped_capability('owner_masters.manage');

  if not exists (select 1 from public.owners where id = p_owner_id and org_id = v_org) then
    perform app.refuse('KM015', 'unknown_entity', 'That owner does not exist.', '{}'::jsonb);
  end if;

  -- The mid-period rule, refused here with a sentence rather than only by the CHECK, so
  -- an administrator is told what to do instead of meeting a constraint name (section 5).
  if extract(day from p_effective_from) <> 1 then
    perform app.refuse('KM031', 'ownership_change_mid_period',
      'An ownership change takes effect at the start of a month. Choose the first day of the month it should begin.',
      jsonb_build_object('proposed', p_effective_from,
                         'next_valid', (date_trunc('month', p_effective_from)
                                        + interval '1 month')::date));
  end if;

  -- And the forward-only rule, for the same reason. Without it this falls through to
  -- `ownership_shares_no_overlap` and a caller is handed a constraint name.
  select max(effective_from) into v_latest
    from public.ownership_shares
   where org_id = v_org and owner_id = p_owner_id;

  if v_latest is not null and p_effective_from <= v_latest then
    perform app.refuse('KM031', 'ownership_change_backdated',
      'This owner already has an ownership share beginning on or after that date. An ownership ratio is not restated after the fact; configure the change from a later month.',
      jsonb_build_object('proposed', p_effective_from,
                         'latest_configured', v_latest,
                         'next_valid', (date_trunc('month', v_latest)
                                        + interval '1 month')::date));
  end if;

  -- Close any share still open on the day before the new one begins. An already-closed
  -- share that ends earlier is left alone; one that would overlap is what this prevents.
  update public.ownership_shares
     set effective_to = (p_effective_from - 1),
         updated_by = v_actor, updated_at = now(), row_version = row_version + 1
   where org_id = v_org and owner_id = p_owner_id
     and effective_from < p_effective_from
     and (effective_to is null or effective_to >= p_effective_from);
  get diagnostics v_closed = row_count;

  insert into public.ownership_shares (
    org_id, owner_id, share_basis_points, effective_from, note, created_by)
  values (v_org, p_owner_id, p_share_basis_points, p_effective_from, p_note, v_actor)
  returning id into v_id;

  perform app.write_audit(v_org, 'ownership_share', v_id, 'created', v_actor, null,
    jsonb_build_object('owner_id', p_owner_id,
                       'share_basis_points', p_share_basis_points,
                       'effective_from', p_effective_from,
                       'superseded_open_shares', v_closed),
    null, null, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'ownership_share', v_id, 'create',
    jsonb_build_object('id', v_id, 'status', 'created',
                       'superseded_open_shares', v_closed));
end; $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Assertions
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Structural, over the **deployed** body rather than over this file, because a migration
-- asserting its own text asserts nothing. The behavioural proof is the live suite, which
-- attempts a backdated set and requires KM031 with a sentence carrying no constraint
-- name -- a probe here would need an authenticated actor, which a migration does not have.

do $$
declare v_src text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_share_set';

  if v_src not like '%ownership_change_backdated%' then
    raise exception
      'owner_share_set does not refuse a backdated ownership share, so it falls through '
      'to ownership_shares_no_overlap and hands a caller a constraint name';
  end if;
  if v_src not like '%ownership_change_mid_period%' then
    raise exception 'owner_share_set no longer refuses a mid-month effective date';
  end if;
end $$;

-- `create or replace` keeps the function's existing ACL, so nothing new becomes callable.
-- Asserted rather than assumed, because that is the assumption D-044 and D-101 both cost
-- this project a corrective migration for.
do $$
begin
  if exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where n.nspname = 'public' and p.proname = 'owner_share_set'
       and a.privilege_type = 'EXECUTE'
       and (a.grantee = 0 or a.grantee = 'anon'::regrole::oid)
  ) then
    raise exception 'public.owner_share_set is executable by anon or by PUBLIC';
  end if;
end $$;

-- The D-110 / D-116 class, closed for **functions** as well as for policies.
--
-- `20260909120000_owner_ledger_view_is_grantable` asserted that no owner-account *policy*
-- may require an unscoped capability no holder can satisfy. The same trap exists at a
-- function boundary: D-025 forces every non-Owner grant to name a business unit, so an
-- unscoped requirement is satisfiable only by the Owner, for ever. That is correct for
-- `owner_masters.manage` -- configuring the ownership ratio is an Owner act -- and it is
-- correct because somebody actually holds it that way, which is what this checks.
do $$
declare v_bad text;
begin
  select string_agg(distinct p.proname || ' (' || m[1] || ')', ', ') into v_bad
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral regexp_matches(
      p.prosrc, 'require_unscoped_capability\(\s*''([a-z_.]+)''', 'g') m
   where n.nspname = 'public'
     and p.proname like 'owner\_%'
     and not exists (
       select 1
         from public.role_capabilities rc
         join public.user_roles ur on ur.role_id = rc.role_id
        where rc.capability_code = m[1]
          and ur.business_unit_id is null);
  if v_bad is not null then
    raise exception
      'an owner-account RPC requires an unscoped capability that no holder can satisfy: '
      '%. That is D-110 and D-116 -- a rule that can never evaluate true refuses '
      'everything and looks like a security boundary working', v_bad;
  end if;
end $$;
