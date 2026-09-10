-- Server migration ledger: 20260909110038  owner_accounts_schema
--
-- Phase 5 OA-1 · owners, ownership shares, family links and the Owner Ledger.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What this is, and what it is deliberately not
-- ═════════════════════════════════════════════════════════════════════════════
--
-- A management **Owner Current Account**: what each owner is entitled to, what they have
-- drawn or consumed, and what remains. It is not partnership accounting. There are no
-- capital accounts, no interest, no partner salary and no loan accounts, because nothing
-- in the approved specification requires them and each is a doorway to a ledger this
-- product has said twice it will not build (spec section 29, OA-1 section 8).
--
-- **No balance is stored anywhere.** A closing balance is derived from the movements and
-- the entitlement every time it is asked for (OA-D2). Storing one would be a second
-- writable copy of a derivable fact, needing a writer on every mutation path — a
-- correction that moves a period, an edit, a void, a replay — and it would be wrong the
-- first time somebody forgot one. That is D-157's argument for deriving revenue
-- contributions, and it binds harder here because a balance depends on the P&L too.
--
-- **An owner is not a user.** There is no `user_id` on `public.owners` and no foreign key
-- to `auth.users`. An owner is a business subject; whether they hold an MIS login is an
-- unrelated, optional fact. Tying the two would mean provisioning somebody a login
-- granted them a share of the business, and deactivating one orphaned the other.
--
-- **A family member is not a user either**, for the same reason and with the same
-- absence of a column to make the mistake with.

-- ═════════════════════════════════════════════════════════════════════════════
-- 1 · Owners
-- ═════════════════════════════════════════════════════════════════════════════

create table if not exists public.owners (
  id           uuid primary key,                 -- client UUID (D-008)
  org_id       uuid not null references public.organizations(id) on delete restrict,
  code         text not null,                    -- immutable (D-035)
  display_name text not null,
  active       boolean not null default true,
  archived_at  timestamptz,
  created_by   uuid not null,
  created_at   timestamptz not null default now(),
  updated_by   uuid,
  updated_at   timestamptz not null default now(),
  row_version  integer not null default 1,
  change_seq   bigint not null default nextval('app.global_change_seq'),
  constraint owners_code_unique unique (org_id, code),
  constraint owners_code_present check (length(trim(code)) > 0),
  constraint owners_name_present check (length(trim(display_name)) > 0)
);

comment on table public.owners is
  'Business owners: the subjects profit is allocated to. Deliberately carries no user id — an owner is not an MIS account (OA-1 section 3). Ships empty; real owners are bootstrap data supplied by the project lead.';

-- ═════════════════════════════════════════════════════════════════════════════
-- 2 · Ownership shares, effective-dated
-- ═════════════════════════════════════════════════════════════════════════════
--
-- A share lives here rather than as a column on the owner because it is a fact about a
-- **period**. On the owner it would make every historical settlement depend on today's
-- value, so a ratio changed in 2027 would silently restate every 2026 statement — which
-- is the harm the date-effective tax model exists to prevent (D-017), applied to
-- ownership.
--
-- `effective_to` is **inclusive**, matching how the tax rules and premises statuses
-- already express an interval.

create table if not exists public.ownership_shares (
  id                 uuid primary key default extensions.gen_random_uuid(),
  org_id             uuid not null references public.organizations(id) on delete restrict,
  owner_id           uuid not null references public.owners(id) on delete restrict,
  share_basis_points integer not null,
  effective_from     date not null,
  effective_to       date,
  note               text,
  created_by         uuid not null,
  created_at         timestamptz not null default now(),
  updated_by         uuid,
  updated_at         timestamptz not null default now(),
  row_version        integer not null default 1,
  change_seq         bigint not null default nextval('app.global_change_seq'),

  -- Zero is deliberately not a share. An owner entitled to nothing is not an owner for
  -- that period, and `0 bp` would make them appear in an allocation that gives them
  -- nothing — which reads like a defect rather than a fact.
  constraint ownership_shares_basis_points_valid
    check (share_basis_points between 1 and 10000),

  -- ── The mid-period change policy, enforced rather than described (section 5) ──
  --
  -- V1 rule: an ownership change takes effect only at the **start of a settlement
  -- period**, which is the first day of a calendar month — the grain `pnl_period_key`
  -- already uses everywhere else. The inclusive end date is therefore the **last** day of
  -- a month, so one share ends the day before the next begins with no gap and no overlap.
  --
  -- Refusing a mid-month date is the honest answer and also the cheap one: the
  -- alternative is apportioning a month's Operating Profit by day, which assumes profit
  -- accrues evenly through the month. Nothing in this system establishes that, and a
  -- settlement built on it would be exact arithmetic over an invented premise.
  constraint ownership_shares_starts_on_period_boundary
    check (extract(day from effective_from) = 1),
  constraint ownership_shares_ends_on_period_boundary
    check (effective_to is null
           or effective_to = (date_trunc('month', effective_to) + interval '1 month - 1 day')::date),
  constraint ownership_shares_ordered
    check (effective_to is null or effective_to >= effective_from)
);

