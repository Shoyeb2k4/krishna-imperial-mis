-- ─────────────────────────────────────────────────────────────────────────────
-- 0006 · Period locks and their append-only history
--
-- Spec §13.4 and D-026. Once a period is closed every create, edit, void and
-- business-date correction touching it is rejected server-side; only the Owner may
-- reopen, and only with a reason that is written down.
--
-- **No code path reopens a period implicitly.** There is no auto-unlock on edit, no
-- cascade and no silent bypass — and because the only way to change `state` is through
-- the RPCs in 0012, that is a property of the schema rather than a promise about it.
--
-- The lock is keyed by `period_key` ('YYYY-MM'), matching BusinessDate.periodKey and the
-- local SQLite mirror, so the client and the server key on the same string. (The Phase 0
-- proposal in docs/DATABASE_SCHEMA.md §7 sketched period_start/period_end date columns;
-- the implemented client settled on the period key, and one representation is worth more
-- than two that must be kept in step. Recorded as D-042.)
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.period_locks (
  id               uuid primary key default extensions.gen_random_uuid(),
  org_id           uuid        not null references public.organizations(id) on delete restrict,
  -- Null means every business unit: an organisation-wide close.
  business_unit_id uuid,
  period_key       text        not null check (period_key ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  state            text        not null check (state in ('open', 'closed')),
  closed_by        uuid        references public.profiles(id) on delete restrict,
  closed_at        timestamptz,
  reopened_by      uuid        references public.profiles(id) on delete restrict,
  reopened_at      timestamptz,
  reopen_reason    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  row_version      integer     not null default 1,
  change_seq       bigint      not null default nextval('app.global_change_seq'),
  constraint period_locks_unit_fk
    foreign key (org_id, business_unit_id)
    references public.business_units (org_id, id) on delete restrict,
  -- A closed period always knows who closed it and when. There is no anonymous close.
  constraint period_locks_closed_is_attributed
    check (state = 'open' or (closed_by is not null and closed_at is not null))
);

-- One lock per (org, unit, period). The coalesce closes the hole Postgres would otherwise
-- leave: two NULL unit ids compare as distinct, so an organisation-wide period could be
-- closed twice and reopened once.
create unique index if not exists period_locks_unique_period
  on public.period_locks (
    org_id, period_key,
    coalesce(business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists period_locks_change_seq_idx on public.period_locks (org_id, change_seq);
create index if not exists period_locks_closed_idx
  on public.period_locks (org_id, period_key) where state = 'closed';

drop trigger if exists touch_period_locks on public.period_locks;
create trigger touch_period_locks before insert or update on public.period_locks
  for each row execute function app.touch_row();

-- ── Append-only history ──────────────────────────────────────────────────────
-- A period may close and reopen repeatedly; each event stands on its own row with its
-- actor, its server timestamp and — for a reopen — its mandatory reason.
create table if not exists public.period_lock_events (
  id             uuid primary key default extensions.gen_random_uuid(),
  org_id         uuid        not null references public.organizations(id) on delete restrict,
  period_lock_id uuid        not null references public.period_locks(id) on delete restrict,
  action         text        not null check (action in ('close', 'reopen')),
  reason         text,
  actor_id       uuid        not null references public.profiles(id) on delete restrict,
  occurred_at    timestamptz not null default now(),
  mutation_id    uuid,
  -- Spec §13.4: reopening demands a reason. Enforced here, so no path can reopen a
  -- period without recording why.
  constraint period_lock_events_reopen_needs_reason
    check (action <> 'reopen' or (reason is not null and length(btrim(reason)) > 0))
);

create index if not exists period_lock_events_lock_idx
  on public.period_lock_events (period_lock_id, occurred_at desc);

drop trigger if exists append_only_period_lock_events on public.period_lock_events;
create trigger append_only_period_lock_events
  before update or delete on public.period_lock_events
  for each row execute function app.refuse_mutation();
