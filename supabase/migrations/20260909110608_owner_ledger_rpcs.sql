-- Server migration ledger: 20260909110608  owner_ledger_rpcs
--
-- Phase 5 OA-1 · the Owner Accounts mutation boundary.
--
-- Every write in this domain travels through one of these. No client role holds INSERT,
-- UPDATE, DELETE or TRUNCATE on any owner-account table, so a modified client has no path
-- around the checks below (D-037, D-162).
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Which capability governs which movement, and why the split falls there
-- ═════════════════════════════════════════════════════════════════════════════
--
--     nc_consumption                    owner_ledger.create.nc
--     withdrawal, settlement_paid       owner_ledger.create.withdrawal
--     opening_balance, manual_adjustment owner_ledger.adjust
--
-- The last line is the one worth defending. `opening_balance` and `manual_adjustment` are
-- **exactly the two types that state their own direction**, which is another way of saying
-- they are the two that can make an account say anything at all. An opening balance sets
-- where the account starts from; an adjustment moves it for a reason the type does not
-- carry. Everything else has a fixed direction and a self-evident meaning.
--
-- So the sensitivity split and the direction split are the same split, which is a good
-- sign that it is the real one rather than one chosen for tidiness.

-- ═════════════════════════════════════════════════════════════════════════════
-- The edit window, measured under the property's own business date (D-067)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Never `current_date`. The session timezone is UTC and the properties are Asia/Kolkata
-- with an 05:00 cut-off, so for half an hour every day the two disagree and an entry that
-- is D+8 old counts as D+7 (D-067). A movement charges exactly one property, so — unlike
-- an expense — there is no greatest-of to take.

