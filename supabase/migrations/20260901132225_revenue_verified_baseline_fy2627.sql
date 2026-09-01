-- Server migration ledger: 20260901132225  revenue_verified_baseline_fy2627
--
-- One file per ledger version (A0). The previous Slice 4 commit collapsed seven
-- ledger versions into two files, which is not provenance.
--
-- 5 · The verified FY 2026-27 baseline (D-096)
-- ═════════════════════════════════════════════════════════════════════════════
--
--   Restaurant  5%    inclusive   inclusive_total
--   Nandbhog    5%    inclusive   inclusive_total   (independent of Restaurant)
--   Room        5%    inclusive   inclusive_total   (generic; NO band is seeded)
--   Banquet     none  --          inclusive_total   (no dormant 5% alternative)
--
-- The Restaurant invoice shows CGST 2.5% + SGST 2.5%. The MIS records the TOTAL rate,
-- because V1 derives Net Sales and builds no GST filing engine (spec 8.1, 29). The
-- jurisdictional split is preserved in documentation, not in this schema.
--
-- Masters are resolved by their canonical immutable CODES. No environment UUID appears
-- anywhere here, and the migration fails loudly rather than guessing.
do $$
declare
  v_org uuid; v_actor uuid; v_units integer; r record;
  v_unit uuid; v_cat uuid; v_id uuid;
begin
  select count(*) into v_units from public.organizations;
  if v_units <> 1 then
    raise exception 'refusing to install the baseline: expected exactly one organisation, found %', v_units;
  end if;
  select id into v_org from public.organizations;

  select p.id into v_actor
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id and ur.revoked_at is null
    join public.roles ro on ro.id = ur.role_id and ro.code = 'owner'
   order by p.created_at limit 1;
  if v_actor is null then
    raise exception 'refusing to install the baseline: no owner profile exists to attribute it to';
  end if;

  for r in
    select * from (values
      ('CCR', 'RESTAURANT',  500, 'inclusive', 'inclusive_total'),
      ('CCR', 'NANDBHOG',    500, 'inclusive', 'inclusive_total'),
      ('HKI', 'ROOM',        500, 'inclusive', 'inclusive_total'),
      ('HKI', 'BANQUET',       0, 'none',      'inclusive_total')
    ) as t(unit_code, cat_code, rate_bp, treatment, input_basis)
  loop
    select id into v_unit from public.business_units
     where org_id = v_org and code = r.unit_code and archived_at is null;
    if v_unit is null then
      raise exception 'baseline: business unit % does not exist', r.unit_code;
    end if;
    if (select count(*) from public.business_units
         where org_id = v_org and code = r.unit_code and archived_at is null) <> 1 then
      raise exception 'baseline: business unit % is ambiguous', r.unit_code;
    end if;

    select id into v_cat from public.revenue_categories
     where org_id = v_org and code = r.cat_code and business_unit_id = v_unit
       and archived_at is null;
    if v_cat is null then
      raise exception 'baseline: revenue category % does not exist under business unit %',
        r.cat_code, r.unit_code;
    end if;
    if (select count(*) from public.revenue_categories
         where org_id = v_org and code = r.cat_code and business_unit_id = v_unit
           and archived_at is null) <> 1 then
      raise exception 'baseline: revenue category % under % is ambiguous', r.cat_code, r.unit_code;
    end if;

    -- Idempotent by intent rather than by ON CONFLICT: if a live rule already covers this
    -- category from this date, leave it alone and say so. Silently rewriting configured
    -- tax would be exactly the thing this project refuses to do.
    if exists (
      select 1 from public.revenue_tax_rates
       where revenue_category_id = v_cat and archived_at is null
         and effective_from = date '2026-04-01'
    ) then
      raise notice 'baseline: % / % already configured from 2026-04-01, left untouched',
        r.unit_code, r.cat_code;
      continue;
    end if;

    perform app.lock_revenue_category(v_org, v_cat);

    insert into public.revenue_tax_rates (
      org_id, business_unit_id, revenue_category_id, rate_bp, treatment,
      effective_from, input_basis, note, created_by)
    values (
      v_org, v_unit, v_cat, r.rate_bp, r.treatment, date '2026-04-01', r.input_basis,
      'Verified FY 2026-27 baseline (D-096). Source: current billing evidence confirmed by the project lead 2026-09-01.',
      v_actor)
    returning id into v_id;

    perform app.assert_revenue_rules_unambiguous(v_id);

    perform app.write_audit(v_org, 'revenue_tax_rate', v_id, 'created', v_actor, null,
      jsonb_build_object('source', 'verified baseline migration',
                         'unit', r.unit_code, 'category', r.cat_code,
                         'rate_bp', r.rate_bp, 'treatment', r.treatment,
                         'input_basis', r.input_basis, 'effective_from', '2026-04-01'),
      'Initial verified configuration installed by migration (D-096)', v_unit, null);
  end loop;
end $$;

-- Prove the intended end state: exactly four live rules, and NOTHING speculative.
do $$
declare v_rules integer; v_bands integer; v_subs integer; v_stats integer;
begin
  select count(*) into v_rules from public.revenue_tax_rates where archived_at is null;
  select count(*) into v_bands from public.revenue_value_bands;
  select count(*) into v_subs  from public.revenue_supply_subtypes;
  select count(*) into v_stats from public.business_unit_tax_statuses;

  if v_rules <> 4 then
    raise exception 'baseline: expected exactly 4 live tax rules, found %', v_rules;
  end if;
  if v_bands <> 0 then
    raise exception 'baseline: no value band may be seeded, found %', v_bands;
  end if;
  if v_subs <> 0 then
    raise exception 'baseline: no supply subtype may be seeded, found %', v_subs;
  end if;
  if v_stats <> 0 then
    raise exception 'baseline: no premises status may be seeded, found %', v_stats;
  end if;
end $$;
