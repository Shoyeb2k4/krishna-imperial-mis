-- ─────────────────────────────────────────────────────────────────────────────
-- 0005 · Role grants, always carrying an explicit business-unit scope
--
-- D-025, and the owner's words in spec §13.2: "A Manager does not automatically gain
-- access to both properties." A grant is a triple — user × role × business unit — and the
-- only role permitted to hold an unscoped, all-units grant is Owner.
--
-- That is enforced by a trigger, not by convention, so the safe default is structural
-- rather than remembered. A manager covering both properties therefore holds two
-- explicit, separately revocable grants, which is visible in the table and revocable one
-- property at a time.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.user_roles (
  id               uuid primary key default extensions.gen_random_uuid(),
  org_id           uuid        not null references public.organizations(id) on delete restrict,
  user_id          uuid        not null references public.profiles(id) on delete restrict,
  role_id          uuid        not null,
  -- Null means every unit. Permitted for Owner alone; the trigger below sees to it.
  business_unit_id uuid,
  granted_by       uuid        not null references public.profiles(id) on delete restrict,
  granted_at       timestamptz not null default now(),
  revoked_by       uuid        references public.profiles(id) on delete restrict,
  revoked_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  row_version      integer     not null default 1,
  change_seq       bigint      not null default nextval('app.global_change_seq'),
  constraint user_roles_role_fk
    foreign key (org_id, role_id) references public.roles (org_id, id) on delete restrict,
  -- The scoped unit must belong to the same organisation as the grant. Tenancy cannot be
  -- crossed by naming a unit from somewhere else.
  constraint user_roles_unit_fk
    foreign key (org_id, business_unit_id)
    references public.business_units (org_id, id) on delete restrict,
  constraint user_roles_revocation_complete
    check ((revoked_at is null) = (revoked_by is null))
);

-- One grant per (user, role, unit). The coalesce is deliberate: without it Postgres
-- treats two NULL unit ids as distinct and would allow the same all-units grant twice.
create unique index if not exists user_roles_unique_grant
  on public.user_roles (
    user_id, role_id,
    coalesce(business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists user_roles_active_idx
  on public.user_roles (user_id, business_unit_id) where revoked_at is null;

create index if not exists user_roles_change_seq_idx on public.user_roles (org_id, change_seq);

drop trigger if exists touch_user_roles on public.user_roles;
create trigger touch_user_roles before insert or update on public.user_roles
  for each row execute function app.touch_row();

-- ── The scoping rule (D-025) ─────────────────────────────────────────────────
create or replace function app.enforce_role_scope()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_requires_scope boolean;
  v_role_code      text;
begin
  select r.requires_unit_scope, r.code
    into v_requires_scope, v_role_code
    from public.roles r
   where r.id = new.role_id;

  if v_requires_scope is null then
    perform app.refuse('KM015', 'unknown_entity', 'That role does not exist.',
                       jsonb_build_object('role_id', new.role_id));
  end if;

  if v_requires_scope and new.business_unit_id is null then
    perform app.refuse(
      'KM002', 'unit_scope_required',
      format('The %s role must be granted for a named business unit. Grant it once per '
             'property so it can be revoked one property at a time.', v_role_code),
      jsonb_build_object('role_id', new.role_id, 'role_code', v_role_code));
  end if;

  if not v_requires_scope and new.business_unit_id is not null then
    -- An unscoped role granted "for one unit" would read as a restriction it does not
    -- actually impose. Refuse rather than quietly widen it.
    perform app.refuse(
      'KM002', 'unit_scope_not_applicable',
      format('The %s role covers every business unit and cannot be granted for one.',
             v_role_code),
      jsonb_build_object('role_id', new.role_id, 'role_code', v_role_code));
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_role_scope_user_roles on public.user_roles;
create trigger enforce_role_scope_user_roles
  before insert or update on public.user_roles
  for each row execute function app.enforce_role_scope();
