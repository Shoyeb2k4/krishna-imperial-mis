-- ─────────────────────────────────────────────────────────────────────────────
-- 0022 · The caller's own authority, in one round trip
--
-- The client needs three things to shape itself honestly: which organisation it is in,
-- which capabilities it holds, and over which properties. All three are already derivable
-- from `user_roles` and `role_capabilities` through RLS, but only by traversing two joins
-- from the client — several round trips, and a shape that changes if the tables do.
--
-- More importantly, D-048 hangs on this answer. A purge follows a *positive* statement of
-- current scope, so that statement should be one atomic server response, not something
-- the client assembles from fragments any one of which might have failed.
--
-- `resolved_at` is server time. The device clock is never authoritative (D-019), and this
-- value is shown as the freshness of the permission state.
--
-- RECOVERED. This migration was applied to the development project on 2026-08-28 and was
-- never committed. `my_authority()` is the single most consequential call the client
-- makes, and for a day it existed only on one server — a staging or production
-- environment could not have been built from this repository. Captured here verbatim from
-- `supabase_migrations.schema_migrations`, and the live suite now asserts that every
-- applied migration has a file, so the same gap cannot reopen silently.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.my_authority()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_org   uuid;
begin
  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  return jsonb_build_object(
    'user_id',     v_actor,
    'org_id',      v_org,
    'resolved_at', now(),
    'grants',      coalesce((
      select jsonb_agg(distinct jsonb_build_object(
               'capability',       rc.capability_code,
               'business_unit_id', ur.business_unit_id))
        from public.user_roles ur
        join public.role_capabilities rc on rc.role_id = ur.role_id
       where ur.user_id = v_actor
         and ur.revoked_at is null
    ), '[]'::jsonb));
end;
$$;

comment on function public.my_authority() is
  'The caller own organisation, capabilities and business-unit scopes, as one atomic '
  'answer. Derives everything from auth.uid(); accepts nothing from the request.';

revoke all on function public.my_authority() from public, anon;
grant execute on function public.my_authority() to authenticated;
