-- Phase 4 Slice 4 — the authoritative revenue schema, resolver, numbering, projection,
-- RPC boundary and the verified FY 2026-27 baseline.
--
-- Applied to `krishna-mis-dev` as six migrations, recorded there as:
--   20260901115849 revenue_tables
--   20260901115939 revenue_tax_resolution
--   20260901132003 revenue_resolver_numbering_projection
--   20260901132148 revenue_rpcs
--   20260901132225 revenue_verified_baseline_fy2627
--   20260901132659 revenue_projection_security_barrier
--
-- This file is the committed record of that work (D-056: every migration the server has
-- applied must exist in the repository). The ordering below is the ordering that was
-- applied, and it matters: structures and the new validator are installed BEFORE the
-- obsolete Phase 2 exclusion constraint is dropped, so no window exists in which
-- ambiguous tax configuration could be written.
--
-- Money is integer paise throughout. No floating point touches a currency amount.

-- ═════════════════════════════════════════════════════════════════════════════
-- 1 · Reference masters and the document/component tables
-- ═════════════════════════════════════════════════════════════════════════════

-- A configured value band: the stable identity an operator selects for a component.
-- Exists because rule identity cannot serve as band identity (D-098): rules are
-- superseded by date and a band is not.
--
-- Boundaries are WRITE-ONCE (D-100). Editing them would retroactively redefine what every
-- effective-dated rule referencing the band applied to — for dates already recorded — with
-- nothing saying it had changed. A boundary change is a different band.
create table if not exists public.revenue_value_bands (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id) on delete restrict,
  revenue_category_id uuid not null
    references public.revenue_categories(id) on delete restrict,
  code                text not null,
  label               text not null,
  floor_minor         bigint,
  ceiling_minor       bigint,
  superseded_by_band_id uuid references public.revenue_value_bands(id) on delete restrict,
  archived_at         timestamptz,
  created_by          uuid not null,
  created_at          timestamptz not null default now(),
  row_version         integer not null default 1,
  updated_at          timestamptz not null default now(),
  constraint revenue_value_bands_code_unique unique (org_id, revenue_category_id, code),
  constraint revenue_value_bands_floor_sane check (floor_minor is null or floor_minor >= 0),
  constraint revenue_value_bands_range_ordered
    check (ceiling_minor is null or floor_minor is null or ceiling_minor > floor_minor),
  -- A band describing no range at all is a label pretending to be a discriminator.
  constraint revenue_value_bands_has_range
    check (floor_minor is not null or ceiling_minor is not null)
);

comment on table public.revenue_value_bands is
  'Configured tariff bands (D-098). Boundaries are write-once (D-100); a change creates a new band that supersedes this one. Ships empty.';

-- A trigger rather than a convention, because "do not edit this" in a comment is the
-- class of rule this project has repeatedly found nobody evaluates. The label stays
-- editable: a rename preserving meaning is D-038's permitted case.
create or replace function app.refuse_band_redefinition()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.floor_minor is distinct from old.floor_minor
     or new.ceiling_minor is distinct from old.ceiling_minor
     or new.code is distinct from old.code
     or new.revenue_category_id is distinct from old.revenue_category_id then
    perform app.refuse('KM023', 'band_is_immutable',
      'A value band''s boundaries cannot be changed. Create a new band and supersede this one, so history keeps saying what it meant.',
      jsonb_build_object('band_id', old.id));
  end if;
  return new;
end; $$;

drop trigger if exists trg_band_immutable on public.revenue_value_bands;
create trigger trg_band_immutable
  before update on public.revenue_value_bands
  for each row execute function app.refuse_band_redefinition();

-- Supply subtypes (D-083). Ships empty; no speculative subtype is created.
create table if not exists public.revenue_supply_subtypes (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id) on delete restrict,
  revenue_category_id uuid not null
    references public.revenue_categories(id) on delete restrict,
  code                text not null,
  label               text not null,
  archived_at         timestamptz,
  created_by          uuid not null,
  created_at          timestamptz not null default now(),
  row_version         integer not null default 1,
  updated_at          timestamptz not null default now(),
  constraint revenue_supply_subtypes_code_unique unique (org_id, revenue_category_id, code)
);

comment on table public.revenue_supply_subtypes is
  'Ships empty (D-083). A subtype exists only after a verified business decision about what is actually invoiced.';

-- Premises tax status over time (D-082). Configured business data, never derived.
create table if not exists public.business_unit_tax_statuses (
  id               uuid primary key default extensions.gen_random_uuid(),
  org_id           uuid not null references public.organizations(id) on delete restrict,
  business_unit_id uuid not null,
  effective_from   date not null,
  status_code      text not null,
  note             text,
  created_by       uuid not null,
  created_at       timestamptz not null default now(),
  row_version      integer not null default 1,
  updated_at       timestamptz not null default now(),
  constraint business_unit_tax_statuses_unit_fk
    foreign key (org_id, business_unit_id)
    references public.business_units(org_id, id) on delete restrict,
  constraint business_unit_tax_statuses_code_present check (length(trim(status_code)) > 0),
  constraint business_unit_tax_statuses_one_per_date
    unique (org_id, business_unit_id, effective_from)
);

comment on table public.business_unit_tax_statuses is
  'Date-effective premises tax status (D-082). Never inferred. Ships empty.';

