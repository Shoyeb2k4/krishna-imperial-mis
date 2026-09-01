-- A1 — no client-accessible write path may create a NEW incomplete revenue tax rule.
--
-- The collision trigger proves ambiguity safety. It says nothing about COMPLETENESS, and
-- a probe confirmed the gap: end-date a baseline, insert a successor without an
-- input_basis, and the row is accepted — after which `resolve_revenue_rule` refuses every
-- entry against it with KM028. A rule that cannot be used is worse than one that cannot be
-- created, because the refusal surfaces to an operator recording sales rather than to the
-- administrator who misconfigured it.
--
-- Legacy Phase 2 rows would have been grandfathered if any existed. NONE DO — verified
-- immediately before this migration: 4 live rules, 0 with a null basis — so the honest
-- expression of "new rules must be complete" is simply NOT NULL, with no exception to
-- explain and no way to reintroduce one.
do $$
declare v_incomplete integer;
begin
  select count(*) into v_incomplete
    from public.revenue_tax_rates where input_basis is null;
  if v_incomplete > 0 then
    raise exception
      'refusing to set input_basis NOT NULL: % existing rule(s) have none. They must be '
      'given an authoritative basis, or explicitly archived, by a decision — not by this '
      'migration inventing one.', v_incomplete;
  end if;
end $$;

alter table public.revenue_tax_rates alter column input_basis set not null;

comment on column public.revenue_tax_rates.input_basis is
  'Which figure the operator types: inclusive_total | pre_tax (D-080, D-097). NOT NULL since A1: a rule with no basis is unusable, and the resolver would refuse every entry against it.';

-- The legacy Phase 2 creators must now refuse deliberately rather than trip a raw NOT NULL
-- violation, which would reach a client as an unmapped 23502 instead of a refusal it can
-- explain. One deliberate revenue tax-rule write contract: `revenue_tax_rule_create`.
--
-- Their callers were audited first. Only `VendorTaxPeriodGateways` calls them, and only
-- the Phase 2 Tax screen calls that. Slice 6 moves the Tax screen onto the v1.2 contract;
-- until then it receives a refusal that names the replacement rather than silently
-- creating a rule nobody can record revenue against.
create or replace function public.tax_rule_create(
  p_revenue_category_id uuid,
  p_rate_bp             integer,
  p_treatment           text,
  p_effective_from      date,
  p_effective_to        date default null,
  p_note                text default null,
  p_mutation_id         uuid default null,
  p_id                  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.refuse('KM029', 'superseded_write_path',
    'Revenue tax rules are created through revenue_tax_rule_create, which requires the amount basis. A rule without one cannot be used to record revenue.',
    jsonb_build_object('use', 'revenue_tax_rule_create'));
  return null;
end;
$$;

create or replace function public.tax_rule_supersede(
  p_current_rule_id  uuid,
  p_base_row_version integer,
  p_rate_bp          integer,
  p_treatment        text,
  p_effective_from   date,
  p_note             text default null,
  p_mutation_id      uuid default null,
  p_new_id           uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.refuse('KM029', 'superseded_write_path',
    'Revenue tax rules are superseded through revenue_tax_rule_end_date followed by revenue_tax_rule_create, which requires the amount basis.',
    jsonb_build_object('use', 'revenue_tax_rule_end_date + revenue_tax_rule_create'));
  return null;
end;
$$;

-- `tax_rule_archive` is untouched: archiving cannot create an incomplete rule, and the
-- Tax screen and the acceptance suites both rely on it.

-- The invariant. Asserted here so a future migration that relaxes the column, or a new
-- write path that forgets, fails at deploy rather than at an operator's entry screen.
do $$
declare v_nullable text; v_bad integer;
begin
  select is_nullable into v_nullable
    from information_schema.columns
   where table_schema = 'public' and table_name = 'revenue_tax_rates'
     and column_name = 'input_basis';
  if v_nullable <> 'NO' then
    raise exception 'revenue_tax_rates.input_basis must be NOT NULL (A1)';
  end if;

  select count(*) into v_bad from public.revenue_tax_rates where input_basis is null;
  if v_bad > 0 then
    raise exception '% incomplete revenue tax rule(s) exist', v_bad;
  end if;
end $$;