create or replace function app.owner_window_today(p_entry_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select app.business_date_at(now(), bu.timezone, bu.business_day_cutoff)
    from public.owner_ledger_entries e
    join public.business_units bu on bu.id = e.business_unit_id
   where e.id = p_entry_id;
$$;

comment on function app.owner_window_today(uuid) is
  'The property business date an owner-movement edit window is measured against (D-067).';

-- The capability a movement type demands. One place, so the three RPCs cannot drift.
create or replace function app.owner_movement_capability(p_movement_type text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_movement_type
    when 'nc_consumption'    then 'owner_ledger.create.nc'
    when 'withdrawal'        then 'owner_ledger.create.withdrawal'
    when 'settlement_paid'   then 'owner_ledger.create.withdrawal'
    when 'opening_balance'   then 'owner_ledger.adjust'
    when 'manual_adjustment' then 'owner_ledger.adjust'
  end;
$$;

comment on function app.owner_movement_capability(text) is
  'The capability required to record one kind of owner movement. Returns null for an unknown type, which the create RPC refuses rather than defaulting.';

-- ═════════════════════════════════════════════════════════════════════════════
-- 1 · Owner and family masters
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.owner_create(
  p_id           uuid,
  p_code         text,
  p_display_name text,
  p_mutation_id  uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_org uuid; v_replay jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Administering who owns the business is an unscoped act: an owner is not a property's
  -- owner, and a grant scoped to one building cannot authorise a statement about the
  -- organisation.
  perform app.require_unscoped_capability('owner_masters.manage');

  insert into public.owners (id, org_id, code, display_name, created_by)
  values (p_id, v_org, p_code, p_display_name, v_actor);

  perform app.write_audit(v_org, 'owner', p_id, 'created', v_actor, null,
    jsonb_build_object('code', p_code, 'display_name', p_display_name),
    null, null, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'owner', p_id, 'create',
    jsonb_build_object('id', p_id, 'status', 'created'));
end; $$;

-- Sets an owner's share from a date, closing whatever share was open before it.
--
-- One RPC rather than two, because "from 1 April this owner holds 50%" is one business
-- act and splitting it would leave a window in which the shares do not total 10000 — a
-- state the settlement calculator is required to refuse, reachable only because the
-- administrative path made it.
create or replace function public.owner_share_set(
  p_owner_id           uuid,
  p_share_basis_points integer,
  p_effective_from     date,
  p_note               text default null,
  p_mutation_id        uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_org uuid; v_replay jsonb; v_id uuid; v_closed integer;
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

create or replace function public.owner_family_member_create(
  p_id                 uuid,
  p_owner_id           uuid,
  p_display_name       text,
  p_effective_from     date,
  p_relationship_label text default null,
  p_is_self            boolean default false,
  p_may_use_nc         boolean default true,
  p_mutation_id        uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_org uuid; v_replay jsonb;
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

  insert into public.owner_family_members (
    id, org_id, owner_id, display_name, relationship_label,
    is_self, may_use_nc, effective_from, created_by)
  values (p_id, v_org, p_owner_id, p_display_name, p_relationship_label,
          coalesce(p_is_self, false), coalesce(p_may_use_nc, true),
          p_effective_from, v_actor);

  perform app.write_audit(v_org, 'owner_family_member', p_id, 'created', v_actor, null,
    jsonb_build_object('owner_id', p_owner_id, 'display_name', p_display_name,
                       'is_self', coalesce(p_is_self, false),
                       'may_use_nc', coalesce(p_may_use_nc, true)),
    null, null, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'owner_family_member', p_id, 'create',
    jsonb_build_object('id', p_id, 'status', 'created'));
end; $$;

-- Ends a family link. **This is how a reassignment happens**: end here, create anew under
-- the other owner. The link itself cannot move — a trigger refuses that — so historical
-- attribution survives by construction rather than by care (section 6).
create or replace function public.owner_family_member_end(
  p_id           uuid,
  p_effective_to date,
  p_mutation_id  uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_org uuid; v_replay jsonb; v_before public.owner_family_members;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_unscoped_capability('owner_masters.manage');

  select * into v_before from public.owner_family_members
   where id = p_id and org_id = v_org;
  if not found then
    perform app.refuse('KM015', 'unknown_entity', 'That person does not exist.', '{}'::jsonb);
  end if;

  update public.owner_family_members
     set effective_to = p_effective_to, active = false,
         updated_by = v_actor, updated_at = now(), row_version = row_version + 1
   where id = p_id;

  perform app.write_audit(v_org, 'owner_family_member', p_id, 'ended', v_actor,
    to_jsonb(v_before), jsonb_build_object('effective_to', p_effective_to),
    null, null, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'owner_family_member', p_id, 'end',
    jsonb_build_object('id', p_id, 'status', 'ended'));
end; $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 2 · The ledger: create
-- ═════════════════════════════════════════════════════════════════════════════
--
-- The caller supplies **facts**. It does not get to dictate the owner an NC bill is
-- attributed to, the direction a fixed-direction movement takes, the period key, the
-- provenance or the transaction number: the server derives every one of those, and its
-- answer is canonical (D-037).

create or replace function public.owner_movement_create(
  p_id                 uuid,
  p_business_unit_id   uuid,
  p_business_date      date,
  p_movement_type      text,
  p_amount_minor       bigint,
  p_direction          text default null,
  p_family_member_id   uuid default null,
  p_declared_owner_id  uuid default null,
  p_owner_id           uuid default null,
  p_collected_by_family_member_id uuid default null,
  p_nc_bill_reference  text default null,
  p_payment_method_id  uuid default null,
  p_reference_number   text default null,
  p_remarks            text default null,
  p_reason             text default null,
  p_captured_at        timestamptz default null,
  p_mutation_id        uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_replay jsonb;
  v_capability text; v_direction text; v_owner uuid;
  v_member public.owner_family_members;
  v_period text := to_char(p_business_date, 'YYYY-MM');
  v_number text; v_fy text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  v_capability := app.owner_movement_capability(p_movement_type);
  if v_capability is null then
    perform app.refuse('KM006', 'validation_failed',
      'That is not a kind of owner movement this system records.',
      jsonb_build_object('movement_type', p_movement_type));
  end if;

  -- Capability before existence (D-046): an unauthorised caller must not be able to use
  -- "unknown owner" versus "no permission" to discover what exists.
  perform app.require_capability_anywhere(v_capability);
  perform app.require_capability(v_capability, p_business_unit_id);

  if p_amount_minor is null or p_amount_minor < 0 then
    perform app.refuse('KM006', 'validation_failed',
      'An amount cannot be negative. Choose the kind of movement instead — that is what decides whether it adds to or reduces the owner''s account.',
      jsonb_build_object('amount_minor', p_amount_minor));
  end if;

  -- ── Direction: fixed by the type, or stated and validated ──────────────────
  v_direction := case p_movement_type
    when 'withdrawal'      then 'debit'
    when 'nc_consumption'  then 'debit'
    when 'settlement_paid' then 'debit'
    else p_direction
  end;
  if v_direction is null or v_direction not in ('credit', 'debit') then
    perform app.refuse('KM006', 'validation_failed',
      'This kind of movement has to say whether it adds to or reduces the owner''s account.',
      jsonb_build_object('movement_type', p_movement_type, 'direction', p_direction));
  end if;

  -- ── Who it belongs to ─────────────────────────────────────────────────────
  if p_movement_type = 'nc_consumption' then
    if p_family_member_id is null then
      perform app.refuse('KM006', 'validation_failed',
        'A non-chargeable bill records who consumed it.', '{}'::jsonb);
    end if;

    select * into v_member from public.owner_family_members
     where id = p_family_member_id and org_id = v_org;
    if not found then
      perform app.refuse('KM015', 'unknown_entity', 'That person does not exist.', '{}'::jsonb);
    end if;

    -- The mapping is resolved **as at the business date**, not as at today. A bill from
    -- last month belongs to whoever that person was linked to last month.
    if not (p_business_date >= v_member.effective_from
            and (v_member.effective_to is null or p_business_date <= v_member.effective_to)) then
      perform app.refuse('KM006', 'validation_failed',
        'That person was not an approved family member on this date.',
        jsonb_build_object('business_date', p_business_date));
    end if;
    if not v_member.may_use_nc then
      perform app.refuse('KM001', 'not_permitted',
        'That person is not approved for non-chargeable consumption.', '{}'::jsonb);
    end if;

    v_owner := v_member.owner_id;

    -- The client declares what it showed the operator; the server **compares** and
    -- refuses on disagreement, never silently re-attributes (section 12).
    --
    -- This is D-114's contract for a declared tax figure, applied to an attribution and
    -- for the same reason: the operator approved a statement about one owner, and
    -- recording it against another would make the record say something nobody agreed to.
    if p_declared_owner_id is not null and p_declared_owner_id <> v_owner then
      perform app.refuse('KM030', 'attribution_mismatch',
        'This bill belongs to a different owner than the one on screen. Open it again to see the current attribution before recording it.',
        jsonb_build_object('declared_owner_id', p_declared_owner_id,
                           'resolved_owner_id', v_owner,
                           'family_member_id', p_family_member_id));
    end if;
  else
    if p_owner_id is null then
      perform app.refuse('KM006', 'validation_failed',
        'This movement has to say which owner it belongs to.', '{}'::jsonb);
    end if;
    if not exists (select 1 from public.owners
                    where id = p_owner_id and org_id = v_org and archived_at is null) then
      perform app.refuse('KM015', 'unknown_entity', 'That owner does not exist.', '{}'::jsonb);
    end if;
    v_owner := p_owner_id;
  end if;

  -- A collector is metadata and is never an attribution, but the person still has to
  -- exist in this organisation (section 13).
  if p_collected_by_family_member_id is not null
     and not exists (select 1 from public.owner_family_members
                      where id = p_collected_by_family_member_id and org_id = v_org) then
    perform app.refuse('KM015', 'unknown_entity',
      'The person recorded as collecting this does not exist.', '{}'::jsonb);
  end if;

  -- ── Period governance, the same discipline as every other financial write ──
  perform app.require_period_open(v_period, p_business_unit_id);

  insert into public.owner_ledger_entries (
    id, org_id, owner_id, business_unit_id, business_date, pnl_period_key,
    business_date_source, captured_at, movement_type, direction, amount_minor,
    family_member_id, collected_by_family_member_id, nc_bill_reference,
    payment_method_id, reference_number, remarks, reason, created_by)
  values (
    p_id, v_org, v_owner, p_business_unit_id, p_business_date, v_period,
    'derived', coalesce(p_captured_at, now()), p_movement_type, v_direction,
    p_amount_minor, p_family_member_id, p_collected_by_family_member_id,
    p_nc_bill_reference, p_payment_method_id, p_reference_number, p_remarks,
    app.stated_reason(p_reason), v_actor);

  select issued_number, issued_financial_year into v_number, v_fy
    from app.next_owner_number(v_org, p_business_date);

  update public.owner_ledger_entries
     set txn_number = v_number, financial_year = v_fy
   where id = p_id;

  perform app.write_audit(v_org, 'owner_ledger_entry', p_id, 'created', v_actor, null,
    jsonb_build_object('owner_id', v_owner, 'movement_type', p_movement_type,
                       'direction', v_direction, 'amount_minor', p_amount_minor,
                       'business_unit_id', p_business_unit_id,
                       'business_date', p_business_date,
                       'family_member_id', p_family_member_id,
                       'txn_number', v_number),
    p_reason, p_business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'owner_ledger_entry', p_id, 'create',
    jsonb_build_object('id', p_id, 'status', 'created', 'txn_number', v_number,
                       'financial_year', v_fy, 'row_version', 1,
                       'owner_id', v_owner, 'direction', v_direction,
                       'business_date_source', 'derived'));
end; $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 3 · The ledger: correction
-- ═════════════════════════════════════════════════════════════════════════════
--
-- **Both periods are checked**, not only the target. Moving a movement out of a closed
-- month changes that month's owner position as surely as moving one in, and spec 13.4's
-- operative word is *affecting*. `revenue_update` already does this; `expense_update` had
-- to be corrected to (D-136), and this starts where that ended up rather than repeating
-- the journey.
--
-- **The movement type is not a parameter.** A correction that turned a withdrawal into a
-- non-chargeable bill would be a different financial event wearing the same number. Enter
-- a new movement instead. An argument that does not exist cannot be forgotten later
-- (D-124's third divergence, applied here from the start).
--
-- **Nor is the owner.** Re-attributing an accepted movement between owners moves money
-- between two people's accounts, and it goes through void-and-re-enter so that both
-- accounts carry a record of what happened.

create or replace function public.owner_movement_update(
  p_id               uuid,
  p_base_row_version integer,
  p_business_date    date,
  p_amount_minor     bigint,
  p_direction        text default null,
  p_collected_by_family_member_id uuid default null,
  p_nc_bill_reference text default null,
  p_payment_method_id uuid default null,
  p_reference_number text default null,
  p_remarks          text default null,
  p_reason           text default null,
  p_correction_reason text default null,
  p_mutation_id      uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_replay jsonb;
  v_before public.owner_ledger_entries;
  v_direction text; v_period text := to_char(p_business_date, 'YYYY-MM');
  v_date_moved boolean; v_elapsed integer; v_window integer;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  perform app.require_capability_anywhere('owner_ledger.edit.all');

  select * into v_before from public.owner_ledger_entries
   where id = p_id and org_id = v_org;
  if not found then
    perform app.refuse('KM015', 'unknown_entity', 'That movement does not exist.', '{}'::jsonb);
  end if;
  perform app.require_capability('owner_ledger.edit.all', v_before.business_unit_id);

  if v_before.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This movement has been voided. Corrections are made by recording a new movement.',
      jsonb_build_object('entry_id', p_id));
  end if;

  perform app.require_version('owner_ledger_entry', p_id,
                              v_before.row_version, p_base_row_version);

  -- Direction stays fixed where the type fixes it; where the type does not, an omitted
  -- direction means "leave it as it was" rather than "make it a credit".
  v_direction := case v_before.movement_type
    when 'withdrawal'      then 'debit'
    when 'nc_consumption'  then 'debit'
    when 'settlement_paid' then 'debit'
    else coalesce(p_direction, v_before.direction)
  end;

  if p_amount_minor is null or p_amount_minor < 0 then
    perform app.refuse('KM006', 'validation_failed',
      'An amount cannot be negative.', jsonb_build_object('amount_minor', p_amount_minor));
  end if;

  -- ── The edit window, under the property's own business date (D-067) ────────
  -- Configuration, not a constant (spec 13.3). `org_settings` is key/value; absent, the
  -- seeded default applies.
  select coalesce((os.value)::text::integer, 7) into v_window
    from public.org_settings os
   where os.org_id = v_org and os.key = 'edit_window_days';
  v_window := coalesce(v_window, 7);
  v_elapsed := app.owner_window_today(p_id) - v_before.business_date;
  if v_elapsed > v_window
     and not public.has_capability('transaction.correct.beyond_window',
                                   v_before.business_unit_id) then
    perform app.refuse('KM021', 'edit_window_closed',
      'This movement is older than the period during which it can be corrected. Somebody with the authority to correct beyond that window has to do it.',
      jsonb_build_object('elapsed_days', v_elapsed, 'window_days', v_window));
  end if;

  -- ── A business-date correction is a first-class act (D-137, mirrored) ──────
  v_date_moved := p_business_date is distinct from v_before.business_date;
  if v_date_moved then
    perform app.require_capability('transaction.correct.business_date',
                                   v_before.business_unit_id);
    if length(app.stated_reason(p_correction_reason)) = 0 then
      perform app.refuse('KM008', 'reason_required',
        'Moving the date of a recorded movement states why.', '{}'::jsonb);
    end if;
    -- The source period as well as the target.
    perform app.require_period_open(v_before.pnl_period_key, v_before.business_unit_id);
  end if;
  perform app.require_period_open(v_period, v_before.business_unit_id);

  update public.owner_ledger_entries
     set business_date = p_business_date,
         pnl_period_key = v_period,
         business_date_source = case when v_date_moved then 'corrected'
                                     else business_date_source end,
         amount_minor = p_amount_minor,
         direction = v_direction,
         collected_by_family_member_id = p_collected_by_family_member_id,
         nc_bill_reference = p_nc_bill_reference,
         payment_method_id = p_payment_method_id,
         reference_number = p_reference_number,
         remarks = p_remarks,
         reason = case when v_before.movement_type = 'manual_adjustment'
                       then app.stated_reason(coalesce(p_reason, v_before.reason))
                       else app.stated_reason(p_reason) end,
         updated_by = v_actor,
         updated_at = now(),
         row_version = v_before.row_version + 1
   where id = p_id;

  perform app.write_audit(v_org, 'owner_ledger_entry', p_id,
    case when v_date_moved then 'business_date_corrected' else 'edited' end,
    v_actor, to_jsonb(v_before),
    jsonb_build_object('amount_minor', p_amount_minor, 'direction', v_direction,
                       'business_date', p_business_date),
    case when v_date_moved then app.stated_reason(p_correction_reason) else null end,
    v_before.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'owner_ledger_entry', p_id, 'update',
    jsonb_build_object('id', p_id, 'status', 'updated',
                       'row_version', v_before.row_version + 1,
                       'business_date_source',
                       case when v_date_moved then 'corrected'
                            else v_before.business_date_source end));
end; $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 4 · The ledger: void
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.owner_movement_void(
  p_id               uuid,
  p_reason           text,
  p_base_row_version integer,
  p_mutation_id      uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_replay jsonb;
  v_before public.owner_ledger_entries; v_reason text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_capability_anywhere('owner_ledger.void');

  select * into v_before from public.owner_ledger_entries
   where id = p_id and org_id = v_org;
  if not found then
    perform app.refuse('KM015', 'unknown_entity', 'That movement does not exist.', '{}'::jsonb);
  end if;
  perform app.require_capability('owner_ledger.void', v_before.business_unit_id);

  -- The canonical whitespace rule, joining the five acts that already carry one rather
  -- than inventing a sixth standard (spec 14.1, D-142, D-145).
  v_reason := app.stated_reason(p_reason);
  if length(v_reason) = 0 then
    perform app.refuse('KM008', 'reason_required',
      'Voiding a movement states why.', '{}'::jsonb);
  end if;

  if v_before.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This movement has already been voided.', jsonb_build_object('entry_id', p_id));
  end if;

  perform app.require_version('owner_ledger_entry', p_id,
                              v_before.row_version, p_base_row_version);
  perform app.require_period_open(v_before.pnl_period_key, v_before.business_unit_id);

  update public.owner_ledger_entries
     set voided_at = now(), voided_by = v_actor, void_reason = v_reason,
         updated_by = v_actor, updated_at = now(),
         row_version = v_before.row_version + 1
   where id = p_id;

  perform app.write_audit(v_org, 'owner_ledger_entry', p_id, 'voided', v_actor,
    to_jsonb(v_before), jsonb_build_object('voided_at', now()),
    v_reason, v_before.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'owner_ledger_entry', p_id, 'void',
    jsonb_build_object('id', p_id, 'status', 'voided',
                       'row_version', v_before.row_version + 1));
end; $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Grants
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Postgres grants EXECUTE to PUBLIC on every new function, so writing only the grant
-- restricts nothing — that is D-044 exactly, and D-101 is it happening a second time one
-- phase later. The revoke is explicit and sits beside the functions it protects.

revoke all on function app.owner_window_today(uuid) from public, anon, authenticated;
revoke all on function app.owner_movement_capability(text) from public, anon, authenticated;
revoke all on function app.next_owner_number(uuid, date) from public, anon, authenticated;

revoke all on function public.owner_create(uuid, text, text, uuid) from public, anon;
revoke all on function public.owner_share_set(uuid, integer, date, text, uuid) from public, anon;
revoke all on function public.owner_family_member_create(uuid, uuid, text, date, text, boolean, boolean, uuid) from public, anon;
revoke all on function public.owner_family_member_end(uuid, date, uuid) from public, anon;
revoke all on function public.owner_movement_create(uuid, uuid, date, text, bigint, text, uuid, uuid, uuid, uuid, text, uuid, text, text, text, timestamptz, uuid) from public, anon;
revoke all on function public.owner_movement_update(uuid, integer, date, bigint, text, uuid, text, uuid, text, text, text, text, uuid) from public, anon;
revoke all on function public.owner_movement_void(uuid, text, integer, uuid) from public, anon;

grant execute on function public.owner_create(uuid, text, text, uuid) to authenticated;
grant execute on function public.owner_share_set(uuid, integer, date, text, uuid) to authenticated;
grant execute on function public.owner_family_member_create(uuid, uuid, text, date, text, boolean, boolean, uuid) to authenticated;
grant execute on function public.owner_family_member_end(uuid, date, uuid) to authenticated;
grant execute on function public.owner_movement_create(uuid, uuid, date, text, bigint, text, uuid, uuid, uuid, uuid, text, uuid, text, text, text, timestamptz, uuid) to authenticated;
grant execute on function public.owner_movement_update(uuid, integer, date, bigint, text, uuid, text, uuid, text, text, text, text, uuid) to authenticated;
grant execute on function public.owner_movement_void(uuid, text, integer, uuid) to authenticated;

-- ── Every one of the eight capabilities is evaluated somewhere ───────────────
--
-- Stated positively, and at deploy time, because the two general assertions would both
-- pass if a capability were simply granted to nobody — which is the D-139 defect in
-- reverse and is how `reports.view` nearly slipped through in the other direction.

do $$
declare v_dead text;
begin
  select string_agg(c.code, ', ') into v_dead
    from public.capabilities c
   where c.category = 'owner_accounts'
     and not exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'app') and p.prokind = 'f'
          and pg_get_functiondef(p.oid) like '%' || c.code || '%')
     and not exists (
       select 1 from pg_policies pol
        where coalesce(pol.qual, '') like '%' || c.code || '%'
           or coalesce(pol.with_check, '') like '%' || c.code || '%');
  if v_dead is not null then
    raise exception
      'owner-account capability granted and evaluated nowhere: %. Either the check was '
      'never written or the grant was never meant (D-127 section 3)', v_dead;
  end if;
end $$;

-- ── And no owner-account function branches on a role name ────────────────────

do $$
declare r record;
begin
  for r in
    -- **Comments are stripped, and that is the point rather than a loophole.** A guard
    -- that reads a function's prose as if it were code is checking the wrong text: the
    -- first run of this block refused `owner_movement_create` for "binary floating point"
    -- because a comment said a collector "has to be a real person". Contorting the prose
    -- to satisfy a regex would have been the wrong fix — a comment cannot declare a type
    -- or branch on a role, so the check belongs on the code.
    --
    -- This is D-139's own lesson pointed the other way: there, counting a comment as an
    -- evaluator let a dead capability pass; here, counting one as code refused a sound
    -- function. Both are the same mistake about what a guard is reading.
    select p.proname,
           regexp_replace(pg_get_functiondef(p.oid), '--[^' || chr(10) || ']*', '', 'g')
             as src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app')
       and p.proname in ('owner_create', 'owner_share_set',
                         'owner_family_member_create', 'owner_family_member_end',
                         'owner_movement_create', 'owner_movement_update',
                         'owner_movement_void', 'owner_movement_capability',
                         'owner_window_today', 'next_owner_number')
  loop
    -- Note the pattern: `\mmanager\M` and friends, and deliberately **not** a bare
    -- `owner`. Every function here is named for the owner-accounts domain, so matching
    -- the word itself would refuse the whole file — which is the same collision that
    -- decided the capability naming (OA-D11), seen from the other side.
    if r.src ~* '\mmanager\M' or r.src ~* '\maccountant\M' or r.src ~* '\mdata_entry\M'
       or r.src ~ 'roles?\.code' then
      raise exception '% branches on a role name rather than a capability', r.proname;
    end if;
    if r.src ~* '\mfloat\M' or r.src ~* '\mreal\M' or r.src ~* 'double precision' then
      raise exception '% uses binary floating point on money', r.proname;
    end if;
  end loop;
end $$;
