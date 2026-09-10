-- Server migration ledger: 20260909112045  owner_ledger_view_is_grantable
--
-- Phase 5 OA-1 · a defect the live authorization matrix found, and it is the one this
-- project keeps finding.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What was wrong
-- ═════════════════════════════════════════════════════════════════════════════
--
-- `20260909110038_owner_accounts_schema` gated the two sensitive reads on
-- `public.has_unscoped_capability('owner_ledger.view')`, reasoning that an owner's current
-- account spans both properties and a per-property slice of it is misleading rather than
-- narrower. **That reasoning is right and the mechanism was wrong.**
--
-- D-025 requires every non-Owner grant to name a business unit, and a database trigger
-- enforces it: only the Owner role may hold an unscoped grant. Measured on this project,
-- that is exactly what the grants look like —
--
--     owner        unscoped   1
--     accountant   scoped     1
--     manager      scoped     4
--     data_entry   scoped     1
--
-- — so `has_unscoped_capability('owner_ledger.view')` could be satisfied by the Owner and
-- by nobody else, for ever. The Accountant was granted the capability by
-- `20260909105555`, could record, correct and void a movement, and then read **nothing**:
-- the live test recorded a withdrawal as the Accountant and got an empty ledger back.
--
-- **That is D-110 and D-116 exactly.** D-110 found a policy requiring a capability no role
-- held; D-116 found three read rules gated on `revenue.view.all`, which does not exist, so
-- the only sanctioned way to read revenue returned nothing to anybody including the Owner.
-- This is the third instance: a capability that is granted, and a gate that the grant can
-- never satisfy. It is invisible to a test that only checks a scoped user sees *less* than
-- the Owner, because both see zero.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What replaces it, and why the principle survives
-- ═════════════════════════════════════════════════════════════════════════════
--
-- `has_capability_anywhere('owner_ledger.view')`.
--
-- The principle was never *"the reader must hold an organisation-wide grant"* — it was
-- **"either the whole ledger is visible or none of it is"**, because a per-property slice
-- of an owner's account shows part of a position with nothing saying so (D-163's argument).
-- `has_capability_anywhere` keeps that exactly: the capability is not used to filter rows
-- by property, so a holder sees every movement of every owner or no row at all.
--
-- What it changes is the meaning of the grant's unit scope for this one capability, and
-- that is stated rather than left to be discovered: **`owner_ledger.view` is inherently an
-- organisation-wide permission, and the business unit named on the grant does not narrow
-- it.** Granting it scoped to one property does not produce a one-property ledger; it
-- produces the whole ledger. Anybody granting it should know that, which is why it is
-- written here and asserted below rather than implied by a helper name.
--
-- The staff-privacy line (OA-1 section 31) is untouched: Manager and Data Entry hold no
-- owner-account capability at all, so an operator who records a bill still learns nothing
-- financial. What changes is that the Accountant can now read the ledger they are
-- permitted to correct — which is what the bundle was always meant to mean.

drop policy if exists ownership_shares_read on public.ownership_shares;
create policy ownership_shares_read on public.ownership_shares
  for select to authenticated
  using (org_id = public.current_org_id()
         and public.has_capability_anywhere('owner_ledger.view'));

drop policy if exists owner_ledger_entries_read on public.owner_ledger_entries;
create policy owner_ledger_entries_read on public.owner_ledger_entries
  for select to authenticated
  using (org_id = public.current_org_id()
         and public.has_capability_anywhere('owner_ledger.view'));

-- ═════════════════════════════════════════════════════════════════════════════
-- The general form of the defect, asserted so it cannot recur here
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Not "these two policies use the right helper" — that would pass for ever and catch
-- nothing. The property is: **no owner-account policy may require an unscoped capability
-- that no role holding it can ever satisfy.** Stated as a search over the catalogue, so
-- the next policy added to this domain is covered by it.

do $$
declare v_bad text;
begin
  select string_agg(pol.policyname || ' (' || c.code || ')', ', ') into v_bad
    from pg_policies pol
    cross join public.capabilities c
   where pol.schemaname = 'public'
     and pol.tablename in ('owners', 'ownership_shares', 'owner_family_members',
                           'owner_ledger_entries')
     and c.category = 'owner_accounts'
     and coalesce(pol.qual, '') like '%has_unscoped_capability%' || c.code || '%'
     -- ... and no role that holds it can satisfy an unscoped requirement.
     and not exists (
       select 1
         from public.role_capabilities rc
         join public.user_roles ur on ur.role_id = rc.role_id
        where rc.capability_code = c.code
          and ur.business_unit_id is null);
  if v_bad is not null then
    raise exception
      'an owner-account policy requires an unscoped capability that no holder can '
      'satisfy: %. That is D-110 and D-116 — a rule that can never evaluate true refuses '
      'everything and looks like a security boundary working', v_bad;
  end if;
end $$;

-- And stated positively: the two sensitive reads are still all-or-nothing rather than
-- sliced by property. A policy that filtered rows on the reader's units would show part of
-- an owner position with nothing saying so.
do $$
declare r record;
begin
  for r in
    select tablename, coalesce(qual, '') as qual
      from pg_policies
     where schemaname = 'public'
       and tablename in ('ownership_shares', 'owner_ledger_entries')
  loop
    if r.qual not like '%owner_ledger.view%' then
      raise exception
        '% is not gated on owner_ledger.view', r.tablename;
    end if;
    if r.qual like '%business_unit_id%' then
      raise exception
        '% filters an owner account by business unit. An owner current account spans '
        'both properties; a per-property slice is not a narrower view but a misleading '
        'one', r.tablename;
    end if;
  end loop;
end $$;
