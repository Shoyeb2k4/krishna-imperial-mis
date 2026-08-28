-- ─────────────────────────────────────────────────────────────────────────────
-- 0013 · Development seed — business structure only
--
-- **No financial data.** No amounts, no transactions, no credentials, no production
-- history (D-027, spec §32). Everything here is business structure taken from master
-- spec §4, and every row is ordinary editable master data.
--
-- Idempotent by construction, in the way that matters: every id is a **UUID v5 derived
-- from the record's permanent code path**, and every insert is `on conflict do nothing`.
-- Re-running changes nothing, and — the part that actually needs care — re-running after
-- the owner has renamed something does **not** undo their rename, because the conflict
-- target is the id and the update clause is absent.
--
-- Deriving ids rather than generating them also makes the local SQLite seed and this one
-- produce *the same ids for the same records*. Without that, a device that seeded itself
-- offline would later meet a server holding the identical hierarchy under different ids,
-- and the two would have to be reconciled by name — which is exactly the fragile,
-- rename-sensitive matching the whole master-identity design exists to avoid (D-035).
-- The namespace below is duplicated in lib/data/local/seed/master_seed.dart and the two
-- must never diverge; a test asserts they agree.
-- ─────────────────────────────────────────────────────────────────────────────

create extension if not exists "uuid-ossp" with schema extensions;

-- The seed namespace. A fixed, arbitrary, non-secret constant: its only job is to make
-- the derivation reproducible on both platforms and in Postgres.
create or replace function app.seed_id(p_path text)
returns uuid
language sql
immutable
security invoker
set search_path = ''
as $$
  select extensions.uuid_generate_v5(
           'd9d3f0a6-4c2b-5f7e-9a10-6b1e2c8f4a70'::uuid, p_path);
$$;

comment on function app.seed_id(text) is
  'UUID v5 over the record permanent code path, e.g. cat:CCR/FB/FOOD_PROD/KIRANA. '
  'Mirrored exactly by seedId() in lib/data/local/seed/master_seed.dart.';

do $$
declare
  v_org uuid := app.seed_id('org:KRISHNA');
begin
  -- ── Organisation ───────────────────────────────────────────────────────────
  insert into public.organizations (id, name, legal_name, financial_year_start_month,
                                    timezone, base_currency)
  values (v_org, 'Krishna Imperial', 'Krishna Imperial', 4, 'Asia/Kolkata', 'INR')
  on conflict (id) do nothing;

  -- Configuration, not a constant in code (spec §13.3).
  insert into public.org_settings (org_id, key, value)
  values (v_org, 'edit_window_days', '7'::jsonb)
  on conflict (org_id, key) do nothing;

  -- ── Business units ─────────────────────────────────────────────────────────
  insert into public.business_units (id, org_id, code, name, kind, timezone,
                                     business_day_cutoff, sort_order)
  values
    (app.seed_id('bu:CCR'), v_org, 'CCR', 'Crystal Canopy Rooftop', 'restaurant',
     'Asia/Kolkata', '05:00', 0),
    (app.seed_id('bu:HKI'), v_org, 'HKI', 'Hotel Krishna Imperial', 'hotel',
     'Asia/Kolkata', '05:00', 1)
  on conflict (id) do nothing;

  -- ── Revenue categories ─────────────────────────────────────────────────────
  -- Nandbhog is a revenue category under Crystal Canopy, not a business unit (D-024).
  insert into public.revenue_categories (id, org_id, business_unit_id, code, name, sort_order)
  values
    (app.seed_id('rev:CCR/RESTAURANT'), v_org, app.seed_id('bu:CCR'), 'RESTAURANT', 'Restaurant', 0),
    (app.seed_id('rev:CCR/NANDBHOG'),   v_org, app.seed_id('bu:CCR'), 'NANDBHOG',   'Nandbhog',   1),
    (app.seed_id('rev:HKI/ROOM'),       v_org, app.seed_id('bu:HKI'), 'ROOM',       'Room',       0),
    (app.seed_id('rev:HKI/BANQUET'),    v_org, app.seed_id('bu:HKI'), 'BANQUET',    'Banquet',    1)
  on conflict (id) do nothing;

  -- ── Payment methods ────────────────────────────────────────────────────────
  insert into public.payment_methods (id, org_id, code, name, requires_reference, sort_order)
  values
    (app.seed_id('pm:CASH'),   v_org, 'CASH',   'Cash',                false, 0),
    (app.seed_id('pm:UPI'),    v_org, 'UPI',    'UPI',                 true,  1),
    (app.seed_id('pm:BANK'),   v_org, 'BANK',   'Bank Transfer',       true,  2),
    (app.seed_id('pm:CARD'),   v_org, 'CARD',   'Card',                false, 3),
    (app.seed_id('pm:CREDIT'), v_org, 'CREDIT', 'Credit / On Account', false, 4)
  on conflict (id) do nothing;

  -- ── Roles ──────────────────────────────────────────────────────────────────
  -- `requires_unit_scope` is false for Owner alone. Everything else must name a
  -- property, enforced by the trigger in 0005 (D-025).
  insert into public.roles (id, org_id, code, name, is_system, requires_unit_scope)
  values
    (app.seed_id('role:owner'),      v_org, 'owner',      'Owner',      true, false),
    (app.seed_id('role:manager'),    v_org, 'manager',    'Manager',    true, true),
    (app.seed_id('role:accountant'), v_org, 'accountant', 'Accountant', true, true),
    (app.seed_id('role:data_entry'), v_org, 'data_entry', 'Data Entry', true, true)
  on conflict (id) do nothing;
