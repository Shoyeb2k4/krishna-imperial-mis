-- Server migration ledger: 20260901115849  revenue_tables
--
-- One file per ledger version (A0). The previous Slice 4 commit collapsed seven
-- ledger versions into two files, which is not provenance.
--
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