-- The rule model gains its bounded discriminators. All nullable and NONE backfilled: a
-- rule configured before Phase 4 has no authoritative answer for these, and writing
-- `inclusive_total` because every verified category happens to use it would be inventing
-- a business fact. A rule with no basis is visibly incomplete and the resolver refuses it.
alter table public.revenue_tax_rates
  add column if not exists input_basis text,
  add column if not exists value_band_id uuid,
  add column if not exists supply_subtype_id uuid,
  add column if not exists premises_status_code text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'revenue_tax_rates_input_basis_valid') then
    alter table public.revenue_tax_rates
      add constraint revenue_tax_rates_input_basis_valid
      check (input_basis is null or input_basis in ('inclusive_total', 'pre_tax'));
  end if;
  -- Basis and treatment are NOT coupled one-to-one (D-097); only the contradictory
  -- pairings are refused. `none` accepts either basis, because with no tax the customer
  -- total and the pre-tax amount are the same number.
  if not exists (select 1 from pg_constraint where conname = 'revenue_tax_rates_basis_coherent') then
    alter table public.revenue_tax_rates
      add constraint revenue_tax_rates_basis_coherent check (
        input_basis is null
        or treatment = 'none'
        or (treatment = 'inclusive' and input_basis = 'inclusive_total')
        or (treatment = 'exclusive' and input_basis = 'pre_tax')
      );
  end if;
  if not exists (select 1 from pg_constraint where conname = 'revenue_tax_rates_band_fk') then
    alter table public.revenue_tax_rates add constraint revenue_tax_rates_band_fk
      foreign key (value_band_id) references public.revenue_value_bands(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'revenue_tax_rates_subtype_fk') then
    alter table public.revenue_tax_rates add constraint revenue_tax_rates_subtype_fk
      foreign key (supply_subtype_id) references public.revenue_supply_subtypes(id) on delete restrict;
  end if;
end $$;

create table if not exists public.revenue_entries (
  id                  uuid primary key,              -- client UUID v7 (D-008)
  org_id              uuid not null references public.organizations(id) on delete restrict,
  txn_number          text,                          -- KI-REV-26-27-000001, server-issued
  financial_year      text,
  business_unit_id    uuid not null,
  revenue_category_id uuid not null,
  business_date       date not null,                 -- derived under D-067, persisted
  pnl_period_key      text not null,
  captured_at         timestamptz not null,          -- device instant, forensic only
  entry_kind          text not null default 'daily_summary',
  source_reference    text,
  notes               text,
  created_by          uuid not null,
  created_at          timestamptz not null default now(),
  updated_by          uuid,
  updated_at          timestamptz not null default now(),
  voided_at           timestamptz,
  voided_by           uuid,
  void_reason         text,
  row_version         integer not null default 1,
  change_seq          bigint not null default nextval('app.global_change_seq'),
  -- The composite ladder (D-040): a category is reached only through its own unit.
  constraint revenue_entries_category_fk
    foreign key (org_id, business_unit_id, revenue_category_id)
    references public.revenue_categories(org_id, business_unit_id, id) on delete restrict,
  constraint revenue_entries_txn_unique unique (org_id, txn_number),
  constraint revenue_entries_kind_valid
    check (entry_kind in ('daily_summary', 'shift', 'import', 'correction')),
  constraint revenue_entries_period_matches
    check (pnl_period_key = to_char(business_date, 'YYYY-MM')),
  constraint revenue_entries_void_states_why
    check (voided_at is null or (voided_by is not null and length(trim(coalesce(void_reason, ''))) > 0)),
  constraint revenue_entries_number_paired
    check ((txn_number is null) = (financial_year is null))
);

comment on table public.revenue_entries is
  'A revenue document (spec 8.0). Carries NO monetary column: gross, tax and net are the exact sums of its components. There is no header total to drift (D-078).';

create table if not exists public.revenue_components (
  id                    uuid primary key,
  org_id                uuid not null references public.organizations(id) on delete restrict,
  revenue_entry_id      uuid not null references public.revenue_entries(id) on delete cascade,
  entered_amount_minor  bigint not null,
  entered_basis         text not null,
  gross_amount_minor    bigint not null,
  tax_amount_minor      bigint not null default 0,
  net_amount_minor      bigint not null,
  tax_rule_id           uuid not null references public.revenue_tax_rates(id) on delete restrict,
  tax_rate_bp           integer not null,
  tax_treatment         text not null,
  value_band_id         uuid references public.revenue_value_bands(id) on delete restrict,
  value_band_label      text,
  value_band_floor_minor   bigint,
  value_band_ceiling_minor bigint,
  supply_subtype_id     uuid references public.revenue_supply_subtypes(id) on delete restrict,
  supply_subtype_label  text,
  premises_status_code  text,
  created_at            timestamptz not null default now(),
  constraint revenue_components_basis_valid check (entered_basis in ('inclusive_total', 'pre_tax')),
  constraint revenue_components_treatment_valid check (tax_treatment in ('inclusive', 'exclusive', 'none')),
  constraint revenue_components_amounts_sane
    check (entered_amount_minor >= 0 and gross_amount_minor >= 0 and tax_amount_minor >= 0),
  constraint revenue_components_rate_sane check (tax_rate_bp between 0 and 10000),
  constraint revenue_components_reconciles
    check (net_amount_minor = gross_amount_minor - tax_amount_minor),
  constraint revenue_components_tax_within_gross check (tax_amount_minor <= gross_amount_minor),
  constraint revenue_components_untaxed_is_free
    check (tax_treatment <> 'none' or tax_amount_minor = 0),
  constraint revenue_components_band_bounds_need_band
    check (value_band_id is not null or (value_band_floor_minor is null and value_band_ceiling_minor is null))
);

comment on table public.revenue_components is
  'The canonical monetary rows. A document has one or more; a routine day has one.';

-- Every document has at least one component. A DEFERRED constraint trigger, which is
-- exactly what SQLite could not offer the local mirror: the check runs at COMMIT, so an
-- entry and its components may be written by separate statements in one transaction.
create or replace function app.assert_revenue_has_components()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.revenue_components c where c.revenue_entry_id = new.id) then
    perform app.refuse('KM024', 'revenue_without_components',
      'A revenue entry must have at least one component.',
      jsonb_build_object('revenue_entry_id', new.id));
  end if;
  return null;
end; $$;

drop trigger if exists trg_revenue_has_components on public.revenue_entries;
create constraint trigger trg_revenue_has_components
  after insert or update on public.revenue_entries
  deferrable initially deferred
  for each row execute function app.assert_revenue_has_components();

