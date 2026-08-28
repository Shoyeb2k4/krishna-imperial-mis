-- ─────────────────────────────────────────────────────────────────────────────
-- 0025 · The cross-unit allocation capability (D-061)
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.1 · Phase 3
--
-- Charging one expense to more than one business unit needs its own permission, over and
-- above holding scope on both. Scope says "you work at this property". A cross-unit split
-- decides how a shared cost is apportioned *between* two properties, which moves both
-- of their operating profits — it is an act of finance, and somebody who happens to cover
-- both properties operationally should not acquire it as a side effect.
--
-- Granted to Accountant and to the Owner role. Deliberately not to Manager or Data Entry,
-- matching `expense.allocate_periods`, which draws the same line for the same reason.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.capabilities (code, category, description) values
  ('expense.allocate_cross_unit', 'expense', 'Charge one expense to more than one business unit')
on conflict (code) do nothing;

insert into public.role_capabilities (role_id, capability_code)
select r.id, 'expense.allocate_cross_unit'
  from public.roles r
 where r.code in ('owner', 'accountant')
on conflict do nothing;

-- The Dart bundles and the Postgres bundles must agree exactly; a host test asserts it
-- in both directions. Prove here that this migration left them agreeing.
do $$
declare v_missing text;
begin
  select string_agg(r.code, ', ')
    into v_missing
    from public.roles r
   where r.code in ('owner', 'accountant')
     and not exists (
       select 1 from public.role_capabilities rc
        where rc.role_id = r.id
          and rc.capability_code = 'expense.allocate_cross_unit');
  if v_missing is not null then
    raise exception 'expense.allocate_cross_unit missing from: %', v_missing;
  end if;

  if exists (
    select 1 from public.role_capabilities rc
      join public.roles r on r.id = rc.role_id
     where rc.capability_code = 'expense.allocate_cross_unit'
       and r.code in ('manager', 'data_entry')) then
    raise exception
      'expense.allocate_cross_unit must not be in an operational bundle';
  end if;
end $$;
