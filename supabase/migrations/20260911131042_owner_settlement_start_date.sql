-- Server migration ledger name: owner_settlement_start_date
--
-- Phase 5 OA-3 · the one authoritative date from which 50:50 ownership and owner
-- settlement begin.
--
-- The header names no ledger version (D-203); `LEDGER.md` maps it.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What the project lead decided (OA-3 Q1, 2026-09-11)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- There is **no separate settlement inception date** in V1. One server setting represents:
--
--     "50:50 ownership and owner settlement begin from this date."
--
-- The settlement calculator requires that date and has always refused to guess it
-- (OA-2, `OwnerSettlementRefusal.beforeInception`). Until now it had nowhere to come from,
-- so no real device could ever produce a settlement.
--
-- **The production date is still outstanding, and nothing here supplies one.** No row is
-- seeded, no default is written, and the column has no default: a missing row is the
-- honest state "Settlement start date not configured", and the settlement refuses on it.
-- Guessing it — the financial-year start, the tax configuration's 2026-04-01, the earliest
-- ownership share — would be inventing a business fact (`CLAUDE.md`, D-043).
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Where it lives, and who may change it
-- ═════════════════════════════════════════════════════════════════════════════
--
-- One row per organisation, written by one reviewed SECURITY DEFINER RPC,
-- `owner_settlement_start_set`, gated by the existing `owner_masters.manage` — the
-- owner-account master/configuration capability — rather than by the Owner role name.
-- Required unscoped, which is the same gate `owner_share_set` uses for the ratio this date
-- governs, and satisfiable: the Owner bundle holds it unscoped and no other bundle holds it.
--
-- Every change is audited with before and after values. Concurrency is explicit: an update
-- states the row version it was based on and a stale one is a conflict, never an
-- overwrite (D-021).
--
-- The date must be the **first of a month**. Settlement periods are calendar months and an
-- ownership change takes effect at the start of one (D-189) — the same rule
-- `owner_share_set` already enforces with the same sentence shape. A mid-month start would
-- make its own first month permanently unsettleable, because that month begins before the
-- start.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Who may read it
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Holders of `owner_settlement.view` (the surface that consumes it) and holders of
-- `owner_masters.manage` (the person who sets it). Anywhere, not unscoped: the date is not
-- sliced by property, and D-200 records what an unsatisfiable unscoped read gate costs.

create table if not exists public.owner_settlement_settings (
  org_id               uuid primary key references public.organizations(id) on delete restrict,
  ownership_start_date date not null,
  created_by           uuid not null,
  created_at           timestamptz not null default now(),
  updated_by           uuid,
  updated_at           timestamptz not null default now(),
  row_version          integer not null default 1,
  change_seq           bigint not null default nextval('app.global_change_seq'),

  -- The mid-period rule, as a backstop. The RPC refuses first, with a sentence.
  constraint owner_settlement_start_first_of_month
    check (extract(day from ownership_start_date) = 1)
);

comment on table public.owner_settlement_settings is
  'The date from which 50:50 ownership and owner settlement begin (OA-3 Q1). One row per organisation; absent means not configured, and the settlement refuses. Ships empty: the production date is outstanding and is never guessed.';

-- change_seq advances on every update (D-177), by the narrow stamp rather than touch_row,
-- which would also increment row_version and double-count the concurrency token the RPC
-- already maintains.
drop trigger if exists trg_owner_settlement_settings_change_seq
  on public.owner_settlement_settings;
create trigger trg_owner_settlement_settings_change_seq
  before update on public.owner_settlement_settings
  for each row execute function app.stamp_change_seq();

alter table public.owner_settlement_settings enable row level security;

-- All four privileges, not three: TRUNCATE survives a three-word revoke and consults no
-- RLS at all (D-162). Every write goes through the RPC below.
revoke all on public.owner_settlement_settings from anon, authenticated;
grant select on public.owner_settlement_settings to authenticated;

create policy owner_settlement_settings_read on public.owner_settlement_settings
  for select to authenticated
  using (org_id = public.current_org_id()
         and (public.has_capability_anywhere('owner_settlement.view')
              or public.has_capability_anywhere('owner_masters.manage')));

