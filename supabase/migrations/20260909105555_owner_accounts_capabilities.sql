-- Server migration ledger: 20260909105555  owner_accounts_capabilities
--
-- Phase 5 OA-1 · the capability vocabulary for the Owner Accounts domain.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Why the first segment is underscored, and why nobody should tidy it (OA-D11)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Three shipped reporting migrations — 20260908050614, 20260908122910 and
-- 20260908124127 — carry this guard over the reporting boundary bodies:
--
--     if v_src ~* '\mowner\M' or v_src ~* '\mmanager\M' … then
--       raise exception '% branches on a role name rather than a capability';
--
-- It is correct and it should stay strict. But Postgres word characters include the
-- underscore, so `\mowner\M` does **not** match inside `owner_ledger` — while it *does*
-- match inside `owner.ledger.view`, where the bare word ends at the dot. A capability
-- literal spelled with dots would therefore be refused as though it were `if role =
-- 'owner'`, and the deploy would fail for a reason that reads like a security finding and
-- is a naming collision.
--
-- Underscored first segments avoid the false positive without weakening the guard. This
-- comment is the record so a later cleanup does not "fix" the names back to dots.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What is granted, and what is deliberately withheld
-- ═════════════════════════════════════════════════════════════════════════════
--
-- **Owner** holds everything, automatically: the seed grants the Owner role every row in
-- `public.capabilities`, so these eight arrive with it and no explicit grant is written.
--
-- **Accountant** holds the operational and corrective half. That role exists to record,
-- correct and reconcile finance, which is exactly this surface — with one exclusion.
--
-- **`owner_ledger.adjust` is not granted to the Accountant.** A manual adjustment is the
-- one movement whose meaning its type does not carry, and it is the obvious route to
-- making an account say something convenient. Correction and void already handle every
-- ordinary mistake, so Owner-only costs nothing operationally and keeps the escape hatch
-- with the person whose money it is.
--
-- **Manager and Data Entry hold nothing here.** Whether operational staff may record an
-- NC bill or a withdrawal is a staff-authority question the project lead has not answered.
-- OA-1 was instructed to create no temporary broad access, and default deny is the safe
-- end of an unanswered question: granting later is a migration, ungranting after somebody
-- has recorded against it is an argument.

insert into public.capabilities (code, category, description) values
  ('owner_masters.view',              'owner_accounts', 'Read the Owner and Family masters'),
  ('owner_masters.manage',            'owner_accounts', 'Administer owners, family links and ownership shares'),
  ('owner_ledger.create.nc',          'owner_accounts', 'Record a non-chargeable consumption'),
  ('owner_ledger.create.withdrawal',  'owner_accounts', 'Record an owner withdrawal'),
  ('owner_ledger.view',               'owner_accounts', 'Read the Owner Ledger for every owner'),
  ('owner_ledger.edit.all',           'owner_accounts', 'Correct any owner ledger movement'),
  ('owner_ledger.void',               'owner_accounts', 'Void an owner ledger movement'),
  ('owner_ledger.adjust',             'owner_accounts', 'Record a manual adjustment to an owner account')
on conflict (code) do nothing;

-- One statement per capability, in the shape every earlier bundle grant uses. Not a
-- stylistic choice: the host parity test reads `select r.id, '<code>' … r.code in (…)`
-- to compare the Postgres bundles against the Dart ones, and a `cross join (values …)`
-- form would grant correctly while being invisible to it — a guard reading an empty
-- haystack reports success (D-103).
insert into public.role_capabilities (role_id, capability_code)
select r.id, 'owner_masters.view'
  from public.roles r where r.code in ('accountant')
on conflict do nothing;

insert into public.role_capabilities (role_id, capability_code)
select r.id, 'owner_ledger.create.nc'
  from public.roles r where r.code in ('accountant')
on conflict do nothing;

insert into public.role_capabilities (role_id, capability_code)
select r.id, 'owner_ledger.create.withdrawal'
  from public.roles r where r.code in ('accountant')
on conflict do nothing;

insert into public.role_capabilities (role_id, capability_code)
select r.id, 'owner_ledger.view'
  from public.roles r where r.code in ('accountant')
