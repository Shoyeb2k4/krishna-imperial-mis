-- Server migration ledger name: owner_share_refusal_promises_no_unavailable_act
--
-- Phase 5 Owner Accounts · a defect in the refusal sentence the previous migration
-- deployed, found by asking whether the action it recommends actually exists.
--
-- The third-owner refusal read:
--
--     "This version allocates profit between exactly two owners, and two are already
--      configured. End an existing owner's share before configuring another."
--
-- **There is no way to end an owner's share.** OA-1 exposes `owner_share_set` and nothing
-- else: it closes the *same* owner's previous share as a side effect of setting a new one,
-- and no `owner_share_end` exists in any migration or anywhere in `lib/`. Substituting one
-- owner for another is an ownership-transition workflow, and the project lead's ruling of
-- 2026-09-10 says not to build one in OA-1 or OA-2 unless separately authorised (D-204).
--
-- So the sentence sent an administrator to look for a control that is deliberately absent.
-- This project holds that a refusal ends in an action rather than in a complaint — and the
-- corollary, which is what was missed, is that **the action has to be available**. A
-- refusal naming an unavailable remedy is worse than one naming none: it reads like a
-- missing button rather than like a decision somebody took.
--
-- Corrected to state the decision, which is the true and actionable thing: changing who
-- the owners are is not part of this version. Nothing else about the function changes, and
-- the assertions below restate every refusal it carries so this replacement cannot quietly
-- drop one (D-174).

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
      'This version allocates profit between exactly two owners, and two are already configured. Changing who the owners are is not part of this version.',
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
-- Assertions, over the deployed body
-- ═════════════════════════════════════════════════════════════════════════════

do $$
declare v_src text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_share_set';

  -- Every refusal the function carried before this replacement still exists. A
  -- `create or replace` is where a predicate gets lost (D-174), and this one exists to
  -- change four words.
  if v_src not like '%ownership_change_mid_period%'
     or v_src not like '%ownership_change_backdated%'
     or v_src not like '%ownership_share_must_be_half%'
     or v_src not like '%ownership_exceeds_two_owners%' then
    raise exception 'owner_share_set lost a refusal it already carried (D-174)';
  end if;

  -- And the sentence no longer recommends an act that does not exist.
  if v_src like '%End an existing owner%' then
    raise exception
      'the third-owner refusal still tells an administrator to end an owner''s share, '
      'and no API can do that';
  end if;
end $$;

-- The remedy it used to name is genuinely absent, and that is asserted rather than
-- remembered: if an owner-share-end boundary is ever added, this fails and whoever adds
-- it gets to decide what the refusal should say.
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app')
       and p.proname in ('owner_share_end', 'owner_share_close', 'owner_share_revoke')
  ) then
    raise exception
      'an owner-share-end boundary now exists. The third-owner refusal was reworded '
      'because none did; revisit what it should tell an administrator to do';
  end if;
end $$;
