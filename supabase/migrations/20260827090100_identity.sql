-- ─────────────────────────────────────────────────────────────────────────────
-- 0002 · Organisation, profiles, roles and the capability catalogue
--
-- Authorisation is expressed as capabilities, never as role names (master spec §13.1).
-- Roles exist only as bundles that hand capabilities out; no policy, function or
-- conditional anywhere in this schema branches on a role's name.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.organizations (
  id                         uuid primary key default extensions.gen_random_uuid(),
  name                       text        not null,
  legal_name                 text,
  financial_year_start_month smallint    not null default 4
                               check (financial_year_start_month between 1 and 12),
  timezone                   text        not null default 'Asia/Kolkata',
  base_currency              char(3)     not null default 'INR',
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  row_version                integer     not null default 1,
  change_seq                 bigint      not null default nextval('app.global_change_seq')
);

-- One profile per authenticated user. `org_id` is the tenancy anchor every RLS policy
-- keys on, and it is read from here — never from anything the client sends.
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete restrict,
  org_id      uuid        not null references public.organizations(id) on delete restrict,
  full_name   text        not null,
  email       text        not null,
  phone       text,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  row_version integer     not null default 1,
  change_seq  bigint      not null default nextval('app.global_change_seq'),
  unique (org_id, email)
);

comment on column public.profiles.org_id is
  'The tenancy anchor. Every authorisation decision derives the organisation from the caller profile row; a client-supplied org id is never accepted as proof of anything.';

-- The capability catalogue. Codes are stable strings and match domain/auth/capability.dart
-- exactly — renaming a Dart enum constant must never move one of these.
create table if not exists public.capabilities (
  code        text primary key,
  category    text not null,
  description text not null
);

create table if not exists public.roles (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid        not null references public.organizations(id) on delete restrict,
  code                text        not null,
  name                text        not null,
  is_system           boolean     not null default false,
  -- False for Owner alone. Everything else must name a business unit (D-025).
  requires_unit_scope boolean     not null default true,
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  row_version         integer     not null default 1,
  change_seq          bigint      not null default nextval('app.global_change_seq'),
  unique (org_id, code),
  unique (org_id, id)
);

create table if not exists public.role_capabilities (
  role_id         uuid not null references public.roles(id) on delete restrict,
  capability_code text not null references public.capabilities(code) on delete restrict,
  primary key (role_id, capability_code)
);

-- Organisation-wide settings that are configuration rather than code. `edit_window_days`
-- lives here precisely so the 7-day window in spec §13.3 is a value, not a constant.
create table if not exists public.org_settings (
  org_id     uuid        not null references public.organizations(id) on delete restrict,
  key        text        not null,
  value      jsonb       not null,
  updated_by uuid        references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (org_id, key)
);

drop trigger if exists touch_organizations on public.organizations;
create trigger touch_organizations before insert or update on public.organizations
  for each row execute function app.touch_row();

drop trigger if exists touch_profiles on public.profiles;
create trigger touch_profiles before insert or update on public.profiles
  for each row execute function app.touch_row();

drop trigger if exists touch_roles on public.roles;
create trigger touch_roles before insert or update on public.roles
  for each row execute function app.touch_row();

-- ── The catalogue itself ─────────────────────────────────────────────────────
-- 27 capabilities, matching lib/domain/auth/capability.dart one for one.
insert into public.capabilities (code, category, description) values
  ('expense.view.own',                  'expense',    'View expenses this user created'),
  ('expense.view.all',                  'expense',    'View all expenses in scope'),
  ('expense.create',                    'expense',    'Record an expense'),
  ('expense.edit.own',                  'expense',    'Edit expenses this user created'),
  ('expense.edit.all',                  'expense',    'Edit any expense in scope'),
  ('expense.void',                      'expense',    'Void an expense'),
  ('expense.allocate_periods',          'expense',    'Split an expense across accounting periods'),
  ('revenue.view',                      'revenue',    'View revenue entries in scope'),
  ('revenue.create',                    'revenue',    'Record revenue'),
  ('revenue.edit',                      'revenue',    'Edit a revenue entry'),
  ('revenue.void',                      'revenue',    'Void a revenue entry'),
  ('transaction.correct.beyond_window', 'correction', 'Edit a transaction after the edit window has closed'),
  ('transaction.correct.business_date', 'correction', 'Change a derived business date'),
  ('attachment.view',                   'attachment', 'View bills and receipts'),
  ('attachment.upload',                 'attachment', 'Attach a bill or receipt'),
  ('reports.view',                      'reporting',  'View reports'),
  ('reports.export',                    'reporting',  'Export reports to Excel or PDF'),
  ('reports.print',                     'reporting',  'Print reports'),
  ('masters.view',                      'masters',    'View master data'),
  ('masters.manage',                    'masters',    'Create, rename, archive and restore master data'),
  ('tax.manage',                        'masters',    'Configure date-effective tax rules'),
  ('users.manage',                      'admin',      'Administer users'),
  ('roles.manage',                      'admin',      'Administer roles and capability grants'),
  ('audit.view',                        'admin',      'View the audit trail'),
  ('settings.manage',                   'admin',      'Change organisation settings'),
  ('period.close',                      'period',     'Close an accounting period'),
  ('period.reopen',                     'period',     'Reopen a closed accounting period')
on conflict (code) do update
  set category = excluded.category, description = excluded.description;