comment on table public.ownership_shares is
  'Effective-dated profit shares in integer basis points (OA-D1). A change takes effect only at a settlement-period boundary (OA-1 section 5); mid-month dates are refused rather than apportioned by day.';

-- One owner cannot hold two shares at once. An exclusion constraint rather than a unique
-- index, because the thing being forbidden is an **overlap of intervals**, which
-- uniqueness cannot express — the pattern A2 established for premises tax statuses.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ownership_shares_no_overlap') then
    alter table public.ownership_shares
      add constraint ownership_shares_no_overlap
      exclude using gist (
        org_id with =,
        owner_id with =,
        daterange(effective_from, effective_to, '[]') with &&
      );
  end if;
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 3 · Family members
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Includes the owner's own self-record, so the NC entry surface offers exactly one kind
-- of person-reference and the mapping resolves uniformly whether the diner was the owner
-- or their daughter.

create table if not exists public.owner_family_members (
  id                 uuid primary key,           -- client UUID
  org_id             uuid not null references public.organizations(id) on delete restrict,
  owner_id           uuid not null references public.owners(id) on delete restrict,
  display_name       text not null,
  -- A label. Nothing branches on it, and an assertion below proves nothing does: a
  -- relationship that decided an amount would be business logic nobody configured.
  relationship_label text,
  is_self            boolean not null default false,
  may_use_nc         boolean not null default true,
  effective_from     date not null,
  effective_to       date,
  active             boolean not null default true,
  created_by         uuid not null,
  created_at         timestamptz not null default now(),
  updated_by         uuid,
  updated_at         timestamptz not null default now(),
  row_version        integer not null default 1,
  change_seq         bigint not null default nextval('app.global_change_seq'),
  constraint owner_family_members_name_present check (length(trim(display_name)) > 0),
  constraint owner_family_members_ordered
    check (effective_to is null or effective_to >= effective_from)
);

comment on table public.owner_family_members is
  'People who may consume against an owner account (OA-D7). No profit share, no current account of their own, and no login — a family member is a business subject, not an MIS user (OA-1 section 7).';

-- One person record, one owner, for ever.
--
-- The invariant OA-1 section 6 asks for is *"one active family-person identity maps to
-- exactly one owner at a time"*, and the honest way to get it is to make the row the
-- identity and forbid the link from moving. A row therefore names one owner permanently;
-- **reassignment is end-date-this-row and create a new one**, which is the same
-- archive-and-create-anew discipline D-038 requires when a master's meaning changes.
--
-- An interval-overlap constraint keyed on `id` was written here first and was
-- meaningless: `id` is the primary key, so there is only ever one row per id and the
-- exclusion could never fire. A constraint that cannot fail is the family of finding this
-- project keeps recording (D-068, D-071, D-077) — caught by asking what it would actually
-- refuse rather than by reading it.
--
-- The ledger snapshots the resolved owner anyway (section 12), so historical attribution
-- survives even this. Two guarantees holding at once rather than one being trusted.
create or replace function app.refuse_family_owner_reassignment()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.owner_id is distinct from old.owner_id then
    perform app.refuse('KM023', 'family_link_is_immutable',
      'A family member stays with the owner they were recorded under. End this person''s link and add them under the other owner, so past bills keep saying what they meant.',
      jsonb_build_object('family_member_id', old.id));
  end if;
  return new;
end; $$;

drop trigger if exists trg_owner_family_link_immutable on public.owner_family_members;
create trigger trg_owner_family_link_immutable
  before update on public.owner_family_members
  for each row execute function app.refuse_family_owner_reassignment();

-- An owner has at most one self-record live at a time. Without this, two self-records
-- would both be offered on the NC form and the operator would be choosing between two
-- spellings of one person.
create unique index if not exists ux_owner_family_self
  on public.owner_family_members (org_id, owner_id)
  where is_self and active;

