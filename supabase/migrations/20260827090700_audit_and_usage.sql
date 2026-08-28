-- ─────────────────────────────────────────────────────────────────────────────
-- 0008 · Audit trail, the idempotency ledger, and authoritative usage counters
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Audit trail (master spec §14) ────────────────────────────────────────────
-- Every important mutation, with before and after state, actor and a **server**
-- timestamp. Append-only: no client holds any grant on this table, and the trigger
-- refuses UPDATE and DELETE even from a SECURITY DEFINER function that gets it wrong.
create table if not exists public.audit_logs (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid        not null references public.organizations(id) on delete restrict,
  entity_type         text        not null,
  entity_id           uuid        not null,
  action              text        not null,
  business_unit_id    uuid,
  before_state        jsonb,
  after_state         jsonb,
  changed_fields      text[],
  reason              text,
  actor_id            uuid        not null references public.profiles(id) on delete restrict,
  actor_name_snapshot text,
  occurred_at         timestamptz not null default now(),
  client_platform     text,
  client_version      text,
  mutation_id         uuid
);

create index if not exists audit_logs_entity_idx
  on public.audit_logs (org_id, entity_type, entity_id, occurred_at desc);
create index if not exists audit_logs_unit_idx
  on public.audit_logs (org_id, business_unit_id, occurred_at desc);

drop trigger if exists append_only_audit_logs on public.audit_logs;
create trigger append_only_audit_logs
  before update or delete on public.audit_logs
  for each row execute function app.refuse_mutation();

-- One writer, so no RPC invents its own audit shape.
create or replace function app.write_audit(
  p_org_id           uuid,
  p_entity_type      text,
  p_entity_id        uuid,
  p_action           text,
  p_actor_id         uuid,
  p_before           jsonb default null,
  p_after            jsonb default null,
  p_reason           text  default null,
  p_business_unit_id uuid  default null,
  p_mutation_id      uuid  default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id     uuid;
  v_fields text[];
begin
  -- Which fields actually moved. Computed here rather than trusted from the caller, so
  -- the audit row cannot understate a change.
  if p_before is not null and p_after is not null then
    select array_agg(key order by key) into v_fields
      from (
        select key from jsonb_each(p_after)
        except
        select key from jsonb_each(p_before)
        union
        select a.key
          from jsonb_each(p_after) a
          join jsonb_each(p_before) b on b.key = a.key
         where a.value is distinct from b.value
      ) changed;
  end if;

  insert into public.audit_logs (
    org_id, entity_type, entity_id, action, business_unit_id,
    before_state, after_state, changed_fields, reason,
    actor_id, actor_name_snapshot, mutation_id
  )
  values (
    p_org_id, p_entity_type, p_entity_id, p_action, p_business_unit_id,
    p_before, p_after, v_fields, p_reason,
    p_actor_id, (select full_name from public.profiles where id = p_actor_id), p_mutation_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ── The idempotency ledger (D-004, D-021) ────────────────────────────────────
-- Answers "have I already applied *this exact intent*?". Separate from row_version,
-- which answers "is this intent still based on current state?". Conflating the two is
-- how a retry becomes a duplicate financial record, or a stale void destroys an edit.
create table if not exists public.processed_mutations (
  mutation_id  uuid primary key,
  org_id       uuid        not null references public.organizations(id) on delete restrict,
  actor_id     uuid        not null references public.profiles(id) on delete restrict,
  entity_type  text        not null,
  entity_id    uuid        not null,
  op           text        not null,
  result       jsonb       not null,
  processed_at timestamptz not null default now()
);

create index if not exists processed_mutations_age_idx on public.processed_mutations (processed_at);

-- UPDATE is refused; DELETE is left available so the 90-day retention purge can run as a
-- privileged scheduled job. A stored result that could be edited would make replay a lie.
create or replace function app.refuse_update_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'KM016',
    message = format('%s rows are written once and never amended', tg_table_name),
    detail  = '{"code":"append_only"}';
end;
$$;

drop trigger if exists append_only_processed_mutations on public.processed_mutations;
create trigger append_only_processed_mutations
  before update on public.processed_mutations
  for each row execute function app.refuse_update_only();

-- ── Authoritative usage counters (owner requirement §11) ─────────────────────
-- The naive implementation of "how many transactions reference this master?" is
-- `count(*)` over the allocation lines. That is fine today and pathological in five
-- years: it is a full scan of financial history, run every time an administrator opens a
-- rename dialog, on a screen that must feel instant.
--
-- So the count is **maintained, not computed**. One row per master, incremented by the
-- Phase 3 financial write path through `app.record_master_usage`, read in O(1) by primary
-- key. `master_usage()` in 0012 serves it as the authoritative figure the client's
-- `UsageSource.server` represents.
--
-- Consequence worth stating plainly: while no financial tables exist, a count of zero is
-- **genuinely authoritative** — there are no transactions in the organisation at all, so
-- nothing is being approximated. That is different in kind from a local cache reporting
-- zero because it has not synced, which the client must never promote (D-041).
create table if not exists public.master_usage_counters (
  entity_type            text        not null,
  entity_id              uuid        not null,
  org_id                 uuid        not null references public.organizations(id) on delete restrict,
  transaction_count      bigint      not null default 0 check (transaction_count >= 0),
  earliest_business_date date,
  latest_business_date   date,
  updated_at             timestamptz not null default now(),
  primary key (entity_type, entity_id)
);

create index if not exists master_usage_counters_org_idx on public.master_usage_counters (org_id);

-- The single mutation point for a counter. Phase 3 attaches triggers on the financial
-- tables that call this; nothing else writes here.
create or replace function app.record_master_usage(
  p_org_id        uuid,
  p_entity_type   text,
  p_entity_id     uuid,
  p_business_date date,
  p_delta         integer default 1
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.master_usage_counters as c (
    entity_type, entity_id, org_id, transaction_count,
    earliest_business_date, latest_business_date, updated_at)
  values (p_entity_type, p_entity_id, p_org_id, greatest(p_delta, 0),
          p_business_date, p_business_date, now())
  on conflict (entity_type, entity_id) do update
    set transaction_count      = greatest(c.transaction_count + p_delta, 0),
        earliest_business_date = least(coalesce(c.earliest_business_date, p_business_date),
                                       p_business_date),
        latest_business_date   = greatest(coalesce(c.latest_business_date, p_business_date),
                                          p_business_date),
        updated_at             = now();
end;
$$;

comment on function app.record_master_usage(uuid, text, uuid, date, integer) is
  'Maintains the O(1) usage counter a master rename or archive decision reads. Phase 3 '
  'financial triggers call this; there is deliberately no count(*) path anywhere.';
