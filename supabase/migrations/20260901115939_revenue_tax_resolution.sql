-- Server migration ledger: 20260901115939  revenue_tax_resolution
--
-- One file per ledger version (A0). The previous Slice 4 commit collapsed seven
-- ledger versions into two files, which is not provenance.
--
-- 2 · The conditional tax doctrine, made authoritative
-- ═════════════════════════════════════════════════════════════════════════════
--
-- D-094: for any fact set at a business date, ZERO or EXACTLY ONE rule may match. Zero
-- refuses, one resolves, more than one is a configuration defect and is refused. There is
-- no most-specific-wins and no runtime tiebreak.
--
-- A NULL discriminator means "does not depend on that dimension", which means it matches
-- EVERY value of it. So a wildcard rule and a specific rule over overlapping dates both
-- match the same entry: they COLLIDE rather than the specific one winning.

-- Two active rules for one category have overlapping applicability when their date ranges
-- overlap AND, on every discriminator, either is a wildcard or they name the same thing.
--
-- Value bands are compared by their TARIFF RANGE, not merely by id: two distinct band
-- rows can describe overlapping ranges, and distinct ids must not be able to hide
-- overlapping financial applicability. Band boundaries are write-once (D-100), so a range
-- compared today means the same thing tomorrow.
create or replace function app.revenue_rules_overlap(
  p_left  public.revenue_tax_rates,
  p_right public.revenue_tax_rates
)
returns boolean language sql stable security definer set search_path = '' as $$
  select
    p_left.revenue_category_id = p_right.revenue_category_id
    and daterange(p_left.effective_from, p_left.effective_to, '[)')
        && daterange(p_right.effective_from, p_right.effective_to, '[)')
    and (
      p_left.value_band_id is null
      or p_right.value_band_id is null
      or p_left.value_band_id = p_right.value_band_id
      or exists (
        select 1
          from public.revenue_value_bands bl, public.revenue_value_bands br
         where bl.id = p_left.value_band_id
           and br.id = p_right.value_band_id
           and int8range(coalesce(bl.floor_minor, 0), bl.ceiling_minor, '[)')
               && int8range(coalesce(br.floor_minor, 0), br.ceiling_minor, '[)')
      )
    )
    and (
      p_left.supply_subtype_id is null
      or p_right.supply_subtype_id is null
      or p_left.supply_subtype_id = p_right.supply_subtype_id
    )
    and (
      p_left.premises_status_code is null
      or p_right.premises_status_code is null
      or p_left.premises_status_code = p_right.premises_status_code
    );
$$;

comment on function app.revenue_rules_overlap is
  'True when two rules could both match one fact set (D-094). NULL is a wildcard and collides with everything; value bands are compared by tariff range, so distinct ids cannot hide overlapping applicability.';

-- D-095. A validating trigger checks rows visible to its own transaction. Two concurrent
-- inserts can each be individually valid while their pair is ambiguous — classic write
-- skew, which no amount of careful validation inside one transaction can detect.
--
-- The key is derived with hashtextextended over the org and category uuids: a stable
-- Postgres builtin, identical in every session and across restarts, NOT a process-local
-- hash. Scoped to (org, category) so configuring Restaurant never blocks Room.
create or replace function app.lock_revenue_category(p_org uuid, p_category uuid)
returns void language sql security definer set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended(p_org::text || ':' || p_category::text, 0));
$$;

comment on function app.lock_revenue_category is
  'Transaction-level advisory lock keyed deterministically on (org, revenue category). Serialises tax-rule configuration for one category so two concurrent writes cannot jointly create an ambiguous set (D-095).';

create or replace function app.assert_revenue_rules_unambiguous(p_rule_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_rule  public.revenue_tax_rates;
  v_other public.revenue_tax_rates;
begin
  select * into v_rule from public.revenue_tax_rates where id = p_rule_id;
  if not found or v_rule.archived_at is not null then
    return;
  end if;

  for v_other in
    select * from public.revenue_tax_rates
     where revenue_category_id = v_rule.revenue_category_id
       and id <> v_rule.id
       and archived_at is null
  loop
    if app.revenue_rules_overlap(v_rule, v_other) then
      perform app.refuse('KM025', 'ambiguous_tax_configuration',
        'Another tax rule already applies to the same revenue over the same dates. Two rules that could both match one entry would make its tax ambiguous, and no rule is ever chosen by ranking.',
        jsonb_build_object('rule_id', v_rule.id, 'conflicts_with', v_other.id));
    end if;
  end loop;
end; $$;

-- On the trigger, so no write path can skip it — including a direct table write, the
-- legacy Phase 2 tax_rule_create, or an archive that changes applicability.
create or replace function app.guard_revenue_rule_write()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_row public.revenue_tax_rates;
begin
  v_row := case when tg_op = 'DELETE' then old else new end;
  perform app.lock_revenue_category(v_row.org_id, v_row.revenue_category_id);
  if tg_op <> 'DELETE' then
    perform app.assert_revenue_rules_unambiguous(new.id);
  end if;
  return null;
end; $$;

drop trigger if exists trg_revenue_rule_unambiguous on public.revenue_tax_rates;
create constraint trigger trg_revenue_rule_unambiguous
  after insert or update on public.revenue_tax_rates
  deferrable initially immediate
  for each row execute function app.guard_revenue_rule_write();

-- ONLY NOW is the Phase 2 constraint obsolete. The replacement exists above, so no window
-- opens in which ambiguity could be written. The old constraint was
-- `exclude using gist (revenue_category_id with =, daterange &&)`: correct for a date-only
-- model and impossible for D-081, because Room's two value bands are by construction two
-- live rules for one category over the same dates (D-093).
alter table public.revenue_tax_rates drop constraint if exists revenue_tax_rates_no_overlap;

do $$
begin
  if not exists (
    select 1 from pg_trigger
     where tgname = 'trg_revenue_rule_unambiguous'
       and tgrelid = 'public.revenue_tax_rates'::regclass
  ) then
    raise exception 'refusing to leave revenue_tax_rates unguarded: the replacement trigger is absent';
  end if;
  if exists (select 1 from pg_constraint where conname = 'revenue_tax_rates_no_overlap') then
    raise exception 'the obsolete Phase 2 exclusion constraint is still present';
  end if;
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