-- ═════════════════════════════════════════════════════════════════════════════
-- 4 · The Owner Ledger
-- ═════════════════════════════════════════════════════════════════════════════
--
-- ── Amounts are positive; the type and the direction decide the effect (section 43) ──
--
-- The alternative — signed amounts — allows a negative withdrawal, which is not an event
-- that happens, and makes every aggregate depend on remembering a sign convention nothing
-- enforces. Two representations of one event is the shape that eventually produces two
-- different answers.
--
-- The sign convention, stated once: the balance is **what the business owes the owner**,
-- so a `credit` increases it and a `debit` reduces it. Withdrawal, NC and settlement
-- payment are all debits; they differ in *meaning*, not direction, which is why they are
-- three types rather than one (OA-D4).

create table if not exists public.owner_ledger_entries (
  id                  uuid primary key,          -- client UUID v7 (D-008)
  org_id              uuid not null references public.organizations(id) on delete restrict,
  txn_number          text,                      -- KI-OWN-26-27-000001, server-issued
  financial_year      text,

  -- Resolved at acceptance and **stored**, never re-derived through the family mapping at
  -- read time. This single column is the whole guarantee that reassigning a family member
  -- later cannot restate an accepted attribution (section 12) — the same discipline that
  -- keeps a revenue component explainable after its tax rule is superseded (D-080).
  owner_id            uuid not null references public.owners(id) on delete restrict,

  -- Where the movement happened (section 10). Source attribution for audit and reporting.
  -- It does **not** decide the profit share, which is organisation-wide.
  business_unit_id    uuid not null,

  business_date       date not null,             -- derived under D-067, persisted
  pnl_period_key      text not null,
  business_date_source text not null default 'derived',
  captured_at         timestamptz not null,      -- device instant, forensic only

  movement_type       text not null,
  direction           text not null,
  amount_minor        bigint not null,

  family_member_id             uuid references public.owner_family_members(id) on delete restrict,
  collected_by_family_member_id uuid references public.owner_family_members(id) on delete restrict,

  nc_bill_reference   text,
  payment_method_id   uuid,
  reference_number    text,
  remarks             text,
  reason              text,

  created_by          uuid not null,
  created_at          timestamptz not null default now(),
  updated_by          uuid,
  updated_at          timestamptz not null default now(),
  voided_at           timestamptz,
  voided_by           uuid,
  void_reason         text,
  row_version         integer not null default 1,
  change_seq          bigint not null default nextval('app.global_change_seq'),

  constraint owner_ledger_entries_unit_fk
    foreign key (org_id, business_unit_id)
    references public.business_units(org_id, id) on delete restrict,
  constraint owner_ledger_entries_txn_unique unique (org_id, txn_number),
  constraint owner_ledger_entries_type_valid
    check (movement_type in ('opening_balance', 'withdrawal', 'nc_consumption',
                             'settlement_paid', 'manual_adjustment')),
  constraint owner_ledger_entries_direction_valid
    check (direction in ('credit', 'debit')),
  constraint owner_ledger_entries_provenance_valid
    check (business_date_source in ('derived', 'corrected')),
  constraint owner_ledger_entries_amount_positive
    check (amount_minor >= 0),

  -- The three fixed-direction types are held to their direction here, so the rule is
  -- structural rather than something an RPC has to remember on every path.
  constraint owner_ledger_entries_fixed_direction
    check (movement_type not in ('withdrawal', 'nc_consumption', 'settlement_paid')
           or direction = 'debit'),

  -- Only a consumption names a consumer. A collector is a different fact and is never an
  -- attribution (section 13).
  constraint owner_ledger_entries_consumer_only_on_nc
    check (movement_type = 'nc_consumption' or family_member_id is null),

  -- A manual adjustment always states why, and whitespace is not a reason (spec 14.1).
  constraint owner_ledger_entries_adjustment_states_why
    check (movement_type <> 'manual_adjustment'
           or length(app.stated_reason(reason)) > 0),

  constraint owner_ledger_entries_void_states_why
    check (voided_at is null
           or (voided_by is not null and length(app.stated_reason(void_reason)) > 0)),
  constraint owner_ledger_entries_number_paired
    check ((txn_number is null) = (financial_year is null)),
  constraint owner_ledger_entries_period_matches
    check (pnl_period_key = to_char(business_date, 'YYYY-MM'))
);

comment on table public.owner_ledger_entries is
  'Owner current-account movements. Amounts are always positive; the movement type and direction decide the effect (OA-1 section 43). No balance is stored — a closing balance is derived (OA-D2). Never an Expense and never Revenue.';

