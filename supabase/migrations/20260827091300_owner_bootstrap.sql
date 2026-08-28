-- ─────────────────────────────────────────────────────────────────────────────
-- 0014 · Development owner bootstrap
--
-- The first Owner has to come from somewhere, and every convenient way of arranging that
-- is a privilege-escalation route left switched on:
--
--   · a public RPC that grants ownership "if nobody owns anything yet" — whoever signs up
--     first wins, and the window stays open until someone uses it;
--   · a trigger that promotes the first `auth.users` row — same race, with no audit;
--   · a seeded owner account — a credential in source control, which is forbidden outright.
--
-- So there is **no client-callable owner-creation path at all**. `EXECUTE` on this
-- function is revoked from `public`, `anon` and `authenticated`. It can only be run by a
-- privileged database role — in practice, the owner pasting one line into the Supabase
-- dashboard SQL editor, authenticated by their dashboard session. A modified APK, a
-- rebuilt .exe and a stolen anon key are all equally powerless against it, because the
-- grant they would need does not exist.
--
-- It is also idempotent, so running it twice is safe, and it refuses to quietly mint a
-- second owner unless that is asked for explicitly.
--
-- Exact steps are in supabase/README.md.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function app.bootstrap_owner(
  p_email            text,
  p_full_name        text    default null,
  p_allow_additional boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id    uuid;
  v_org        uuid := app.seed_id('org:KRISHNA');
  v_role       uuid := app.seed_id('role:owner');
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_existing   uuid;
  v_grant      uuid;
  v_created    boolean := false;
begin
  if length(v_email) = 0 then
    raise exception 'bootstrap_owner requires the email address of an existing auth user';
  end if;

  select u.id into v_user_id from auth.users u where lower(u.email) = v_email;
  if v_user_id is null then
    raise exception
      'No authentication user exists for %. Create the user first in the Supabase '
      'dashboard under Authentication -> Users -> Add user, then run this again. '
      'This function deliberately cannot create accounts or set passwords.', v_email;
  end if;

  if not exists (select 1 from public.organizations where id = v_org) then
    raise exception
      'The organisation has not been seeded yet. Apply all migrations before bootstrapping '
      'the owner.';
  end if;

  -- Refuse to mint a second owner by accident. Adding one deliberately is possible, and
  -- says so at the call site.
  select ur.user_id into v_existing
    from public.user_roles ur
   where ur.role_id = v_role and ur.revoked_at is null and ur.user_id <> v_user_id
   limit 1;

  if v_existing is not null and not p_allow_additional then
    raise exception
      'This organisation already has an owner. Re-run with p_allow_additional => true if '
      'a second owner is genuinely intended; ownership is not granted by accident.';
  end if;

  insert into public.profiles (id, org_id, full_name, email)
  values (v_user_id, v_org, coalesce(nullif(btrim(coalesce(p_full_name, '')), ''), v_email),
          v_email)
  on conflict (id) do update set is_active = true
  returning true into v_created;

  -- The Owner grant is unscoped by definition: Owner is the only role permitted to hold
  -- an all-units grant, and the scoping trigger refuses to attach a unit to it (D-025).
  insert into public.user_roles (org_id, user_id, role_id, business_unit_id, granted_by)
  values (v_org, v_user_id, v_role, null, v_user_id)
  on conflict (user_id, role_id,
               coalesce(business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set revoked_at = null, revoked_by = null
  returning id into v_grant;

  perform app.write_audit(
    v_org, 'user_role', v_grant, 'owner_bootstrapped', v_user_id,
    null::jsonb,
    jsonb_build_object('user_id', v_user_id, 'email', v_email, 'role', 'owner'),
    'development owner bootstrap, run from a privileged database session',
    null::uuid, null::uuid);

  return jsonb_build_object(
    'status',  'ok',
    'user_id', v_user_id,
    'org_id',  v_org,
    'email',   v_email,
    'grant_id', v_grant,
    'profile_created', v_created);
end;
$$;

-- The whole point. There is no client-reachable grant on this function, and never will be.
revoke all on function app.bootstrap_owner(text, text, boolean) from public;
revoke all on function app.bootstrap_owner(text, text, boolean) from anon, authenticated;

comment on function app.bootstrap_owner(text, text, boolean) is
  'One-time development owner bootstrap. Executable only by a privileged database role '
  '(the dashboard SQL editor). Never callable by anon or authenticated, so it cannot '
  'remain an open privilege-escalation route. It never creates accounts or sets passwords.';

-- ── Granting the other roles ─────────────────────────────────────────────────
-- Once an Owner exists, further grants are ordinary administration and go through this,
-- which is capability-gated like everything else. Every non-Owner grant must name a
-- business unit; the trigger in 0005 refuses otherwise (D-025).
create or replace function public.user_role_grant(
  p_user_id          uuid,
  p_role_code        text,
  p_business_unit_id uuid default null,
  p_mutation_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  v_role   uuid;
  v_grant  uuid;
  v_replay jsonb;
  v_result jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Handing out authority over one property needs authority over that property; handing
  -- out an unscoped grant needs an unscoped one.
  if p_business_unit_id is null then
    perform app.require_unscoped_capability('users.manage');
  else
    perform app.require_capability('users.manage', p_business_unit_id);
  end if;

  select r.id into v_role from public.roles r
   where r.org_id = v_org and r.code = p_role_code and r.archived_at is null;
  if v_role is null then
    perform app.refuse('KM015', 'unknown_entity', 'That role does not exist.',
      jsonb_build_object('role_code', p_role_code));
  end if;

  if not exists (select 1 from public.profiles p where p.id = p_user_id and p.org_id = v_org) then
    perform app.refuse('KM015', 'unknown_entity', 'That user is not part of this organisation.',
      jsonb_build_object('user_id', p_user_id));
  end if;

  insert into public.user_roles (org_id, user_id, role_id, business_unit_id, granted_by)
  values (v_org, p_user_id, v_role, p_business_unit_id, v_actor)
  on conflict (user_id, role_id,
               coalesce(business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set revoked_at = null, revoked_by = null, granted_by = v_actor, granted_at = now()
  returning id into v_grant;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'user_role', 'entity_id', v_grant,
    'user_id', p_user_id, 'role_code', p_role_code,
    'business_unit_id', p_business_unit_id);

  perform app.write_audit(v_org, 'user_role', v_grant, 'role_granted', v_actor,
    null::jsonb, v_result, null, p_business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'user_role', v_grant,
                               'grant', v_result);
end;
$$;

-- Revoking is immediate and total: `has_capability` reads live rows, so the next request
-- from that user is already refused. A mutation queued on their device while they still
-- had authority is refused when it finally arrives — the server's current authorisation
-- always wins (owner requirement §17).
create or replace function public.user_role_revoke(
  p_grant_id    uuid,
  p_mutation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_org    uuid;
  g        record;
  v_replay jsonb;
  v_result jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  select * into g from public.user_roles where id = p_grant_id and org_id = v_org;
  if g.id is null then
    perform app.refuse('KM015', 'unknown_entity', 'That grant does not exist.',
      jsonb_build_object('grant_id', p_grant_id));
  end if;

  if g.business_unit_id is null then
    perform app.require_unscoped_capability('users.manage');
  else
    perform app.require_capability('users.manage', g.business_unit_id);
  end if;

  update public.user_roles
     set revoked_at = now(), revoked_by = v_actor
   where id = p_grant_id and revoked_at is null;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'user_role', 'entity_id', p_grant_id,
    'revoked', true);

  perform app.write_audit(v_org, 'user_role', p_grant_id, 'role_revoked', v_actor,
    jsonb_build_object('revoked_at', null), jsonb_build_object('revoked_at', now()),
    null, g.business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'user_role', p_grant_id,
                               'revoke', v_result);
end;
$$;

grant execute on function public.user_role_grant(uuid, text, uuid, uuid) to authenticated;
grant execute on function public.user_role_revoke(uuid, uuid) to authenticated;
