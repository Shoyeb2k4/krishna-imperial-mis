-- ─────────────────────────────────────────────────────────────────────────────
-- 0003 · Master data, with the hierarchy made structurally impossible to break
--
--     Business Unit → Department → Section → Expense Category
--
-- Owner requirement §4: the database must reject impossible structures even if the
-- client is modified. A plain parent foreign key does not achieve that. `sections.
-- department_id → departments(id)` guarantees the department exists; it says nothing
-- about which *property* that department belongs to, so nothing stops a Hotel Krishna
-- section being re-pointed at a Crystal Canopy department.
--
-- The fix is a **composite foreign-key ladder**. Each level carries its ancestors and
-- references the parent by the whole tuple:
--
--     departments        (org_id, business_unit_id)                → business_units(org_id, id)
--     sections           (org_id, business_unit_id, department_id) → departments(org_id, business_unit_id, id)
--     expense_categories (org_id, business_unit_id, department_id, section_id)
--                                                                 → sections(org_id, business_unit_id, department_id, id)
--
-- The ancestor columns are **not** free-floating denormalised copies — that is exactly
-- what the owner warned against. Each is pinned by the composite key above, so it is
-- arithmetically incapable of disagreeing with the real parent: to make a section claim
-- the wrong business unit you would have to name a (business_unit_id, department_id) pair
-- that does not exist in `departments`, and the foreign key refuses it. Consistency is
-- transactional because it is the same constraint, checked at the same moment, as the
-- parent link itself.
--
-- Two further properties fall out of this, both wanted:
--   · Re-parenting a department to a different business unit fails while it has sections,
--     because their tuples would no longer resolve. Cross-property moves are impossible
--     rather than merely discouraged.
--   · A Phase 3 expense allocation line can validate its whole classification with **one**
--     foreign key against `expense_categories(id, section_id, department_id,
--     business_unit_id)` — no trigger, no application check, no possible drift.
--
-- Recorded as D-040.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Business units ───────────────────────────────────────────────────────────
create table if not exists public.business_units (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid        not null references public.organizations(id) on delete restrict,
  code                text        not null,
  name                text        not null,
  kind                text        not null default 'other'
                        check (kind in ('restaurant', 'hotel', 'other')),
  -- IANA zone and cut-off per property. Changing the cut-off affects future derivations
  -- only; persisted business dates are never restated (D-019).
  timezone            text        not null default 'Asia/Kolkata',
  business_day_cutoff time        not null default '05:00',
  sort_order          integer     not null default 0,
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  row_version         integer     not null default 1,
  change_seq          bigint      not null default nextval('app.global_change_seq'),
  constraint business_units_org_code_key unique (org_id, code),
  constraint business_units_org_id_key   unique (org_id, id)
);

-- ── Departments ──────────────────────────────────────────────────────────────
create table if not exists public.departments (
  id               uuid primary key default extensions.gen_random_uuid(),
  org_id           uuid        not null,
  business_unit_id uuid        not null,
  code             text        not null,
  name             text        not null,
  sort_order       integer     not null default 0,
  archived_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  row_version      integer     not null default 1,
  change_seq       bigint      not null default nextval('app.global_change_seq'),
  constraint departments_unit_fk
    foreign key (org_id, business_unit_id)
    references public.business_units (org_id, id) on delete restrict,
  constraint departments_unit_code_key unique (business_unit_id, code),
  constraint departments_chain_key     unique (org_id, business_unit_id, id)
);

-- ── Sections ─────────────────────────────────────────────────────────────────
create table if not exists public.sections (
  id               uuid primary key default extensions.gen_random_uuid(),
  org_id           uuid        not null,
  business_unit_id uuid        not null,
  department_id    uuid        not null,
  code             text        not null,
  name             text        not null,
  sort_order       integer     not null default 0,
  archived_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  row_version      integer     not null default 1,
  change_seq       bigint      not null default nextval('app.global_change_seq'),
  constraint sections_department_fk
    foreign key (org_id, business_unit_id, department_id)
    references public.departments (org_id, business_unit_id, id) on delete restrict,
  constraint sections_department_code_key unique (department_id, code),
  constraint sections_chain_key unique (org_id, business_unit_id, department_id, id)
);