-- ═════════════════════════════════════════════════════════════════════════════
-- The one writer
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.owner_settlement_start_set(
  p_ownership_start_date date,
  p_base_row_version     integer default null,
  p_mutation_id          uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_actor uuid; v_org uuid; v_replay jsonb;
        v_existing public.owner_settlement_settings%rowtype; v_found boolean;
        v_version integer; v_status text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Permission before anything about the row is revealed (D-046).
  perform app.require_unscoped_capability('owner_masters.manage');

  if p_ownership_start_date is null then
    perform app.refuse('KM031', 'ownership_start_required',
      'Choose the date from which 50:50 ownership and owner settlement begin.',
      '{}'::jsonb);
  end if;

  if extract(day from p_ownership_start_date) <> 1 then
    perform app.refuse('KM031', 'ownership_start_mid_period',
      'Ownership and settlement begin at the start of a month. Choose the first day of the month they should begin.',
      jsonb_build_object('proposed', p_ownership_start_date,
                         'next_valid', (date_trunc('month', p_ownership_start_date)
                                        + interval '1 month')::date));
  end if;

  select * into v_existing
    from public.owner_settlement_settings
   where org_id = v_org
   for update;
  v_found := found;

  if v_found then
    -- A change to a configured date must be based on the version the person was looking
    -- at. A stale intent is a conflict, never an overwrite of somebody else's change.
    if p_base_row_version is null or p_base_row_version <> v_existing.row_version then
      perform app.refuse('KM003', 'version_conflict',
        'The settlement start date was changed by somebody else. Review the current date before changing it.',
        jsonb_build_object('current_row_version', v_existing.row_version,
                           'current_ownership_start_date', v_existing.ownership_start_date));
    end if;

    update public.owner_settlement_settings
       set ownership_start_date = p_ownership_start_date,
           updated_by = v_actor, updated_at = now(),
           row_version = row_version + 1
     where org_id = v_org
     returning row_version into v_version;
    v_status := 'updated';
  else
    -- Nothing is configured, so an intent that claims to be based on a version was based
    -- on a state that does not exist.
    if p_base_row_version is not null then
      perform app.refuse('KM003', 'version_conflict',
        'The settlement start date is not configured any more. Review it before setting it.',
        jsonb_build_object('current_row_version', null));
    end if;

    insert into public.owner_settlement_settings (org_id, ownership_start_date, created_by)
    values (v_org, p_ownership_start_date, v_actor)
    returning row_version into v_version;
    v_status := 'created';
  end if;

  perform app.write_audit(v_org, 'owner_settlement_settings', v_org,
    'ownership_start_set', v_actor,
    case when v_found
         then jsonb_build_object('ownership_start_date', v_existing.ownership_start_date,
                                 'row_version', v_existing.row_version)
    end,
    jsonb_build_object('ownership_start_date', p_ownership_start_date,
                       'row_version', v_version),
    null, null, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'owner_settlement_settings', v_org,
    case when v_found then 'update' else 'create' end,
    jsonb_build_object('status', v_status,
                       'ownership_start_date', p_ownership_start_date,
                       'row_version', v_version));
end; $fn$;

revoke all on function public.owner_settlement_start_set(date, integer, uuid)
  from public, anon;
grant execute on function public.owner_settlement_start_set(date, integer, uuid)
  to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- Assertions
-- ═════════════════════════════════════════════════════════════════════════════

do $$
declare v_src text; v_secdef boolean; v_cfg text[];
begin
  select p.prosrc, p.prosecdef, p.proconfig into v_src, v_secdef, v_cfg
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_settlement_start_set';

  if not v_secdef then
    raise exception 'owner_settlement_start_set must be security definer: clients hold no write privilege';
  end if;
  if not exists (select 1 from unnest(coalesce(v_cfg, array[]::text[])) c
                  where c like 'search_path=%') then
    raise exception 'owner_settlement_start_set does not pin its search_path';
  end if;

  -- Gated by the configuration capability, never by a role name.
  if v_src not like '%owner_masters.manage%' then
    raise exception 'owner_settlement_start_set is not gated on owner_masters.manage';
  end if;
  if v_src ~ '\mowner\M\s*=' or v_src ~ 'roles?\.code' then
    raise exception 'owner_settlement_start_set branches on a role name';
  end if;

  -- Every change is audited, and concurrency is explicit.
  if v_src not like '%app.write_audit%' then
    raise exception 'owner_settlement_start_set writes no audit record';
  end if;
  if v_src not like '%p_base_row_version%' or v_src not like '%version_conflict%' then
    raise exception 'owner_settlement_start_set does not enforce the base row version (D-021)';
  end if;
  if v_src not like '%ownership_start_mid_period%' then
    raise exception 'owner_settlement_start_set does not refuse a mid-month start';
  end if;
end $$;

-- Nothing is seeded. The production date is outstanding, and a row written here would be a
-- date nobody chose.
do $$
begin
  if exists (select 1 from public.owner_settlement_settings) then
    raise exception
      'owner_settlement_settings holds a row after its own migration. The settlement start '
      'date is a business fact the project lead has not supplied, and is never seeded';
  end if;
end $$;

-- No client write privilege of any kind, and the read gate is satisfiable and unsliced.
do $$
declare v_priv text;
begin
  select string_agg(distinct a.privilege_type || ' to ' || a.grantee, ', ') into v_priv
    from information_schema.role_table_grants a
   where a.table_schema = 'public' and a.table_name = 'owner_settlement_settings'
     and a.grantee in ('anon', 'authenticated')
     and a.privilege_type <> 'SELECT';
  if v_priv is not null then
    raise exception 'a client role holds a write privilege on owner_settlement_settings: %', v_priv;
  end if;

  if has_table_privilege('anon', 'public.owner_settlement_settings', 'select') then
    raise exception 'anon can read owner_settlement_settings';
  end if;

  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'owner_settlement_settings'
                and coalesce(qual, '') like '%has_unscoped_capability%') then
    raise exception
      'the settlement start date read gate requires an unscoped capability, which only the '
      'Owner can hold (D-200)';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'owner_settlement_settings'
                and coalesce(qual, '') like '%business_unit_id%') then
    raise exception 'the settlement start date read gate filters by business unit';
  end if;

  if not exists (
    select 1 from pg_trigger tg
      join pg_class c on c.oid = tg.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_proc p on p.oid = tg.tgfoid
     where n.nspname = 'public' and c.relname = 'owner_settlement_settings'
       and p.proname = 'stamp_change_seq' and not tg.tgisinternal) then
    raise exception 'owner_settlement_settings carries change_seq and does not advance it (D-177)';
  end if;
end $$;