end $$;

-- ── Departments, sections and expense categories ─────────────────────────────
-- Written as data rather than as a hand-unrolled list of INSERTs, so the shape stays
-- readable next to master spec §4 and a typo cannot silently attach a Hotel Krishna
-- section to a Crystal Canopy department — the composite foreign keys would refuse it,
-- but the structure here should be legible enough that it never gets that far.
do $$
declare
  v_org uuid := app.seed_id('org:KRISHNA');
  rec   record;
begin
  for rec in
    select * from (values
      -- unit, dept code, dept name, dept order, section code, section name, section order,
      -- category code, category name, nature, shared, category order
      ('CCR','FB','F&B / Kitchen',0,'FOOD_PROD','Food Production',0,'KIRANA','Kirana & Pulses','operating',false,0),
      ('CCR','FB','F&B / Kitchen',0,'FOOD_PROD','Food Production',0,'VEG_FRUIT','Vegetables & Fruits','operating',false,1),
      ('CCR','FB','F&B / Kitchen',0,'FOOD_PROD','Food Production',0,'MILK_DAHI','Milk & Dahi','operating',false,2),
      ('CCR','FB','F&B / Kitchen',0,'FOOD_PROD','Food Production',0,'PANEER','Paneer / Dairy','operating',false,3),
      ('CCR','FB','F&B / Kitchen',0,'KITCHEN_FUEL','Kitchen Fuel',1,'CYL_COAL','Cylinder & Coal','utility',false,0),
      ('CCR','CCR_PAYROLL','Payroll',1,'CCR_WAGES','Wages',0,'KITCHEN_PAYROLL','Kitchen / F&B Payroll','payroll',false,0),
      ('CCR','CCR_PAYROLL','Payroll',1,'CCR_WAGES','Wages',0,'OTHER_WAGES','Other Wages','payroll',false,1),
      ('CCR','CCR_PAYROLL','Payroll',1,'CCR_WAGES','Wages',0,'INCENTIVES','Incentives','payroll',false,2),
      ('CCR','CCR_UTIL','Utilities',2,'CCR_UTIL_SVC','Utility Services',0,'ELECTRICITY','Electricity','utility',true,0),
      ('CCR','CCR_UTIL','Utilities',2,'CCR_UTIL_SVC','Utility Services',0,'WATER','Water','utility',true,1),
      ('CCR','CCR_OTHER','Other',3,'CCR_OTHER_OPS','Other Operations',0,'OTHER_OPEX','Other Operating Expenses','other',false,0),

      ('HKI','HK','Housekeeping',0,'HK_OPS','Housekeeping Operations',0,'HK_SALARY','Housekeeping Salary','payroll',false,0),
      ('HKI','HK','Housekeeping',0,'HK_OPS','Housekeeping Operations',0,'HK_EXPENSES','Housekeeping Expenses','operating',false,1),
      ('HKI','FO','Front Office',1,'FO_OPS','Front Office Operations',0,'FO_SALARY','Front Office Salary','payroll',false,0),
      ('HKI','HKI_UTIL','Utilities',2,'HKI_WATER','Water',0,'WATER','Water','utility',true,0),
      ('HKI','HKI_UTIL','Utilities',2,'HKI_WATER','Water',0,'TANKER','Tanker','utility',false,1),
      ('HKI','HKI_UTIL','Utilities',2,'HKI_WATER','Water',0,'WATER_CANS','Water Cans','utility',false,2),
      ('HKI','HKI_UTIL','Utilities',2,'HKI_POWER','Power & Fuel',1,'ELECTRICITY','Electricity','utility',true,0),
      ('HKI','HKI_UTIL','Utilities',2,'HKI_POWER','Power & Fuel',1,'DIESEL','Diesel','utility',false,1),
      ('HKI','HKI_MAINT','Maintenance',3,'HKI_BUILDING','Building & Upkeep',0,'BUILDING','Building Expenses','operating',false,0),
      ('HKI','HKI_MAINT','Maintenance',3,'HKI_BUILDING','Building & Upkeep',0,'MAINTENANCE','Maintenance','operating',false,1),
      ('HKI','HKI_PAYROLL','Payroll',4,'HKI_WAGES','Wages',0,'PAYROLL','Payroll','payroll',false,0),
      ('HKI','HKI_OTHER','Other',5,'HKI_OTHER_OPS','Other Operations',0,'OTHER_OPEX','Other Operating Expenses','other',false,0)
    ) as t(unit, dept_code, dept_name, dept_order, sec_code, sec_name, sec_order,
           cat_code, cat_name, nature, shared, cat_order)
  loop
    insert into public.departments (id, org_id, business_unit_id, code, name, sort_order)
    values (app.seed_id(format('dept:%s/%s', rec.unit, rec.dept_code)), v_org,
            app.seed_id(format('bu:%s', rec.unit)), rec.dept_code, rec.dept_name, rec.dept_order)
    on conflict (id) do nothing;

    insert into public.sections (id, org_id, business_unit_id, department_id, code, name, sort_order)
    values (app.seed_id(format('sec:%s/%s/%s', rec.unit, rec.dept_code, rec.sec_code)), v_org,
            app.seed_id(format('bu:%s', rec.unit)),
            app.seed_id(format('dept:%s/%s', rec.unit, rec.dept_code)),
            rec.sec_code, rec.sec_name, rec.sec_order)
    on conflict (id) do nothing;

    insert into public.expense_categories (id, org_id, business_unit_id, department_id,
                                           section_id, code, name, nature,
                                           is_shared_by_default, sort_order)
    values (app.seed_id(format('cat:%s/%s/%s/%s', rec.unit, rec.dept_code, rec.sec_code, rec.cat_code)),
            v_org, app.seed_id(format('bu:%s', rec.unit)),
            app.seed_id(format('dept:%s/%s', rec.unit, rec.dept_code)),
            app.seed_id(format('sec:%s/%s/%s', rec.unit, rec.dept_code, rec.sec_code)),
            rec.cat_code, rec.cat_name, rec.nature, rec.shared, rec.cat_order)
    on conflict (id) do nothing;
  end loop;
