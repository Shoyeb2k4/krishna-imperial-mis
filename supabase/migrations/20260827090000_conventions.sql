-- ─────────────────────────────────────────────────────────────────────────────
-- 0001 · Conventions, extensions and the shared write machinery
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.1 · Phase 2
--
-- Everything the rest of the schema leans on: the private `app` schema for internal
-- helpers, the one global change sequence that drives incremental sync, and the trigger
-- that stamps `updated_at` / `row_version` / `change_seq` on every synced table.
--
-- Nothing in this file is reachable from a client. `app` is never exposed through
-- PostgREST, and EXECUTE is revoked from `anon` and `authenticated` throughout.
-- ─────────────────────────────────────────────────────────────────────────────

create extension if not exists "pgcrypto"  with schema extensions;   -- gen_random_uuid
create extension if not exists "btree_gist" with schema extensions;  -- tax exclusion constraint

create schema if not exists app;
revoke all on schema app from public;
grant usage on schema app to postgres, service_role;

comment on schema app is
  'Internal helpers. Never exposed through PostgREST; clients reach the database only '
  'through RLS-protected SELECTs on public tables and through SECURITY DEFINER RPCs.';

-- ── Incremental sync cursor ──────────────────────────────────────────────────
-- One sequence shared by every synced table, so a client can pull "everything changed
-- since N" in one ordered pass (docs/ARCHITECTURE.md §5.2).
create sequence if not exists app.global_change_seq as bigint;

-- ── The shared write trigger ─────────────────────────────────────────────────
-- Server timestamps are authoritative; the device clock is forensic metadata only
-- (D-019). `row_version` is the optimistic-concurrency token every mutation must
-- declare (D-021) — it is incremented *here* so no RPC can forget to.
create or replace function app.touch_row()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at  := now();
  new.change_seq  := nextval('app.global_change_seq');
  if tg_op = 'UPDATE' then
    -- A caller cannot set its own version: the database owns it.
    new.row_version := old.row_version + 1;
    new.created_at  := old.created_at;
  else
    new.row_version := coalesce(new.row_version, 1);
    new.created_at  := coalesce(new.created_at, now());
  end if;
  return new;
end;
$$;

comment on function app.touch_row() is
  'Stamps server-authoritative updated_at, row_version and change_seq. Attached to every '
  'synced table so optimistic concurrency cannot be bypassed by a forgetful RPC.';

-- ── Append-only guard ────────────────────────────────────────────────────────
-- Audit trails, period-lock events and the mutation ledger are written once and never
-- amended. Enforced by a trigger, not by the absence of a grant, so it holds even for a
-- SECURITY DEFINER function that gets it wrong (master spec §14).
create or replace function app.refuse_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'KM016',
    message = format('%s is append-only; %s is not permitted', tg_table_name, tg_op),
    detail  = '{"code":"append_only"}';
end;
$$;

-- ── Error vocabulary ─────────────────────────────────────────────────────────
-- Every refusal carries a distinct SQLSTATE and a machine-readable DETAIL payload, so
-- the UI can tell the user the *real* reason. A closed period must never surface as a
-- permissions problem, and a stale version must never surface as a closed period.
--
--   KM001 missing_capability      KM009 immutable_code
--   KM002 out_of_unit_scope       KM010 hierarchy_violation
--   KM003 version_conflict        KM011 not_authenticated
--   KM004 period_closed           KM012 duplicate_name
--   KM005 has_active_children     KM013 already_archived
--   KM006 archived_master         KM014 not_archived
--   KM007 tax_period_overlap      KM015 unknown_entity
--   KM008 reason_required         KM016 append_only
--                                 KM017 acknowledgement_required
create or replace function app.refuse(
  p_errcode text,
  p_code    text,
  p_message text,
  p_detail  jsonb default '{}'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = p_errcode,
    message = p_message,
    detail  = (p_detail || jsonb_build_object('code', p_code))::text;
end;
$$;