create index if not exists revenue_entries_ledger_idx
  on public.revenue_entries (org_id, business_unit_id, business_date desc);
create index if not exists revenue_entries_period_idx
  on public.revenue_entries (org_id, pnl_period_key);
create index if not exists revenue_entries_day_idx
  on public.revenue_entries (org_id, business_unit_id, revenue_category_id, business_date)
  where voided_at is null;
create index if not exists revenue_components_entry_idx
  on public.revenue_components (revenue_entry_id);
create index if not exists revenue_tax_rates_resolution_idx
  on public.revenue_tax_rates (revenue_category_id, effective_from) where archived_at is null;
create index if not exists revenue_value_bands_category_idx
  on public.revenue_value_bands (revenue_category_id) where archived_at is null;
create index if not exists revenue_supply_subtypes_category_idx
  on public.revenue_supply_subtypes (revenue_category_id) where archived_at is null;
create index if not exists business_unit_tax_statuses_timeline_idx
  on public.business_unit_tax_statuses (business_unit_id, effective_from desc);

alter table public.revenue_entries            enable row level security;
alter table public.revenue_components         enable row level security;
alter table public.revenue_value_bands        enable row level security;
alter table public.revenue_supply_subtypes    enable row level security;
alter table public.business_unit_tax_statuses enable row level security;

alter table public.revenue_entries            force row level security;
alter table public.revenue_components         force row level security;
alter table public.revenue_value_bands        force row level security;
alter table public.revenue_supply_subtypes    force row level security;
alter table public.business_unit_tax_statuses force row level security;

-- Policies call the PUBLISHED helper, never the internal `app` schema, which
-- `authenticated` cannot reach — the mistake that made every table 403 in Phase 2 (D-045).
drop policy if exists revenue_entries_read on public.revenue_entries;
create policy revenue_entries_read on public.revenue_entries
  for select to authenticated
  using (org_id = public.current_org_id()
         and public.has_capability('revenue.view.all', business_unit_id));

drop policy if exists revenue_components_read on public.revenue_components;
create policy revenue_components_read on public.revenue_components
  for select to authenticated
  using (exists (select 1 from public.revenue_entries e where e.id = revenue_components.revenue_entry_id));

drop policy if exists revenue_value_bands_read on public.revenue_value_bands;
create policy revenue_value_bands_read on public.revenue_value_bands
  for select to authenticated using (org_id = public.current_org_id());

drop policy if exists revenue_supply_subtypes_read on public.revenue_supply_subtypes;
create policy revenue_supply_subtypes_read on public.revenue_supply_subtypes
  for select to authenticated using (org_id = public.current_org_id());

drop policy if exists business_unit_tax_statuses_read on public.business_unit_tax_statuses;
create policy business_unit_tax_statuses_read on public.business_unit_tax_statuses
  for select to authenticated
  using (org_id = public.current_org_id()
         and public.has_capability('revenue.view.all', business_unit_id));

-- No client role holds INSERT, UPDATE or DELETE on any of these, and no SELECT on the
-- financial tables: reads go through the projection (D-037).
revoke all on public.revenue_entries            from anon, authenticated;
revoke all on public.revenue_components         from anon, authenticated;
revoke all on public.revenue_value_bands        from anon, authenticated;
revoke all on public.revenue_supply_subtypes    from anon, authenticated;
revoke all on public.business_unit_tax_statuses from anon, authenticated;

grant select on public.revenue_value_bands        to authenticated;
grant select on public.revenue_supply_subtypes    to authenticated;
grant select on public.business_unit_tax_statuses to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 2 · The conditional tax doctrine, made authoritative
-- ═════════════════════════════════════════════════════════════════════════════
--
-- D-094: for any fact set at a business date, ZERO or EXACTLY ONE rule may match. Zero
-- refuses, one resolves, more than one is a configuration defect and is refused. There is
-- no most-specific-wins and no runtime tiebreak.
--
-- A NULL discriminator means "does not depend on that dimension", which means it matches
-- EVERY value of it. So a wildcard rule and a specific rule over overlapping dates both
-- match the same entry: they COLLIDE rather than the specific one winning.

-- Two active rules for one category have overlapping applicability when their date ranges
-- overlap AND, on every discriminator, either is a wildcard or they name the same thing.
--
-- Value bands are compared by their TARIFF RANGE, not merely by id: two distinct band
-- rows can describe overlapping ranges, and distinct ids must not be able to hide
-- overlapping financial applicability. Band boundaries are write-once (D-100), so a range
-- compared today means the same thing tomorrow.
create or replace function app.revenue_rules_overlap(
  p_left  public.revenue_tax_rates,
  p_right public.revenue_tax_rates
)
returns boolean language sql stable security definer set search_path = '' as $$
  select
    p_left.revenue_category_id = p_right.revenue_category_id
    and daterange(p_left.effective_from, p_left.effective_to, '[)')
        && daterange(p_right.effective_from, p_right.effective_to, '[)')
    and (
      p_left.value_band_id is null
      or p_right.value_band_id is null
      or p_left.value_band_id = p_right.value_band_id
      or exists (
        select 1
          from public.revenue_value_bands bl, public.revenue_value_bands br
         where bl.id = p_left.value_band_id
           and br.id = p_right.value_band_id
           and int8range(coalesce(bl.floor_minor, 0), bl.ceiling_minor, '[)')
               && int8range(coalesce(br.floor_minor, 0), br.ceiling_minor, '[)')
      )
    )
    and (
      p_left.supply_subtype_id is null
      or p_right.supply_subtype_id is null
      or p_left.supply_subtype_id = p_right.supply_subtype_id
    )
    and (
      p_left.premises_status_code is null
      or p_right.premises_status_code is null
      or p_left.premises_status_code = p_right.premises_status_code
    );
$$;

comment on function app.revenue_rules_overlap is
  'True when two rules could both match one fact set (D-094). NULL is a wildcard and collides with everything; value bands are compared by tariff range, so distinct ids cannot hide overlapping applicability.';

