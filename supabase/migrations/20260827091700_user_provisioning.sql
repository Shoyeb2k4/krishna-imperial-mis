-- ─────────────────────────────────────────────────────────────────────────────
-- 0018 · Onboarding a user into the organisation
--
-- A gap found while preparing the authorisation tests, not test scaffolding: there was no
-- legitimate way for an Owner to bring an existing authentication account into the
-- organisation. `user_role_grant` requires a profile, and nothing created one except the
-- owner bootstrap. The only alternative would have been inserting profiles behind the
-- authorisation model, which is exactly what must not happen - so the mechanism is built
-- properly instead.
--
-- It deliberately does NOT create accounts or set passwords. Sign-up and credentials stay
-- entirely inside Supabase Auth; this only says "this existing account belongs to this
-- organisation, and here is its display name".
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.user_provision(
  p_email       text,
  p_full_name   text,
  p_mutation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor   uuid;
  v_org     uuid;
  v_user_id uuid;
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_replay  jsonb;
  v_result  jsonb;
  v_created boolean;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Bringing somebody into the organisation is an organisation-wide act, so it needs an
  -- organisation-wide grant. A manager scoped to one property cannot enrol people.
  perform app.require_unscoped_capability('users.manage');

  if length(v_email) = 0 then
    perform app.refuse('KM012', 'name_required', 'An email address is required.');
  end if;
  if length(btrim(coalesce(p_full_name, ''))) = 0 then
    perform app.refuse('KM012', 'name_required', 'A full name is required.');
  end if;

  select u.id into v_user_id from auth.users u where lower(u.email) = v_email;
  if v_user_id is null then
    perform app.refuse('KM015', 'unknown_entity',
      'No sign-in account exists for that address. The person must sign up, or be added '
      'in the Supabase dashboard, before they can be given a role.',
      jsonb_build_object('email', v_email));
  end if;

  if exists (select 1 from public.profiles p where p.id = v_user_id and p.org_id <> v_org) then
    perform app.refuse('KM002', 'out_of_unit_scope',
      'That account already belongs to another organisation.',
      jsonb_build_object('email', v_email));
  end if;

  v_created := not exists (select 1 from public.profiles p where p.id = v_user_id);

  insert into public.profiles (id, org_id, full_name, email)
  values (v_user_id, v_org, btrim(p_full_name), v_email)
  on conflict (id) do update set full_name = excluded.full_name, is_active = true;

  v_result := jsonb_build_object(
    'status', 'applied', 'entity_type', 'profile', 'entity_id', v_user_id,
    'email', v_email, 'created', v_created);

  perform app.write_audit(v_org, 'profile', v_user_id,
    case when v_created then 'user_provisioned' else 'user_updated' end,
    v_actor, null::jsonb, v_result, null, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'profile', v_user_id,
                               'provision', v_result);
end;
$$;

-- Deactivating a user without deleting anything they recorded.
create or replace function public.user_deactivate(
  p_user_id     uuid,
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
  v_replay jsonb;
  v_result jsonb;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();
  perform app.require_unscoped_capability('users.manage');

  if not exists (select 1 from public.profiles p where p.id = p_user_id and p.org_id = v_org) then
    perform app.refuse('KM015', 'unknown_entity', 'That user is not part of this organisation.',
      jsonb_build_object('user_id', p_user_id));
  end if;

  update public.profiles set is_active = false where id = p_user_id;

  v_result := jsonb_build_object('status', 'applied', 'entity_type', 'profile',
                                 'entity_id', p_user_id, 'is_active', false);
  perform app.write_audit(v_org, 'profile', p_user_id, 'user_deactivated', v_actor,
    jsonb_build_object('is_active', true), jsonb_build_object('is_active', false),
    null, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'profile', p_user_id,
                               'deactivate', v_result);
end;
$$;

revoke all on function public.user_provision(text, text, uuid) from public, anon;
revoke all on function public.user_deactivate(uuid, uuid) from public, anon;
grant execute on function public.user_provision(text, text, uuid) to authenticated;
grant execute on function public.user_deactivate(uuid, uuid) to authenticated;

-- Keep the privilege invariant true after adding to the API surface.
do $$
declare v_leak text;
begin
  select string_agg(p.oid::regprocedure::text, ', ')
    into v_leak
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_leak is not null then
    raise exception 'anon can execute: %', v_leak;
  end if;
end $$;