-- ── Expense categories ───────────────────────────────────────────────────────
create table if not exists public.expense_categories (
  id                   uuid primary key default extensions.gen_random_uuid(),
  org_id               uuid        not null,
  business_unit_id     uuid        not null,
  department_id        uuid        not null,
  section_id           uuid        not null,
  code                 text        not null,
  name                 text        not null,
  nature               text        not null default 'operating'
                         check (nature in ('operating', 'payroll', 'utility', 'other')),
  -- A hint for the entry screen: electricity is usually split between properties. Never
  -- a rule — the user always decides the actual allocation (spec §7).
  is_shared_by_default boolean     not null default false,
  sort_order           integer     not null default 0,
  archived_at          timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  row_version          integer     not null default 1,
  change_seq           bigint      not null default nextval('app.global_change_seq'),
  constraint expense_categories_section_fk
    foreign key (org_id, business_unit_id, department_id, section_id)
    references public.sections (org_id, business_unit_id, department_id, id) on delete restrict,
  constraint expense_categories_section_code_key unique (section_id, code),
  -- The anchor a Phase 3 allocation line will reference with one composite key.
  constraint expense_categories_chain_key
    unique (id, section_id, department_id, business_unit_id)
);

-- ── Revenue categories ───────────────────────────────────────────────────────
-- No tax column here, deliberately. Tax is date-effective per category and lives in its
-- own table, so a rate set next April cannot restate last year's Net Sales (D-017).
-- Nandbhog is a category under Crystal Canopy, not a business unit (D-024).
create table if not exists public.revenue_categories (
  id               uuid primary key default extensions.gen_random_uuid(),
  org_id           uuid        not null,
  business_unit_id uuid        not null,
  code             text        not null,
  name             text        not null,
  sort_order       integer     not null default 0,
  archived_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  row_version      integer     not null default 1,
  change_seq       bigint      not null default nextval('app.global_change_seq'),
  constraint revenue_categories_unit_fk
    foreign key (org_id, business_unit_id)
    references public.business_units (org_id, id) on delete restrict,
  constraint revenue_categories_unit_code_key unique (business_unit_id, code),
  constraint revenue_categories_chain_key unique (org_id, business_unit_id, id)
);

-- ── Vendors ──────────────────────────────────────────────────────────────────
-- Organisation-level: a supplier serves the company, not one property. The optional
-- defaults simply pre-select during entry and are pinned to a real hierarchy path when
-- present. Name is the only requirement — GSTIN is never forced (owner requirement §12).
create table if not exists public.vendors (
  id                       uuid primary key default extensions.gen_random_uuid(),
  org_id                   uuid        not null references public.organizations(id) on delete restrict,
  code                     text        not null,
  name                     text        not null,
  gstin                    text,
  phone                    text,
  address                  text,
  notes                    text,
  default_business_unit_id uuid,
  default_category_id      uuid references public.expense_categories(id) on delete restrict,
  sort_order               integer     not null default 0,
  archived_at              timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  row_version              integer     not null default 1,
  change_seq               bigint      not null default nextval('app.global_change_seq'),
  constraint vendors_org_code_key unique (org_id, code),
  constraint vendors_default_unit_fk
    foreign key (org_id, default_business_unit_id)
    references public.business_units (org_id, id) on delete restrict
);

-- Names are unique per organisation, case-insensitively, among **live** vendors only.
-- Archiving must free the name for reuse; a plain unique constraint would hold it
-- hostage forever, which is not what archiving means.
create unique index if not exists vendors_org_name_live_key
  on public.vendors (org_id, lower(name)) where archived_at is null;

-- ── Payment methods ──────────────────────────────────────────────────────────
create table if not exists public.payment_methods (
  id                 uuid primary key default extensions.gen_random_uuid(),
  org_id             uuid        not null references public.organizations(id) on delete restrict,
  code               text        not null,
  name               text        not null,
  requires_reference boolean     not null default false,
  sort_order         integer     not null default 0,
  archived_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  row_version        integer     not null default 1,
  change_seq         bigint      not null default nextval('app.global_change_seq'),
  constraint payment_methods_org_code_key unique (org_id, code),
  constraint payment_methods_org_id_key   unique (org_id, id)
);

-- ── Shared write machinery ───────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['business_units', 'departments', 'sections',
                           'expense_categories', 'revenue_categories',
                           'vendors', 'payment_methods']
  loop
    execute format('drop trigger if exists touch_%1$s on public.%1$s', t);
    execute format(
      'create trigger touch_%1$s before insert or update on public.%1$s '
      'for each row execute function app.touch_row()', t);
    execute format(
      'create index if not exists %1$s_change_seq_idx on public.%1$s (org_id, change_seq)', t);
    execute format(
      'create index if not exists %1$s_live_idx on public.%1$s (org_id) where archived_at is null', t);
  end loop;
end $$;

create index if not exists departments_unit_idx        on public.departments (business_unit_id);
create index if not exists sections_department_idx     on public.sections (department_id);
create index if not exists expense_categories_sect_idx on public.expense_categories (section_id);
create index if not exists revenue_categories_unit_idx on public.revenue_categories (business_unit_id);