on conflict do nothing;

insert into public.role_capabilities (role_id, capability_code)
select r.id, 'owner_ledger.edit.all'
  from public.roles r where r.code in ('accountant')
on conflict do nothing;

insert into public.role_capabilities (role_id, capability_code)
select r.id, 'owner_ledger.void'
  from public.roles r where r.code in ('accountant')
on conflict do nothing;

-- The Owner role is granted every capability by the seed's blanket select. That select
-- ran once, before these rows existed, so it has to be re-applied for the new ones —
-- otherwise `owner_ledger.adjust` would be granted to nobody at all and the "stated
-- positively" assertion below would be the only thing to notice.
insert into public.role_capabilities (role_id, capability_code)
select r.id, c.code
  from public.roles r
  join public.capabilities c on c.category = 'owner_accounts'
 where r.code = 'owner'
on conflict do nothing;

-- ── The bundles are asserted, in both directions ─────────────────────────────
--
-- The Dart bundles and the Postgres bundles must agree exactly, and a host test asserts
-- that from the migration text. This proves the same thing against the catalogue that
-- will actually be applied, which is what catches a grant made by hand.

do $$
declare v_missing text; v_extra text;
begin
  -- Owner holds all eight.
  select string_agg(c.code, ', ') into v_missing
    from public.capabilities c
   where c.category = 'owner_accounts'
     and not exists (
       select 1 from public.role_capabilities rc
         join public.roles r on r.id = rc.role_id
        where r.code = 'owner' and rc.capability_code = c.code);
  if v_missing is not null then
    raise exception 'the Owner role is missing owner-account capabilities: %', v_missing;
  end if;

  -- The Accountant holds six, and specifically not the adjustment.
  select string_agg(c, ', ') into v_missing
    from unnest(array['owner_masters.view', 'owner_ledger.create.nc',
                      'owner_ledger.create.withdrawal', 'owner_ledger.view',
                      'owner_ledger.edit.all', 'owner_ledger.void']) as c
   where not exists (
     select 1 from public.role_capabilities rc
       join public.roles r on r.id = rc.role_id
      where r.code = 'accountant' and rc.capability_code = c);
  if v_missing is not null then
    raise exception 'the Accountant bundle is missing: %', v_missing;
  end if;

  if exists (
    select 1 from public.role_capabilities rc
      join public.roles r on r.id = rc.role_id
     where r.code = 'accountant'
       and rc.capability_code in ('owner_ledger.adjust', 'owner_masters.manage')) then
    raise exception
      'owner_ledger.adjust and owner_masters.manage are Owner-only in V1; granting either '
      'to the Accountant is a product decision, not a migration detail';
  end if;

  -- Manager and Data Entry hold nothing in this domain.
  select string_agg(distinct r.code || ':' || rc.capability_code, ', ') into v_extra
    from public.role_capabilities rc
    join public.roles r on r.id = rc.role_id
    join public.capabilities c on c.code = rc.capability_code
   where r.code in ('manager', 'data_entry') and c.category = 'owner_accounts';
  if v_extra is not null then
    raise exception
      'an operational bundle acquired an owner-account capability without a product '
      'decision: %', v_extra;
  end if;
end $$;

-- ── Staff privacy, asserted rather than described (OA-1 section 31) ──────────
--
-- The point of splitting recording from reading is that somebody who may record a bill
-- learns nothing financial. That property is worth an assertion, because it is the one a
-- future convenience grant would quietly destroy: bundling `owner_ledger.view` into an
-- operational role would look like a small usability fix and would hand a waiter every
-- owner's drawings.

do $$
declare v_bad text;
begin
  select string_agg(distinct r.code, ', ') into v_bad
    from public.role_capabilities rc
    join public.roles r on r.id = rc.role_id
   where rc.capability_code in ('owner_ledger.create.nc',
                                'owner_ledger.create.withdrawal')
     and r.code not in ('owner', 'accountant');
  if v_bad is not null then
    raise exception
      'a role outside the reviewed set may record owner movements: %. Recording is an '
      'operational act and may be granted, but it is a product decision', v_bad;
  end if;
end $$;
