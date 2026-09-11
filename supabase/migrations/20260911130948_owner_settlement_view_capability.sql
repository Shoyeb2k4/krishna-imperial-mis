-- Server migration ledger name: owner_settlement_view_capability
--
-- Phase 5 OA-3 · the capability that gates the Owner Profit & Settlement Statement.
--
-- The header names no ledger version: the version is assigned at apply time, so a file
-- naming it cannot be the text that was submitted (D-203). `LEDGER.md` maps it.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What the project lead decided (OA-3, 2026-09-11)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- `owner_settlement.view` is created now, together with the boundary that evaluates it —
-- never before it, because a capability granted and evaluated by nothing is the family
-- D-068, D-071, D-077, D-116 and D-139 record, and OA-1 and OA-2 reserved it for exactly
-- this reason (D-197).
--
-- **Owner bundle only, for V1.** The settlement is organisation-wide: it allocates the
-- consolidated Operating Profit of both properties, and a unit-scoped reader must never
-- receive a partial owner settlement. Under D-025 only the Owner role holds unscoped
-- grants, so it is the only bundle that could ever read a complete one.
--
--   * Accountant — NO owner settlement access.
--   * Manager    — NO access.
--   * Data Entry — NO access.
--
-- Enforced by capability and never by a role-name branch. The Owner bundle receives it the
-- way it received the OA-1 capabilities: by the category re-apply below, not by naming the
-- role in any authorisation predicate.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Why the first segment is underscored
-- ═════════════════════════════════════════════════════════════════════════════
--
-- The reporting boundary migrations refuse any body matching `\mowner\M` as a role-name
-- branch. `owner_settlement` does not match, because the underscore is a word character;
-- `owner.settlement.view` would, and a legitimate capability literal would fail a deploy
-- as though it were `if role = 'owner'` (OA-D11, D-199). This is the third namespace the
-- owner-account domain uses, and it is a decision (D-197), not a naming choice.

insert into public.capabilities (code, category, description) values
  ('owner_settlement.view', 'owner_accounts', 'Read the Owner Profit & Settlement Statement preview')
on conflict (code) do nothing;

-- The Owner role is granted every capability by the seed's blanket select, which ran once
-- and cannot see a row added since. Re-applied for this category exactly as OA-1 did, so
-- the new capability reaches the Owner bundle and no other.
insert into public.role_capabilities (role_id, capability_code)
select r.id, c.code
  from public.roles r
  join public.capabilities c on c.category = 'owner_accounts'
 where r.code = 'owner'
on conflict do nothing;

-- ═════════════════════════════════════════════════════════════════════════════
-- Assertions over the catalogue that will actually be applied
-- ═════════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from public.role_capabilities rc
      join public.roles r on r.id = rc.role_id
     where r.code = 'owner' and rc.capability_code = 'owner_settlement.view') then
    raise exception 'the Owner bundle does not hold owner_settlement.view';
  end if;

  -- Owner only. Stated positively over every other role, so a later convenience grant to
  -- the Accountant fails a deploy rather than quietly handing a finance reader the
  -- owners' private position.
  if exists (
    select 1 from public.role_capabilities rc
      join public.roles r on r.id = rc.role_id
     where rc.capability_code = 'owner_settlement.view'
       and r.code <> 'owner') then
    raise exception
      'owner_settlement.view is held by a bundle other than the Owner. V1 grants it to the '
      'Owner bundle only; widening it is a product decision, not a migration detail (OA-3)';
  end if;
end $$;
