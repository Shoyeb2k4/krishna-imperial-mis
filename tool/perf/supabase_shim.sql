-- Phase 8 Slice 2 — the minimal Supabase shim for the local D-186 harness (D-313).
--
-- The repository's migrations assume a Supabase project. This recreates only what they
-- reference, so that `supabase/migrations/*.sql` applies unmodified, in order, to a plain
-- PostgreSQL 17 cluster. Every deviation from Supabase is listed here, because a local
-- timing is only as honest as the list of things that differ from the real server:
--
--   * roles        anon, authenticated, service_role, authenticator — NOLOGIN, no
--                  BYPASSRLS except service_role, as on Supabase. `postgres` here is the
--                  bootstrap superuser; on Supabase it is not a superuser but it does hold
--                  BYPASSRLS, and it owns every table, view and function. RLS therefore
--                  applies identically to `authenticated` on both, and is bypassed
--                  identically by the object owner inside SECURITY DEFINER bodies.
--   * auth.uid()   byte-for-byte the definition read from krishna-mis-dev on 2026-09-29.
--   * auth.users   only the columns the migrations read (id, email).
--   * storage      buckets and objects with only the columns the migrations name; no
--                  Storage API, no storage.foldername. Nothing measured touches storage.
--   * extensions   btree_gist, pgcrypto and uuid-ossp installed in `extensions`, as the
--                  migrations request. pg_stat_statements, supautils and safeupdate are not
--                  installed; nothing measured depends on them.
--   * PostgREST    not present. The probe emulates it the way PostgREST does: SET LOCAL
--                  ROLE authenticated plus request.jwt.claims (d186_probe.sql).
--   * version      PostgreSQL 17.11 locally against 17.6 on Supabase; settings mirrored in
--                  localpg.sh.
-- Roles are cluster-wide, so a second `schema` run on the same cluster finds them.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
    create role authenticator nologin noinherit;
    grant anon, authenticated, service_role to authenticator;
  end if;
end $$;

create schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (
  id    uuid primary key,
  email text
);
create function auth.uid() returns uuid language sql stable as $$
  select
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create schema storage;
grant usage on schema storage to anon, authenticated, service_role;
create table storage.buckets (
  id                 text primary key,
  name               text not null,
  public             boolean default false,
  file_size_limit    bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id        uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name      text,
  owner_id  text,
  metadata  jsonb
);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to authenticated;

create schema supabase_migrations;
