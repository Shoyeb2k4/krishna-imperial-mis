-- ─────────────────────────────────────────────────────────────────────────────
-- 0007 · Date-effective tax configuration
--
-- Spec §8.1 and D-017. **No rate is hard-coded anywhere.** A rate belongs to a revenue
-- category over a period of time, and a change is a *new* period rather than an edit to
-- the old one — so a rate set next April can never restate last year's Net Sales.
--
-- The period is half-open, `[effective_from, effective_to)`. A rule ending on the day
-- another begins is therefore not an overlap: the boundary belongs to the new rule, and
-- exactly one rule applies to any date. `daterange(..., '[)')` says precisely that, which
-- is why the exclusion constraint below is stronger than anything the local SQLite mirror
-- can express — SQLite gets a repository-enforced equivalent inside a transaction.
--
-- The constraint is **partial**: `where archived_at is null`. Archiving a rule must free
-- its period for a valid replacement. A total constraint would let an archived row block
-- the very correction archiving exists to permit (owner requirement §10).
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.revenue_tax_rates (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid        not null references public.organizations(id) on delete restrict,
  business_unit_id    uuid        not null,
  revenue_category_id uuid        not null,
  -- Basis points: 1% = 100, 5% = 500. An integer, never a float — a rate that arrives as
  -- binary floating point has already lost the argument (D-002).
  rate_bp             integer     not null check (rate_bp between 0 and 10000),
  treatment           text        not null check (treatment in ('inclusive', 'exclusive', 'none')),
  effective_from      date        not null,
  -- Exclusive upper bound. Null means still in force.
  effective_to        date,
  note                text,
  archived_at         timestamptz,
  created_by          uuid        not null references public.profiles(id) on delete restrict,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  row_version         integer     not null default 1,
  change_seq          bigint      not null default nextval('app.global_change_seq'),
  -- The category is pinned together with its property, so a rule can never be attached to
  -- a category belonging to the other business unit (D-040).
  constraint revenue_tax_rates_category_fk
    foreign key (org_id, business_unit_id, revenue_category_id)
    references public.revenue_categories (org_id, business_unit_id, id) on delete restrict,
  constraint revenue_tax_rates_period_ordered
    check (effective_to is null or effective_to > effective_from),
  -- No two live rules for one category may both claim any date.
  constraint revenue_tax_rates_no_overlap
    exclude using gist (
      revenue_category_id with =,
      daterange(effective_from, effective_to, '[)') with &&
    ) where (archived_at is null)
);

create index if not exists revenue_tax_rates_category_idx
  on public.revenue_tax_rates (revenue_category_id, effective_from);
create index if not exists revenue_tax_rates_change_seq_idx
  on public.revenue_tax_rates (org_id, change_seq);

drop trigger if exists touch_revenue_tax_rates on public.revenue_tax_rates;
create trigger touch_revenue_tax_rates before insert or update on public.revenue_tax_rates
  for each row execute function app.touch_row();

-- ── Resolution ───────────────────────────────────────────────────────────────
-- The rule governing one category on one business date, or nothing.
--
-- Returning nothing rather than defaulting to zero is deliberate: a missing rule is a
-- configuration gap the user must see, not a silent "no tax" that quietly overstates Net
-- Sales. Identical semantics to TaxRuleSet.ruleFor in the domain layer.
create or replace function public.tax_rule_for(
  p_revenue_category_id uuid,
  p_business_date       date
)
returns table (
  id         uuid,
  rate_bp    integer,
  treatment  text,
  effective_from date,
  effective_to   date
)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.id, r.rate_bp, r.treatment, r.effective_from, r.effective_to
    from public.revenue_tax_rates r
   where r.revenue_category_id = p_revenue_category_id
     and r.archived_at is null
     and daterange(r.effective_from, r.effective_to, '[)') @> p_business_date
   limit 1;
$$;

comment on function public.tax_rule_for(uuid, date) is
  'The single live rule covering a date, half-open [from, to). Reads through RLS, so a '
  'caller only resolves rates for categories they may already see.';