create index if not exists owner_ledger_owner_period_idx
  on public.owner_ledger_entries (org_id, owner_id, pnl_period_key)
  where voided_at is null;

create index if not exists owner_ledger_unit_date_idx
  on public.owner_ledger_entries (org_id, business_unit_id, business_date);

-- ═════════════════════════════════════════════════════════════════════════════
-- 5 · change_seq advances on every update (OA-1 section 22, D-177)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- D-172 required this to be **proven** rather than assumed, and D-177 is what happened
-- when it was not: `revenue_entries` carried `change_seq` with a default and stamped
-- nothing on UPDATE, so an edit, a business-date correction that moved a sale from June
-- to July, and a void were all invisible to any delta. `row_version` advanced throughout,
-- which is exactly what hid it.
--
-- The invariant that closed it is catalogue-wide with **no exemption list**, so these four
-- tables are covered by it the moment they exist. The triggers are installed here from
-- day one rather than being a corrective later.
--
-- `app.stamp_change_seq` rather than `app.touch_row`, deliberately: `touch_row` also
-- increments `row_version`, and these RPCs own that themselves — attaching it would
-- double-increment the concurrency token and refuse every client's next correction with
-- a version conflict it could not explain.

drop trigger if exists trg_owners_change_seq on public.owners;
create trigger trg_owners_change_seq
  before update on public.owners
  for each row execute function app.stamp_change_seq();

drop trigger if exists trg_ownership_shares_change_seq on public.ownership_shares;
create trigger trg_ownership_shares_change_seq
  before update on public.ownership_shares
  for each row execute function app.stamp_change_seq();

drop trigger if exists trg_owner_family_change_seq on public.owner_family_members;
create trigger trg_owner_family_change_seq
  before update on public.owner_family_members
  for each row execute function app.stamp_change_seq();

drop trigger if exists trg_owner_ledger_change_seq on public.owner_ledger_entries;
create trigger trg_owner_ledger_change_seq
  before update on public.owner_ledger_entries
  for each row execute function app.stamp_change_seq();

do $$
declare v_missing text;
begin
  select string_agg(t.tbl, ', ') into v_missing
    from unnest(array['owners', 'ownership_shares', 'owner_family_members',
                      'owner_ledger_entries']) as t(tbl)
   where not exists (
     select 1 from pg_trigger tg
       join pg_class c on c.oid = tg.tgrelid
       join pg_namespace n on n.oid = c.relnamespace
       join pg_proc p on p.oid = tg.tgfoid
      where n.nspname = 'public' and c.relname = t.tbl
        and p.proname = 'stamp_change_seq' and not tg.tgisinternal);
  if v_missing is not null then
    raise exception
      'owner-account table carries change_seq and does not advance it on update: %. '
      'That is D-177 exactly, and it is invisible until a reporting delta silently '
      'misses a correction', v_missing;
  end if;
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 6 · A voided movement is immutable
-- ═════════════════════════════════════════════════════════════════════════════
--
-- The same rule every financial document in this system carries (D-006): history is
-- corrected by void and re-entry, never by rewriting a voided row.

create or replace function app.refuse_voided_owner_movement()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  -- The void itself is the one update allowed to set voided_at, so the test is on the
  -- **old** row. Exactly the shape `app.refuse_voided_mutation` already uses for expenses;
  -- a separate function only because the sentence a person reads is different.
  if old.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This movement has been voided. Corrections are made by recording a new movement.',
      jsonb_build_object('entry_id', old.id));
  end if;
  return new;
end; $$;

drop trigger if exists trg_owner_ledger_voided_immutable on public.owner_ledger_entries;
create trigger trg_owner_ledger_voided_immutable
  before update on public.owner_ledger_entries
  for each row execute function app.refuse_voided_owner_movement();

-- ═════════════════════════════════════════════════════════════════════════════
-- 7 · Owner Ledger numbering: its own financial-year sequence
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Section 21 asked whether a transaction number earns its place here. It does, and for the
-- reason it does everywhere else in this product: `txn_number` is the marker of **canonical
-- acceptance**. Slice 1 made `txn_number is not null` the one canonical-only predicate on
-- both reporting engines (D-168), and OA-1 section 17 requires the Owner Ledger to follow
-- the same doctrine. Without a number there would be no server-issued fact distinguishing
-- an accepted movement from a local attempt, and the canonical rule would have to be
-- invented from something softer.
--
-- It is also what a person quotes. "Which withdrawal?" has to have an answer that survives
-- a screenshot.
--
-- Its own sequence, shared with neither the expense nor the revenue one: three document
-- families that share a counter cannot be reconciled independently.

