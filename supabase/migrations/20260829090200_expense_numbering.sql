-- ─────────────────────────────────────────────────────────────────────────────
-- 0027 · Allocating the expense number
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.1 · Phase 3
--
-- `KI-EXP-26-27-000001`. Organisation-wide, financial-year scoped, sequence resetting
-- each 1 April, and **never** prefixed with a property because one expense may be
-- allocated across both.
--
-- Three properties this has to have, and one it must not.
--
-- MUST: allocated only after the record is accepted. A number is a claim that a document
-- exists; issuing one for a write that then fails would leave a gap nobody can explain.
--
-- MUST: concurrency-safe, with no duplicates, ever. Two accountants saving at the same
-- instant in the same financial year must get 41 and 42, not 41 twice. A counter row per
-- (org, year) is locked with `FOR UPDATE`, so the second transaction waits for the first
-- rather than reading a stale maximum. `max(txn_number) + 1` is exactly the pattern that
-- looks correct and issues duplicates under load.
--
-- MUST: derive the year from the record's own business date, so a document recorded on
-- 2 April for the trading day of 31 March takes a number in the year that is closing.
--
-- MUST NOT: be reservable by a client. Two devices offline for a week would both reserve
-- `000042`. Offline, an expense is identified by its client-generated UUID and shows its
-- number the moment the server issues one.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.document_number_counters (
  org_id         uuid     not null references public.organizations (id),
  document_kind  text     not null,
  financial_year smallint not null,
  next_sequence  integer  not null default 1 check (next_sequence > 0),
  updated_at     timestamptz not null default now(),
  primary key (org_id, document_kind, financial_year)
);

comment on table public.document_number_counters is
  'One row per organisation, document kind and financial year. Locked FOR UPDATE while a '
  'number is issued, so concurrent writers queue instead of colliding. Never read by a '
  'client: no policy grants SELECT.';

-- Deliberately no RLS policy. A counter is not user data, and the only legitimate reader
-- is the SECURITY DEFINER function below.
alter table public.document_number_counters enable row level security;

-- The Indian financial year a date falls in, named by its opening year.
create or replace function app.financial_year_of(p_date date)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select (case when extract(month from p_date) >= 4
               then extract(year from p_date)
               else extract(year from p_date) - 1 end)::smallint;
$$;

comment on function app.financial_year_of(date) is
  'Indian financial year, 1 April to 31 March, named by its opening year. 2026-06-15 and '
  '2027-03-31 both yield 2026.';

create or replace function app.allocate_expense_number(
  p_org_id        uuid,
  p_business_date date
)
-- Column names deliberately unlike the counter table's own, because a RETURNS TABLE
-- column is an OUT parameter: `financial_year` here would shadow the column of the same
-- name inside the INSERT below, and Postgres refuses the ambiguity at call time.
returns table (issued_number text, issued_year smallint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year smallint := app.financial_year_of(p_business_date);
  v_seq  integer;
begin
  -- Insert-or-lock, in one statement. A concurrent caller either blocks on the unique
  -- index (fresh year) or on the row lock the DO UPDATE takes (existing year), so the
  -- two serialise instead of both reading the same `next_sequence`. `max(...) + 1` is
  -- the pattern that looks correct and issues duplicates under exactly this load.
  --
  -- RETURNING sees the row *after* the statement, so the number just issued is one less
  -- than what the counter now points at — 2-1 = 1 on the first insert, and old+1-1 = old
  -- on every conflict thereafter.
  insert into public.document_number_counters as c
         (org_id, document_kind, financial_year, next_sequence)
  values (p_org_id, 'EXP', v_year, 2)
  on conflict (org_id, document_kind, financial_year) do update
    set next_sequence = c.next_sequence + 1,
        updated_at    = now()
  returning c.next_sequence - 1 into v_seq;

  return query
    select format('KI-EXP-%s-%s-%s',
                  to_char(v_year % 100, 'FM00'),
                  to_char((v_year + 1) % 100, 'FM00'),
                  to_char(v_seq, 'FM000000')),
           v_year;
end;
$$;

comment on function app.allocate_expense_number(uuid, date) is
  'Issues the next expense number for the organisation and financial year, under a row '
  'lock. Called only after a write has been accepted. Never reachable by a client.';

revoke all on function app.financial_year_of(date) from public, anon, authenticated;
revoke all on function app.allocate_expense_number(uuid, date)
  from public, anon, authenticated;