-- D-095. A validating trigger checks rows visible to its own transaction. Two concurrent
-- inserts can each be individually valid while their pair is ambiguous — classic write
-- skew, which no amount of careful validation inside one transaction can detect.
--
-- The key is derived with hashtextextended over the org and category uuids: a stable
-- Postgres builtin, identical in every session and across restarts, NOT a process-local
-- hash. Scoped to (org, category) so configuring Restaurant never blocks Room.
create or replace function app.lock_revenue_category(p_org uuid, p_category uuid)
returns void language sql security definer set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended(p_org::text || ':' || p_category::text, 0));
$$;

comment on function app.lock_revenue_category is
  'Transaction-level advisory lock keyed deterministically on (org, revenue category). Serialises tax-rule configuration for one category so two concurrent writes cannot jointly create an ambiguous set (D-095).';

create or replace function app.assert_revenue_rules_unambiguous(p_rule_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_rule  public.revenue_tax_rates;
  v_other public.revenue_tax_rates;
begin
  select * into v_rule from public.revenue_tax_rates where id = p_rule_id;
  if not found or v_rule.archived_at is not null then
    return;
  end if;

  for v_other in
    select * from public.revenue_tax_rates
     where revenue_category_id = v_rule.revenue_category_id
       and id <> v_rule.id
       and archived_at is null
  loop
    if app.revenue_rules_overlap(v_rule, v_other) then
      perform app.refuse('KM025', 'ambiguous_tax_configuration',
        'Another tax rule already applies to the same revenue over the same dates. Two rules that could both match one entry would make its tax ambiguous, and no rule is ever chosen by ranking.',
        jsonb_build_object('rule_id', v_rule.id, 'conflicts_with', v_other.id));
    end if;
  end loop;
end; $$;

-- On the trigger, so no write path can skip it — including a direct table write, the
-- legacy Phase 2 tax_rule_create, or an archive that changes applicability.
create or replace function app.guard_revenue_rule_write()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_row public.revenue_tax_rates;
begin
  v_row := case when tg_op = 'DELETE' then old else new end;
  perform app.lock_revenue_category(v_row.org_id, v_row.revenue_category_id);
  if tg_op <> 'DELETE' then
    perform app.assert_revenue_rules_unambiguous(new.id);
  end if;
  return null;
end; $$;

drop trigger if exists trg_revenue_rule_unambiguous on public.revenue_tax_rates;
create constraint trigger trg_revenue_rule_unambiguous
  after insert or update on public.revenue_tax_rates
  deferrable initially immediate
  for each row execute function app.guard_revenue_rule_write();

-- ONLY NOW is the Phase 2 constraint obsolete. The replacement exists above, so no window
-- opens in which ambiguity could be written. The old constraint was
-- `exclude using gist (revenue_category_id with =, daterange &&)`: correct for a date-only
-- model and impossible for D-081, because Room's two value bands are by construction two
-- live rules for one category over the same dates (D-093).
alter table public.revenue_tax_rates drop constraint if exists revenue_tax_rates_no_overlap;

do $$
begin
  if not exists (
    select 1 from pg_trigger
     where tgname = 'trg_revenue_rule_unambiguous'
       and tgrelid = 'public.revenue_tax_rates'::regclass
  ) then
    raise exception 'refusing to leave revenue_tax_rates unguarded: the replacement trigger is absent';
  end if;
  if exists (select 1 from pg_constraint where conname = 'revenue_tax_rates_no_overlap') then
    raise exception 'the obsolete Phase 2 exclusion constraint is still present';
  end if;
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 3 · Resolution, arithmetic, numbering and the read boundary
-- ═════════════════════════════════════════════════════════════════════════════

-- Inputs are explicit FACTS, never a caller-supplied tax result. The server resolves
-- independently and its answer is final (D-037).
create or replace function app.resolve_revenue_rule(
  p_category uuid,
  p_date     date,
  p_band     uuid default null,
  p_subtype  uuid default null,
  p_premises text default null
)
returns public.revenue_tax_rates
language plpgsql stable security definer set search_path = '' as $$
declare
  v_matches public.revenue_tax_rates[];
  v_rule    public.revenue_tax_rates;
  v_needs   text;
begin
  select array_agg(r) into v_matches
    from public.revenue_tax_rates r
   where r.revenue_category_id = p_category
     and r.archived_at is null
     and r.effective_from <= p_date
     and (r.effective_to is null or r.effective_to > p_date)
     -- A null discriminator on the RULE is a wildcard and matches anything. A null on the
     -- FACTS against a specific rule is not a match: the entry has not stated the thing
     -- the rule is about.
     and (r.value_band_id is null or r.value_band_id = p_band)
     and (r.supply_subtype_id is null or r.supply_subtype_id = p_subtype)
     and (r.premises_status_code is null or r.premises_status_code = p_premises);

  if v_matches is null or array_length(v_matches, 1) is null then
    -- Distinguish "no rule exists" from "you have not told it which band this is". The
    -- remedies differ and so must the messages.
    select case
             when bool_or(r.value_band_id is not null) and p_band is null then 'value band'
             when bool_or(r.supply_subtype_id is not null) and p_subtype is null then 'supply subtype'
             when bool_or(r.premises_status_code is not null) and p_premises is null then 'premises tax status'
           end
      into v_needs
      from public.revenue_tax_rates r
     where r.revenue_category_id = p_category
       and r.archived_at is null
       and r.effective_from <= p_date
       and (r.effective_to is null or r.effective_to > p_date);

    if v_needs is not null then
      perform app.refuse('KM026', 'missing_tax_fact',
        'This revenue entry needs a ' || v_needs || ' before its tax can be determined.',
        jsonb_build_object('dimension', v_needs));
    end if;

    perform app.refuse('KM027', 'no_tax_rule',
      'No tax rule configured for this revenue entry.',
      jsonb_build_object('revenue_category_id', p_category, 'business_date', p_date));
  end if;

  if array_length(v_matches, 1) > 1 then
    perform app.refuse('KM025', 'ambiguous_tax_configuration',
      'More than one tax rule applies to this revenue entry. The tax configuration must be corrected before this can be recorded.',
      jsonb_build_object('matches', array_length(v_matches, 1)));
  end if;

  v_rule := v_matches[1];

  if v_rule.input_basis is null then
    perform app.refuse('KM028', 'incomplete_tax_rule',
      'The tax rule that applies here is incomplete: it does not say which amount is entered. It must be corrected before revenue can be recorded against it.',
      jsonb_build_object('rule_id', v_rule.id));
  end if;

  return v_rule;
end; $$;

comment on function app.resolve_revenue_rule is
  'Zero or exactly one (D-094). Takes facts, never a caller-supplied tax result. KM025 ambiguous, KM026 missing fact, KM027 no rule, KM028 incomplete.';

-- The same specification as Dart's TaxRule.compute. Half-up is (2n + d) / (2d) on
-- integers, which rounds .5 away from zero without ever touching a floating point value.
create or replace function app.revenue_compute(
  p_entered bigint, p_rate_bp integer, p_treatment text
)
returns table (gross bigint, tax bigint, net bigint)
language plpgsql immutable security invoker set search_path = '' as $$
declare
  v_tax bigint;
begin
  if p_entered < 0 then
    raise exception 'revenue must not be negative';
  end if;
  if p_treatment = 'none' then
    return query select p_entered, 0::bigint, p_entered;
  elsif p_treatment = 'inclusive' then
    v_tax := (2 * p_entered * p_rate_bp + (10000 + p_rate_bp)) / (2 * (10000 + p_rate_bp));
    return query select p_entered, v_tax, p_entered - v_tax;
  elsif p_treatment = 'exclusive' then
    v_tax := (2 * p_entered * p_rate_bp + 10000) / 20000;
    return query select p_entered + v_tax, v_tax, p_entered;
  else
    raise exception 'unknown treatment %', p_treatment;
  end if;
end; $$;

comment on function app.revenue_compute is
  'The canonical integer half-up specification, shared with Dart TaxRule.compute. No floating point ever touches a currency amount.';

-- KI-REV numbering: organisation-wide, Indian financial year, its OWN sequence.
create table if not exists public.revenue_number_counters (
  org_id         uuid not null references public.organizations(id) on delete restrict,
  financial_year text not null,
  last_value     bigint not null default 0,
  primary key (org_id, financial_year)
);

alter table public.revenue_number_counters enable row level security;
alter table public.revenue_number_counters force row level security;
revoke all on public.revenue_number_counters from anon, authenticated;

create or replace function app.revenue_financial_year(p_date date)
returns text language sql immutable security invoker set search_path = '' as $$
  -- 1 April - 31 March (D-014). 15 June 2026 is FY 26-27.
  select case
    when extract(month from p_date) >= 4
      then to_char(p_date, 'YY') || '-' || to_char(p_date + interval '1 year', 'YY')
    else to_char(p_date - interval '1 year', 'YY') || '-' || to_char(p_date, 'YY')
  end;
$$;

create or replace function app.next_revenue_number(p_org uuid, p_date date)
returns table (number text, financial_year text)
language plpgsql security definer set search_path = '' as $$
declare
  v_fy   text := app.revenue_financial_year(p_date);
  v_next bigint;
begin
  -- Concurrency-safe by construction: the upsert takes a row lock on exactly this
  -- (org, financial year), so two concurrent acceptances serialise on the counter and
  -- neither can read the same last_value. Gaps are avoided because the number is issued
  -- only after every validation has passed.
  insert into public.revenue_number_counters (org_id, financial_year, last_value)
       values (p_org, v_fy, 1)
  on conflict (org_id, financial_year)
    do update set last_value = public.revenue_number_counters.last_value + 1
  returning public.revenue_number_counters.last_value into v_next;

  return query select 'KI-REV-' || v_fy || '-' || lpad(v_next::text, 6, '0'), v_fy;
end; $$;

comment on function app.next_revenue_number is
  'KI-REV-26-27-000001. Organisation-wide, FY-reset, separate from the expense sequence, issued only after canonical acceptance.';

-- The read boundary. `security_barrier`, not `security_invoker`: the view runs as its
-- owner and carries its OWN authorisation predicate, so the base tables stay ungranted
-- and the projection is the only way in. (security_invoker was tried first and failed for
-- every authorised user, because the caller holds no SELECT on revenue_entries — caught
-- by the live security test.)
drop view if exists public.revenue_component_detail;
drop view if exists public.revenue_document;

create view public.revenue_document
with (security_barrier = true) as
select
  e.id, e.org_id, e.txn_number, e.financial_year,
  e.business_unit_id, e.revenue_category_id,
  e.business_date, e.pnl_period_key, e.entry_kind,
  e.source_reference, e.notes, e.created_by, e.created_at, e.updated_at,
  e.voided_at, e.void_reason, e.row_version, e.change_seq,
  coalesce(t.gross_minor, 0)     as gross_amount_minor,
  coalesce(t.tax_minor, 0)       as tax_amount_minor,
  coalesce(t.net_minor, 0)       as net_amount_minor,
  coalesce(t.component_count, 0) as component_count
from public.revenue_entries e
left join lateral (
  select sum(c.gross_amount_minor) as gross_minor,
         sum(c.tax_amount_minor)   as tax_minor,
         sum(c.net_amount_minor)   as net_minor,
         count(*)                  as component_count
    from public.revenue_components c
   where c.revenue_entry_id = e.id
) t on true
where e.org_id = public.current_org_id()
  and public.has_capability('revenue.view.all', e.business_unit_id);

comment on view public.revenue_document is
  'The only revenue header a client reads. Totals are SUMS OF COMPONENTS, never a stored header value (D-078). Never grant SELECT on public.revenue_entries to a client role.';

create view public.revenue_component_detail
with (security_barrier = true) as
select c.* from public.revenue_components c
 where exists (
   select 1 from public.revenue_entries e
    where e.id = c.revenue_entry_id
      and e.org_id = public.current_org_id()
      and public.has_capability('revenue.view.all', e.business_unit_id)
 );

comment on view public.revenue_component_detail is
  'Components, visible only through an authorised parent document. One predicate, in one place.';

revoke all on public.revenue_document         from anon, public;
revoke all on public.revenue_component_detail from anon, public;
grant select on public.revenue_document         to authenticated;
grant select on public.revenue_component_detail to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 4 · The mutation boundary
-- ═════════════════════════════════════════════════════════════════════════════
--
-- The caller supplies FACTS and ENTERED AMOUNTS. It does not get to dictate the rate, the
-- tax, the net or the rule snapshot: the server resolves and computes those, and its
-- answer is canonical (D-037).

create or replace function public.revenue_tax_rule_create(
  p_revenue_category_id uuid,
  p_rate_bp             integer,
  p_treatment           text,
  p_effective_from      date,
  p_input_basis         text,
  p_effective_to        date default null,
  p_value_band_id       uuid default null,
  p_supply_subtype_id   uuid default null,
  p_premises_status_code text default null,
  p_note                text default null,
  p_mutation_id         uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_unit uuid; v_replay jsonb; v_id uuid;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Capability before existence (D-046): an unauthorised caller must not be able to use
  -- "unknown category" versus "no permission" to discover what exists.
  perform app.require_capability_anywhere('tax.manage');

  select business_unit_id into v_unit
    from public.revenue_categories
   where id = p_revenue_category_id and org_id = v_org;
  if v_unit is null then
    perform app.refuse('KM015', 'unknown_entity', 'That revenue category does not exist.', '{}'::jsonb);
  end if;
  perform app.require_capability('tax.manage', v_unit);

  -- Serialise configuration for this category BEFORE validating, so two concurrent
  -- writers cannot each validate against a state that does not yet contain the other's
  -- row and jointly create an ambiguous set (D-095).
  perform app.lock_revenue_category(v_org, p_revenue_category_id);

  insert into public.revenue_tax_rates (
    org_id, business_unit_id, revenue_category_id, rate_bp, treatment,
    effective_from, effective_to, input_basis, value_band_id,
    supply_subtype_id, premises_status_code, note, created_by)
  values (
    v_org, v_unit, p_revenue_category_id, p_rate_bp, p_treatment,
    p_effective_from, p_effective_to, p_input_basis, p_value_band_id,
    p_supply_subtype_id, p_premises_status_code, p_note, v_actor)
  returning id into v_id;

  -- The trigger validates too; calling it here means the refusal happens inside this
  -- function, where the lock is provably already held.
  perform app.assert_revenue_rules_unambiguous(v_id);

  perform app.write_audit(v_org, 'revenue_tax_rate', v_id, 'created', v_actor, null,
    jsonb_build_object('rate_bp', p_rate_bp, 'treatment', p_treatment,
                       'input_basis', p_input_basis, 'effective_from', p_effective_from,
                       'value_band_id', p_value_band_id,
                       'supply_subtype_id', p_supply_subtype_id,
                       'premises_status_code', p_premises_status_code),
    null, v_unit, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_tax_rate', v_id, 'create',
    jsonb_build_object('id', v_id, 'status', 'created'));
end; $$;

create or replace function public.revenue_tax_rule_end_date(
  p_rule_id uuid, p_effective_to date, p_mutation_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_rule public.revenue_tax_rates; v_replay jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_capability_anywhere('tax.manage');

  select * into v_rule from public.revenue_tax_rates where id = p_rule_id and org_id = v_org;
  if not found then
    perform app.refuse('KM015', 'unknown_entity', 'That tax rule does not exist.', '{}'::jsonb);
  end if;
  perform app.require_capability('tax.manage', v_rule.business_unit_id);

  -- End-dating changes applicability, so it takes the same lock.
  perform app.lock_revenue_category(v_org, v_rule.revenue_category_id);

  update public.revenue_tax_rates
     set effective_to = p_effective_to, updated_at = now(), row_version = row_version + 1
   where id = p_rule_id;

  perform app.write_audit(v_org, 'revenue_tax_rate', p_rule_id, 'end_dated', v_actor,
    to_jsonb(v_rule), jsonb_build_object('effective_to', p_effective_to),
    null, v_rule.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_tax_rate', p_rule_id, 'end_date',
    jsonb_build_object('id', p_rule_id, 'status', 'ended'));
end; $$;

create or replace function public.revenue_create(
  p_id uuid,
  p_business_unit_id uuid,
  p_revenue_category_id uuid,
  p_business_date date,
  p_components jsonb,
  p_entry_kind text default 'daily_summary',
  p_source_reference text default null,
  p_notes text default null,
  p_captured_at timestamptz default null,
  p_mutation_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_replay jsonb; v_comp jsonb;
  v_rule public.revenue_tax_rates; v_calc record;
  v_number text; v_fy text;
  v_band public.revenue_value_bands; v_subtype public.revenue_supply_subtypes;
  v_count integer := 0;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  perform app.require_capability_anywhere('revenue.create');
  perform app.require_capability('revenue.create', p_business_unit_id);

  if not exists (
    select 1 from public.revenue_categories
     where id = p_revenue_category_id and org_id = v_org
       and business_unit_id = p_business_unit_id and archived_at is null
  ) then
    perform app.refuse('KM015', 'unknown_entity',
      'That revenue category does not belong to that business unit, or is archived.', '{}'::jsonb);
  end if;

  perform app.require_period_open(to_char(p_business_date, 'YYYY-MM'), p_business_unit_id);

  if jsonb_array_length(coalesce(p_components, '[]'::jsonb)) = 0 then
    perform app.refuse('KM024', 'revenue_without_components',
      'A revenue entry must have at least one component.', '{}'::jsonb);
  end if;

  insert into public.revenue_entries (
    id, org_id, business_unit_id, revenue_category_id, business_date,
    pnl_period_key, captured_at, entry_kind, source_reference, notes, created_by)
  values (
    p_id, v_org, p_business_unit_id, p_revenue_category_id, p_business_date,
    to_char(p_business_date, 'YYYY-MM'), coalesce(p_captured_at, now()),
    p_entry_kind, p_source_reference, p_notes, v_actor);

  for v_comp in select * from jsonb_array_elements(p_components)
  loop
    -- The server resolves. Anything the caller sent about rate or tax is ignored, not
    -- trusted and then checked.
    v_rule := app.resolve_revenue_rule(
      p_revenue_category_id, p_business_date,
      nullif(v_comp->>'value_band_id', '')::uuid,
      nullif(v_comp->>'supply_subtype_id', '')::uuid,
      nullif(v_comp->>'premises_status_code', ''));

    select * into v_calc from app.revenue_compute(
      (v_comp->>'entered_amount_minor')::bigint, v_rule.rate_bp, v_rule.treatment);

    select * into v_band from public.revenue_value_bands where id = v_rule.value_band_id;
    select * into v_subtype from public.revenue_supply_subtypes where id = v_rule.supply_subtype_id;

    insert into public.revenue_components (
      id, org_id, revenue_entry_id, entered_amount_minor, entered_basis,
      gross_amount_minor, tax_amount_minor, net_amount_minor,
      tax_rule_id, tax_rate_bp, tax_treatment,
      value_band_id, value_band_label, value_band_floor_minor, value_band_ceiling_minor,
      supply_subtype_id, supply_subtype_label, premises_status_code)
    values (
      coalesce(nullif(v_comp->>'id','')::uuid, extensions.gen_random_uuid()),
      v_org, p_id,
      (v_comp->>'entered_amount_minor')::bigint,
      v_rule.input_basis,
      v_calc.gross, v_calc.tax, v_calc.net,
      v_rule.id, v_rule.rate_bp, v_rule.treatment,
      v_rule.value_band_id, v_band.label, v_band.floor_minor, v_band.ceiling_minor,
      v_rule.supply_subtype_id, v_subtype.label, v_rule.premises_status_code);
    v_count := v_count + 1;
  end loop;

  -- Numbering only after every validation has passed, so a refused attempt burns no
  -- number.
  select number, financial_year into v_number, v_fy
    from app.next_revenue_number(v_org, p_business_date);

  update public.revenue_entries
     set txn_number = v_number, financial_year = v_fy
   where id = p_id;

  perform app.write_audit(v_org, 'revenue_entry', p_id, 'created', v_actor, null,
    jsonb_build_object('txn_number', v_number, 'business_date', p_business_date,
                       'components', v_count),
    null, p_business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'create',
    jsonb_build_object('id', p_id, 'txn_number', v_number,
                       'financial_year', v_fy, 'row_version', 1, 'status', 'created'));
end; $$;

create or replace function public.revenue_void(
  p_id uuid, p_base_row_version integer, p_reason text, p_mutation_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_entry public.revenue_entries; v_replay jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_capability_anywhere('revenue.void');

  if coalesce(trim(p_reason), '') = '' then
    perform app.refuse('KM008', 'reason_required', 'A void must state why.', '{}'::jsonb);
  end if;

  select * into v_entry from public.revenue_entries where id = p_id and org_id = v_org;
  if not found then
    perform app.refuse('KM015', 'unknown_entity', 'That revenue entry does not exist.', '{}'::jsonb);
  end if;

  perform app.require_capability('revenue.void', v_entry.business_unit_id);
  perform app.require_period_open(v_entry.pnl_period_key, v_entry.business_unit_id);

  -- A different mutation voiding an already-voided document with a matching version is an
  -- audited no-op; a stale one is a conflict (D-021).
  if v_entry.voided_at is not null and v_entry.row_version = p_base_row_version then
    return app.remember_mutation(p_mutation_id, v_org, v_actor,
      'revenue_entry', p_id, 'void',
      jsonb_build_object('id', p_id, 'row_version', v_entry.row_version,
                         'status', 'already_voided'));
  end if;

  if v_entry.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'This revenue entry changed since you loaded it. Review the latest version before voiding.',
      jsonb_build_object('expected', p_base_row_version, 'actual', v_entry.row_version));
  end if;

  update public.revenue_entries
     set voided_at = now(), voided_by = v_actor, void_reason = p_reason,
         row_version = row_version + 1, updated_at = now(), updated_by = v_actor
   where id = p_id;

  perform app.write_audit(v_org, 'revenue_entry', p_id, 'voided', v_actor,
    to_jsonb(v_entry), jsonb_build_object('void_reason', p_reason),
    p_reason, v_entry.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'void',
    jsonb_build_object('id', p_id, 'row_version', v_entry.row_version + 1, 'status', 'voided'));
end; $$;

-- Nothing is callable that has not been reviewed (D-044).
revoke all on function public.revenue_tax_rule_create(uuid, integer, text, date, text, date, uuid, uuid, text, text, uuid) from public, anon;
revoke all on function public.revenue_tax_rule_end_date(uuid, date, uuid) from public, anon;
revoke all on function public.revenue_create(uuid, uuid, uuid, date, jsonb, text, text, text, timestamptz, uuid) from public, anon;
revoke all on function public.revenue_void(uuid, integer, text, uuid) from public, anon;

grant execute on function public.revenue_tax_rule_create(uuid, integer, text, date, text, date, uuid, uuid, text, text, uuid) to authenticated;
grant execute on function public.revenue_tax_rule_end_date(uuid, date, uuid) to authenticated;
grant execute on function public.revenue_create(uuid, uuid, uuid, date, jsonb, text, text, text, timestamptz, uuid) to authenticated;
grant execute on function public.revenue_void(uuid, integer, text, uuid) to authenticated;

-- The internal helpers stay in `app`, which `authenticated` cannot reach.
revoke all on function app.resolve_revenue_rule(uuid, date, uuid, uuid, text) from public, anon, authenticated;
revoke all on function app.revenue_compute(bigint, integer, text) from public, anon, authenticated;
revoke all on function app.next_revenue_number(uuid, date) from public, anon, authenticated;
revoke all on function app.lock_revenue_category(uuid, uuid) from public, anon, authenticated;
revoke all on function app.revenue_financial_year(date) from public, anon, authenticated;
revoke all on function app.assert_revenue_rules_unambiguous(uuid) from public, anon, authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 5 · The verified FY 2026-27 baseline (D-096)
-- ═════════════════════════════════════════════════════════════════════════════
--
--   Restaurant  5%    inclusive   inclusive_total
--   Nandbhog    5%    inclusive   inclusive_total   (independent of Restaurant)
--   Room        5%    inclusive   inclusive_total   (generic; NO band is seeded)
--   Banquet     none  --          inclusive_total   (no dormant 5% alternative)
--
-- The Restaurant invoice shows CGST 2.5% + SGST 2.5%. The MIS records the TOTAL rate,
-- because V1 derives Net Sales and builds no GST filing engine (spec 8.1, 29). The
-- jurisdictional split is preserved in documentation, not in this schema.
--
-- Masters are resolved by their canonical immutable CODES. No environment UUID appears
-- anywhere here, and the migration fails loudly rather than guessing.
do $$
declare
  v_org uuid; v_actor uuid; v_units integer; r record;
  v_unit uuid; v_cat uuid; v_id uuid;
begin
  select count(*) into v_units from public.organizations;
  if v_units <> 1 then
    raise exception 'refusing to install the baseline: expected exactly one organisation, found %', v_units;
  end if;
  select id into v_org from public.organizations;

  select p.id into v_actor
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id and ur.revoked_at is null
    join public.roles ro on ro.id = ur.role_id and ro.code = 'owner'
   order by p.created_at limit 1;
  if v_actor is null then
    raise exception 'refusing to install the baseline: no owner profile exists to attribute it to';
  end if;

  for r in
    select * from (values
      ('CCR', 'RESTAURANT',  500, 'inclusive', 'inclusive_total'),
      ('CCR', 'NANDBHOG',    500, 'inclusive', 'inclusive_total'),
      ('HKI', 'ROOM',        500, 'inclusive', 'inclusive_total'),
      ('HKI', 'BANQUET',       0, 'none',      'inclusive_total')
    ) as t(unit_code, cat_code, rate_bp, treatment, input_basis)
  loop
    select id into v_unit from public.business_units
     where org_id = v_org and code = r.unit_code and archived_at is null;
    if v_unit is null then
      raise exception 'baseline: business unit % does not exist', r.unit_code;
    end if;
    if (select count(*) from public.business_units
         where org_id = v_org and code = r.unit_code and archived_at is null) <> 1 then
      raise exception 'baseline: business unit % is ambiguous', r.unit_code;
    end if;

    select id into v_cat from public.revenue_categories
     where org_id = v_org and code = r.cat_code and business_unit_id = v_unit
       and archived_at is null;
    if v_cat is null then
      raise exception 'baseline: revenue category % does not exist under business unit %',
        r.cat_code, r.unit_code;
    end if;
    if (select count(*) from public.revenue_categories
         where org_id = v_org and code = r.cat_code and business_unit_id = v_unit
           and archived_at is null) <> 1 then
      raise exception 'baseline: revenue category % under % is ambiguous', r.cat_code, r.unit_code;
    end if;

    -- Idempotent by intent rather than by ON CONFLICT: if a live rule already covers this
    -- category from this date, leave it alone and say so. Silently rewriting configured
    -- tax would be exactly the thing this project refuses to do.
    if exists (
      select 1 from public.revenue_tax_rates
       where revenue_category_id = v_cat and archived_at is null
         and effective_from = date '2026-04-01'
    ) then
      raise notice 'baseline: % / % already configured from 2026-04-01, left untouched',
        r.unit_code, r.cat_code;
      continue;
    end if;

    perform app.lock_revenue_category(v_org, v_cat);

    insert into public.revenue_tax_rates (
      org_id, business_unit_id, revenue_category_id, rate_bp, treatment,
      effective_from, input_basis, note, created_by)
    values (
      v_org, v_unit, v_cat, r.rate_bp, r.treatment, date '2026-04-01', r.input_basis,
      'Verified FY 2026-27 baseline (D-096). Source: current billing evidence confirmed by the project lead 2026-09-01.',
      v_actor)
    returning id into v_id;

    perform app.assert_revenue_rules_unambiguous(v_id);

    perform app.write_audit(v_org, 'revenue_tax_rate', v_id, 'created', v_actor, null,
      jsonb_build_object('source', 'verified baseline migration',
                         'unit', r.unit_code, 'category', r.cat_code,
                         'rate_bp', r.rate_bp, 'treatment', r.treatment,
                         'input_basis', r.input_basis, 'effective_from', '2026-04-01'),
      'Initial verified configuration installed by migration (D-096)', v_unit, null);
  end loop;
end $$;

-- Prove the intended end state: exactly four live rules, and NOTHING speculative.
do $$
declare v_rules integer; v_bands integer; v_subs integer; v_stats integer;
begin
  select count(*) into v_rules from public.revenue_tax_rates where archived_at is null;
  select count(*) into v_bands from public.revenue_value_bands;
  select count(*) into v_subs  from public.revenue_supply_subtypes;
  select count(*) into v_stats from public.business_unit_tax_statuses;

  if v_rules <> 4 then
    raise exception 'baseline: expected exactly 4 live tax rules, found %', v_rules;
  end if;
  if v_bands <> 0 then
    raise exception 'baseline: no value band may be seeded, found %', v_bands;
  end if;
  if v_subs <> 0 then
    raise exception 'baseline: no supply subtype may be seeded, found %', v_subs;
  end if;
  if v_stats <> 0 then
    raise exception 'baseline: no premises status may be seeded, found %', v_stats;
  end if;
end $$;