create table if not exists public.owner_number_counters (
  org_id         uuid not null references public.organizations(id) on delete restrict,
  financial_year text not null,
  last_value     bigint not null default 0,
  primary key (org_id, financial_year)
);

alter table public.owner_number_counters enable row level security;
revoke all on public.owner_number_counters from anon, authenticated;

comment on table public.owner_number_counters is
  'KI-OWN sequence state, per organisation and financial year. Unreadable by any client: a counter is not data, and exposing it would leak how much has been recorded.';

create or replace function app.next_owner_number(p_org uuid, p_date date)
returns table (issued_number text, issued_financial_year text)
language plpgsql security definer set search_path = '' as $$
declare
  v_fy   text := app.revenue_financial_year(p_date);
  v_next bigint;
begin
  -- Concurrency-safe by construction: the upsert takes a row lock on exactly this
  -- (org, financial year), so two concurrent acceptances serialise on the counter and
  -- neither can read the same last_value.
  insert into public.owner_number_counters (org_id, financial_year, last_value)
       values (p_org, v_fy, 1)
  on conflict (org_id, financial_year)
    do update set last_value = public.owner_number_counters.last_value + 1
  returning last_value into v_next;

  issued_number := 'KI-OWN-' || v_fy || '-' || lpad(v_next::text, 6, '0');
  issued_financial_year := v_fy;
  return next;
end; $$;

comment on function app.next_owner_number(uuid, date) is
  'Issues the next KI-OWN number on canonical acceptance. Its own counter, shared with neither the expense nor the revenue sequence (D-085 applied to a third document family).';

-- `app.revenue_financial_year` is reused rather than a third copy being written: the
-- financial year is 1 April to 31 March for every document family in this product, and a
-- second implementation of one rule is the situation that drifts (D-020's argument at
-- the smallest scale). The name is historical; the function is about the calendar.

-- ═════════════════════════════════════════════════════════════════════════════
-- 8 · RLS — default deny, and a partial ledger is worse than none
-- ═════════════════════════════════════════════════════════════════════════════

alter table public.owners               enable row level security;
alter table public.ownership_shares     enable row level security;
alter table public.owner_family_members enable row level security;
alter table public.owner_ledger_entries enable row level security;

-- No client holds any write privilege on any of them: every mutation goes through a
-- reviewed SECURITY DEFINER RPC. **All four privileges**, not three — TRUNCATE survived a
-- three-word revoke on four financial tables and does not consult RLS at all (D-162).
revoke all on public.owners               from anon, authenticated;
revoke all on public.ownership_shares     from anon, authenticated;
revoke all on public.owner_family_members from anon, authenticated;
revoke all on public.owner_ledger_entries from anon, authenticated;

-- Reads are granted back, gated by the policies below and by nothing else.
grant select on public.owners               to authenticated;
grant select on public.ownership_shares     to authenticated;
grant select on public.owner_family_members to authenticated;
grant select on public.owner_ledger_entries to authenticated;

-- ── The masters: the person list an operator needs ──────────────────────────
--
-- `owner_masters.view` **or** `owner_ledger.view`, held anywhere. An NC clerk must be
-- able to say whose bill it is; that is the whole of what these two tables tell them, and
-- it carries no amount, no balance and no share.

create policy owners_read on public.owners
  for select to authenticated
  using (org_id = public.current_org_id()
         and (public.has_capability_anywhere('owner_masters.view')
              or public.has_capability_anywhere('owner_ledger.view')));

create policy owner_family_members_read on public.owner_family_members
  for select to authenticated
  using (org_id = public.current_org_id()
         and (public.has_capability_anywhere('owner_masters.view')
              or public.has_capability_anywhere('owner_ledger.view')));

-- ── Shares and the ledger: unscoped, and only for the sensitive capability ───
--
-- **`owner_ledger.view` is required unscoped, and that is a design decision rather than
-- a convenience.** An owner's current account spans both properties, so a per-property
-- slice of it is not a narrower view — it is a misleading one, showing part of an account
-- with nothing saying so. Either the whole ledger is visible or none of it is, which is
-- D-163's argument applied to an owner position.
--
-- The profit share is gated the same way and **not** by `owner_masters.view`, because a
-- ratio is what an entitlement is computed from: handing it to somebody who may record a
-- bill would tell them how the business is divided (OA-1 section 31).

