-- Reactivating a user the Owner previously deactivated.
--
-- `user_deactivate` shipped without a counterpart, which made deactivation a one-way
-- door through the API: an Owner who suspended somebody — a manager on leave, a mistaken
-- click — had no supported way to give the account back, and the only route left was
-- direct table access, which no client holds and which writes no audit row.
--
-- Found while running the Phase 2 session-lifecycle acceptance, where the scenario
-- explicitly requires the test identity to be restored afterwards.
--
-- Deliberately symmetric with `user_deactivate`: same unscoped `users.manage` guard, same
-- idempotency key, same audit shape. Reactivating restores nothing else — the user's role
-- grants are separate records and any that were revoked stay revoked.

create or replace function public.user_reactivate(
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

  if not exists (
    select 1 from public.profiles p where p.id = p_user_id and p.org_id = v_org
  ) then
    perform app.refuse('KM015', 'unknown_entity',
      'That user is not part of this organisation.',
      jsonb_build_object('user_id', p_user_id));
  end if;

  update public.profiles set is_active = true where id = p_user_id;

  v_result := jsonb_build_object('status', 'applied', 'entity_type', 'profile',
                                 'entity_id', p_user_id, 'is_active', true);
  perform app.write_audit(v_org, 'profile', p_user_id, 'user_reactivated', v_actor,
    jsonb_build_object('is_active', false), jsonb_build_object('is_active', true),
    null, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'profile', p_user_id,
                               'reactivate', v_result);
end;
$$;

revoke all on function public.user_reactivate(uuid, uuid) from public, anon;
grant execute on function public.user_reactivate(uuid, uuid) to authenticated;

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
