-- Server migration ledger: 20260901132003  revenue_resolver_numbering_projection
--
-- One file per ledger version (A0). The previous Slice 4 commit collapsed seven
-- ledger versions into two files, which is not provenance.
--
-- 3 · Resolution, arithmetic, numbering and the read boundary
-- ═════════════════════════════════════════════════════════════════════════════

-- Inputs are explicit FACTS, never a caller-supplied tax result. The server resolves
-- independently and its answer is final (D-037).
create or replace function app.resolve_revenue_rule(
  p_category uuid,
  p_date     date,
  p_band     uuid default null,
  p_subtype  uuid default null,
  p_premises text default null
)
returns public.revenue_tax_rates
language plpgsql stable security definer set search_path = '' as $$
declare
  v_matches public.revenue_tax_rates[];
  v_rule    public.revenue_tax_rates;
  v_needs   text;
begin
  select array_agg(r) into v_matches
    from public.revenue_tax_rates r
   where r.revenue_category_id = p_category
     and r.archived_at is null
     and r.effective_from <= p_date
     and (r.effective_to is null or r.effective_to > p_date)
     -- A null discriminator on the RULE is a wildcard and matches anything. A null on the
     -- FACTS against a specific rule is not a match: the entry has not stated the thing
     -- the rule is about.
     and (r.value_band_id is null or r.value_band_id = p_band)
     and (r.supply_subtype_id is null or r.supply_subtype_id = p_subtype)
     and (r.premises_status_code is null or r.premises_status_code = p_premises);

  if v_matches is null or array_length(v_matches, 1) is null then
    -- Distinguish "no rule exists" from "you have not told it which band this is". The
    -- remedies differ and so must the messages.
    select case
             when bool_or(r.value_band_id is not null) and p_band is null then 'value band'
             when bool_or(r.supply_subtype_id is not null) and p_subtype is null then 'supply subtype'
             when bool_or(r.premises_status_code is not null) and p_premises is null then 'premises tax status'
           end
      into v_needs
      from public.revenue_tax_rates r
     where r.revenue_category_id = p_category
       and r.archived_at is null
       and r.effective_from <= p_date
       and (r.effective_to is null or r.effective_to > p_date);

    if v_needs is not null then
      perform app.refuse('KM026', 'missing_tax_fact',
        'This revenue entry needs a ' || v_needs || ' before its tax can be determined.',
        jsonb_build_object('dimension', v_needs));
    end if;

    perform app.refuse('KM027', 'no_tax_rule',
      'No tax rule configured for this revenue entry.',
      jsonb_build_object('revenue_category_id', p_category, 'business_date', p_date));
  end if;

  if array_length(v_matches, 1) > 1 then
    perform app.refuse('KM025', 'ambiguous_tax_configuration',
      'More than one tax rule applies to this revenue entry. The tax configuration must be corrected before this can be recorded.',
      jsonb_build_object('matches', array_length(v_matches, 1)));
  end if;

  v_rule := v_matches[1];

  if v_rule.input_basis is null then
    perform app.refuse('KM028', 'incomplete_tax_rule',
      'The tax rule that applies here is incomplete: it does not say which amount is entered. It must be corrected before revenue can be recorded against it.',
      jsonb_build_object('rule_id', v_rule.id));
  end if;

  return v_rule;
end; $$;

comment on function app.resolve_revenue_rule is
  'Zero or exactly one (D-094). Takes facts, never a caller-supplied tax result. KM025 ambiguous, KM026 missing fact, KM027 no rule, KM028 incomplete.';

-- The same specification as Dart's TaxRule.compute. Half-up is (2n + d) / (2d) on
-- integers, which rounds .5 away from zero without ever touching a floating point value.
create or replace function app.revenue_compute(
  p_entered bigint, p_rate_bp integer, p_treatment text
)
returns table (gross bigint, tax bigint, net bigint)
language plpgsql immutable security invoker set search_path = '' as $$
declare
  v_tax bigint;
begin
  if p_entered < 0 then
    raise exception 'revenue must not be negative';
  end if;
  if p_treatment = 'none' then
    return query select p_entered, 0::bigint, p_entered;
  elsif p_treatment = 'inclusive' then
    v_tax := (2 * p_entered * p_rate_bp + (10000 + p_rate_bp)) / (2 * (10000 + p_rate_bp));
    return query select p_entered, v_tax, p_entered - v_tax;
  elsif p_treatment = 'exclusive' then
    v_tax := (2 * p_entered * p_rate_bp + 10000) / 20000;
    return query select p_entered + v_tax, v_tax, p_entered;
  else
    raise exception 'unknown treatment %', p_treatment;
  end if;
end; $$;

comment on function app.revenue_compute is
  'The canonical integer half-up specification, shared with Dart TaxRule.compute. No floating point ever touches a currency amount.';

-- KI-REV numbering: organisation-wide, Indian financial year, its OWN sequence.
create table if not exists public.revenue_number_counters (
  org_id         uuid not null references public.organizations(id) on delete restrict,
  financial_year text not null,
  last_value     bigint not null default 0,
  primary key (org_id, financial_year)
);

alter table public.revenue_number_counters enable row level security;
alter table public.revenue_number_counters force row level security;
revoke all on public.revenue_number_counters from anon, authenticated;

create or replace function app.revenue_financial_year(p_date date)
returns text language sql immutable security invoker set search_path = '' as $$
  -- 1 April - 31 March (D-014). 15 June 2026 is FY 26-27.
  select case
    when extract(month from p_date) >= 4
      then to_char(p_date, 'YY') || '-' || to_char(p_date + interval '1 year', 'YY')
    else to_char(p_date - interval '1 year', 'YY') || '-' || to_char(p_date, 'YY')
  end;
$$;

create or replace function app.next_revenue_number(p_org uuid, p_date date)
returns table (number text, financial_year text)
language plpgsql security definer set search_path = '' as $$
declare
  v_fy   text := app.revenue_financial_year(p_date);
  v_next bigint;
begin
  -- Concurrency-safe by construction: the upsert takes a row lock on exactly this
  -- (org, financial year), so two concurrent acceptances serialise on the counter and
  -- neither can read the same last_value. Gaps are avoided because the number is issued
  -- only after every validation has passed.
  insert into public.revenue_number_counters (org_id, financial_year, last_value)
       values (p_org, v_fy, 1)
  on conflict (org_id, financial_year)
    do update set last_value = public.revenue_number_counters.last_value + 1
  returning public.revenue_number_counters.last_value into v_next;

  return query select 'KI-REV-' || v_fy || '-' || lpad(v_next::text, 6, '0'), v_fy;
end; $$;

comment on function app.next_revenue_number is
  'KI-REV-26-27-000001. Organisation-wide, FY-reset, separate from the expense sequence, issued only after canonical acceptance.';
