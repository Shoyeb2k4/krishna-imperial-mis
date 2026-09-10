-- Server migration ledger name: owner_share_set_enforces_the_v1_vector
--
-- Phase 5 Owner Accounts · the project lead's ruling of 2026-09-10 (D-204), enforced at
-- the configuration boundary.
--
-- The header names no ledger version deliberately. Supabase assigns the version when the
-- migration is applied, so a file that names its own version cannot be the text that was
-- submitted — which is what D-203 had to record about every earlier OA-1 file. The
-- version-to-file mapping lives in `LEDGER.md`, where it is checked.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- The ruling
-- ═════════════════════════════════════════════════════════════════════════════
--
-- For V1, ownership is fixed: **exactly two active owners, 5000 basis points each,
-- totalling 10000.** The settlement engine must not accept or infer 60/40, 70/30, a
-- three-owner allocation, unequal ownership, a partial total, or a total above 100%.
--
-- **This is a business rule, not a schema limitation, and the schema is unchanged.**
-- `ownership_shares` keeps its date-effective columns, its `between 1 and 10000` CHECK
-- and its exclusion constraint, so it still expresses any ratio and every historical row
-- stays exactly as it was recorded. What narrows is what this RPC will accept *now*.
--
-- Lifting it, when a 60/40 transition is separately authorised, is one `create or
-- replace` of this function plus the domain rule it mirrors — and no migration of
-- history, which is the whole reason the constraint is here rather than on the column.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Why the boundary as well as the engine
-- ═════════════════════════════════════════════════════════════════════════════
--
-- The load-bearing guarantee is in the domain: `OwnershipShareSet.resolveV1For` refuses
-- to resolve anything but `[5000, 5000]`, so nothing can *infer* a ratio nobody approved.
-- That alone would leave a database able to hold a configuration every settlement will
-- refuse, with the refusal arriving much later than the act that caused it. Refusing here
-- as well is the "must not accept" half, and it means the two never disagree about what
-- V1 permits.
--
-- Both halves name the same two numbers, and a host guard pins them to each other so one
-- cannot be edited into disagreement with the other — the discipline D-104 established
-- for a stored wire name after it was written and read through two different spellings.

create or replace function public.owner_share_set(
  p_owner_id           uuid,
  p_share_basis_points integer,
  p_effective_from     date,
  p_note               text default null,
  p_mutation_id        uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_org uuid; v_replay jsonb; v_id uuid; v_closed integer;
        v_latest date; v_other_owners integer;
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

  -- ── The V1 vector (D-204) ─────────────────────────────────────────────────
  --
  -- The value first, because it is the one a 60/40 configuration fails while totalling
  -- exactly 10000 — the case a total-only check cannot see at all.
  if p_share_basis_points <> 5000 then
    perform app.refuse('KM033', 'ownership_share_must_be_half',
      'For this version an owner holds exactly half of the business. Configure 5000 basis points, or ask for a different ownership model to be approved first.',
      jsonb_build_object('proposed', p_share_basis_points,
                         'required', 5000,
                         'total', 10000));
  end if;

  -- Then the count. "Open at or after the proposed date" rather than "open today",
  -- because a share configured to begin next April is just as much a third owner as one
  -- that begins now, and checking only today would let it in.
  select count(distinct owner_id) into v_other_owners
    from public.ownership_shares
   where org_id = v_org
     and owner_id <> p_owner_id
     and (effective_to is null or effective_to >= p_effective_from);

  if v_other_owners >= 2 then
    perform app.refuse('KM033', 'ownership_exceeds_two_owners',
      'This version allocates profit between exactly two owners, and two are already configured. End an existing owner''s share before configuring another.',
      jsonb_build_object('other_owners', v_other_owners, 'permitted', 2));
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
-- Assertions, over the deployed body rather than over this file
-- ═════════════════════════════════════════════════════════════════════════════
--
-- A `create or replace` is where a predicate gets lost (D-174), and this one restates a
-- function that already carried two refusals of its own.

do $$
declare v_src text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_share_set';

  if v_src not like '%ownership_share_must_be_half%'
     or v_src not like '%ownership_exceeds_two_owners%' then
    raise exception
      'owner_share_set does not enforce the V1 ownership vector: a share other than '
      '5000 basis points, or a third owner, would be accepted and then refused by every '
      'settlement that read it';
  end if;
  if v_src not like '%ownership_change_mid_period%'
     or v_src not like '%ownership_change_backdated%' then
    raise exception
      'owner_share_set lost a refusal it already carried (D-174)';
  end if;
end $$;

-- The schema is untouched, and that is asserted rather than intended: the ruling says to
-- keep the date-effective model, so a migration that quietly narrowed the column would be
-- doing something nobody asked for and would make an authorised 60/40 a data migration.
do $$
declare v_check text;
begin
  select pg_get_constraintdef(oid) into v_check
    from pg_constraint
   where conname = 'ownership_shares_basis_points_valid';

  if v_check is null then
    raise exception 'the ownership share CHECK is missing';
  end if;
  if v_check not like '%10000%' or v_check like '%5000%' then
    raise exception
      'the ownership share CHECK has been narrowed to the V1 vector. That is a business '
      'rule and belongs at the boundary, not on the column: narrowing it here would make '
      'an authorised future ratio a migration of history';
  end if;

  if not exists (select 1 from pg_constraint
                  where conname = 'ownership_shares_no_overlap') then
    raise exception 'the ownership share exclusion constraint is missing';
  end if;
end $$;

-- No stored row is rewritten by this migration, and history that is not the V1 vector
-- stays exactly as it was recorded. Reported rather than corrected: a settlement over
-- such a period refuses, which is the correct consequence of a ruling that says this
-- version does not do variable ownership.
do $$
declare v_historical integer;
begin
  select count(*) into v_historical
    from public.ownership_shares
   where share_basis_points <> 5000;
  if v_historical > 0 then
    raise notice
      '% ownership share row(s) are not 5000 basis points. They are left exactly as '
      'recorded; V1 refuses to settle a period they govern rather than restating them',
      v_historical;
  end if;
end $$;