create policy ownership_shares_read on public.ownership_shares
  for select to authenticated
  using (org_id = public.current_org_id()
         and public.has_unscoped_capability('owner_ledger.view'));

create policy owner_ledger_entries_read on public.owner_ledger_entries
  for select to authenticated
  using (org_id = public.current_org_id()
         and public.has_unscoped_capability('owner_ledger.view'));

-- ── Assertions, because a policy nobody evaluates is a comment ───────────────

do $$
declare v_bad text;
begin
  -- Every one of the four is RLS-enabled and default-deny.
  select string_agg(c.relname, ', ') into v_bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('owners', 'ownership_shares', 'owner_family_members',
                       'owner_ledger_entries', 'owner_number_counters')
     and not c.relrowsecurity;
  if v_bad is not null then
    raise exception 'owner-account table without row level security: %', v_bad;
  end if;

  -- No client write grant anywhere in the domain, over all four privileges.
  select string_agg(table_name || ':' || privilege_type, ', ') into v_bad
    from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in ('owners', 'ownership_shares', 'owner_family_members',
                        'owner_ledger_entries', 'owner_number_counters')
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_bad is not null then
    raise exception
      'a client role holds a write privilege on an owner-account table: %. Every '
      'mutation travels through a reviewed SECURITY DEFINER RPC (D-162)', v_bad;
  end if;

  -- `anon` reads nothing at all.
  select string_agg(table_name, ', ') into v_bad
    from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in ('owners', 'ownership_shares', 'owner_family_members',
                        'owner_ledger_entries', 'owner_number_counters')
     and grantee = 'anon';
  if v_bad is not null then
    raise exception 'anon holds a privilege on an owner-account table: %', v_bad;
  end if;

  -- No policy in this domain reads a financial base table inline. A policy expression
  -- runs with the **querying user's** privileges, so an inline read answers from rows the
  -- caller can already see rather than from the truth — and a correct predicate restored
  -- from a superseded version of itself is how that came back after being fixed twice
  -- (D-045, D-109, D-174).
  select string_agg(policyname, ', ') into v_bad
    from pg_policies
   where schemaname = 'public'
     and tablename in ('owners', 'ownership_shares', 'owner_family_members',
                       'owner_ledger_entries')
     and (coalesce(qual, '') ~ 'from public\.(expenses|revenue_entries|revenue_components|owner_ledger_entries)'
          or coalesce(with_check, '') ~ 'from public\.(expenses|revenue_entries|revenue_components|owner_ledger_entries)');
  if v_bad is not null then
    raise exception 'an owner-account policy reads a financial base table inline: %', v_bad;
  end if;

  -- And no policy branches on a role name. Capability-first, always (spec 13.1, OA-D8).
  select string_agg(policyname, ', ') into v_bad
    from pg_policies
   where schemaname = 'public'
     and tablename in ('owners', 'ownership_shares', 'owner_family_members',
                       'owner_ledger_entries')
     and (coalesce(qual, '') ~* '\mmanager\M|\maccountant\M|\mdata_entry\M'
          or coalesce(qual, '') ~ 'roles?\.code');
  if v_bad is not null then
    raise exception 'an owner-account policy branches on a role name: %', v_bad;
  end if;
end $$;

-- ── The relationship label decides nothing ──────────────────────────────────
--
-- Stated as an assertion rather than a comment because "this column is only a label" is
-- exactly the kind of rule this project has repeatedly found nobody evaluates. If a
-- relationship ever starts deciding an amount, it becomes business logic that nobody
-- configured and that no capability governs.

do $$
declare v_bad text;
begin
  -- `prokind = 'f'` is required, not defensive: `pg_get_functiondef` raises 42809 on an
  -- aggregate, and `public` holds several. The D-139 assertion this is modelled on already
  -- carries the same filter, and omitting it here made the first application of this
  -- migration fail with a message about `array_agg` that has nothing to do with the rule
  -- being checked.
  select string_agg(p.proname, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app')
     and p.prokind = 'f'
     and pg_get_functiondef(p.oid) ~ 'relationship_label'
     and pg_get_functiondef(p.oid) ~* '(amount_minor|share_basis_points)';
  if v_bad is not null then
    raise exception
      'a function reads relationship_label alongside money or a share: %. A family '
      'relationship is a label; the moment it decides a figure it is uncontrolled '
      'business logic', v_bad;
  end if;
end $$;