end $$;

-- ── Role capability bundles ──────────────────────────────────────────────────
-- Mirrors RoleTemplates in lib/domain/auth/capability.dart exactly. A test asserts the
-- two agree, because a bundle that drifts is a silent privilege change.
do $$
declare
  v_org uuid := app.seed_id('org:KRISHNA');
begin
  -- Owner: everything.
  insert into public.role_capabilities (role_id, capability_code)
  select app.seed_id('role:owner'), c.code from public.capabilities c
  on conflict do nothing;

  insert into public.role_capabilities (role_id, capability_code)
  select app.seed_id('role:manager'), code from unnest(array[
    'expense.view.all', 'expense.create', 'expense.edit.own',
    'revenue.view', 'revenue.create', 'revenue.edit',
    'attachment.view', 'attachment.upload',
    'reports.view', 'masters.view']) as code
  on conflict do nothing;

  insert into public.role_capabilities (role_id, capability_code)
  select app.seed_id('role:accountant'), code from unnest(array[
    'expense.view.all', 'expense.create', 'expense.edit.all', 'expense.void',
    'expense.allocate_periods',
    'revenue.view', 'revenue.create', 'revenue.edit', 'revenue.void',
    'transaction.correct.beyond_window', 'transaction.correct.business_date',
    'attachment.view', 'attachment.upload',
    'reports.view', 'reports.export', 'reports.print',
    'masters.view', 'audit.view']) as code
  on conflict do nothing;

  insert into public.role_capabilities (role_id, capability_code)
  select app.seed_id('role:data_entry'), code from unnest(array[
    'expense.view.own', 'expense.create', 'expense.edit.own',
    'revenue.create', 'attachment.upload', 'masters.view']) as code
  on conflict do nothing;
end $$;

-- ── Deliberately NOT seeded: tax rates ───────────────────────────────────────
-- Spec §8.1 forbids a hard-coded rate anywhere, and a rate committed to a migration is a
-- rate in source control that nobody chose. The domain already treats a missing rule as a
-- configuration gap the user must see, rather than as a silent "no tax" that would
-- overstate Net Sales — so an empty timeline is the honest starting state.
--
-- The owner supplies the first rule per revenue category (rate, treatment, effective
-- from) through the Tax screen or `tax_rule_create`. Recorded as an open question rather
-- than guessed at.
