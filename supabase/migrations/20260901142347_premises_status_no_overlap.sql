-- A2 — premises status resolution must yield zero or exactly one, never several.
--
-- As shipped, the table carried only `effective_from` with a unique on
-- (org, unit, effective_from). That expresses "one status may START on a given date". It
-- does NOT express "at most one status APPLIES on a given date", and a probe confirmed
-- the difference: two open-ended rows starting 2026-04-01 and 2026-06-01 are both
-- applicable on 2026-08-01.
--
-- Resolving that by "latest effective_from wins" would be a ranking, which is precisely
-- what D-094 forbids for tax facts. A premises status is a tax fact.
--
-- Unlike a tax rule, this table has NO wildcard discriminators — a status is a plain
-- interval on one unit's timeline. So an exclusion constraint fully models it, and is
-- preferable to the trigger-plus-advisory-lock the rules needed (D-095): it is enforced by
-- the index at write time, which makes it inherently concurrency-safe with no
-- read-validate-write window for two sessions to slip through.

alter table public.business_unit_tax_statuses
  add column if not exists effective_to date,
  add column if not exists archived_at timestamptz;

comment on column public.business_unit_tax_statuses.effective_to is
  'Exclusive upper bound. Null means still in force. Half-open [from, to), so a status ending the day another begins is not an overlap — the boundary belongs to the successor.';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'business_unit_tax_statuses_period_ordered') then
    alter table public.business_unit_tax_statuses
      add constraint business_unit_tax_statuses_period_ordered
      check (effective_to is null or effective_to > effective_from);
  end if;
end $$;

-- The unique on effective_from is subsumed: two rows sharing a start date necessarily
-- overlap. Keeping both would be two constraints asserting one thing, and the weaker one
-- would eventually be mistaken for the guarantee.
alter table public.business_unit_tax_statuses
  drop constraint if exists business_unit_tax_statuses_one_per_date;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'business_unit_tax_statuses_no_overlap') then
    alter table public.business_unit_tax_statuses
      add constraint business_unit_tax_statuses_no_overlap
      exclude using gist (
        business_unit_id with =,
        daterange(effective_from, effective_to, '[)') with &&
      ) where (archived_at is null);
  end if;
end $$;

comment on constraint business_unit_tax_statuses_no_overlap
  on public.business_unit_tax_statuses is
  'At most one status applies to a unit on any date (A2). Partial on archived_at so archiving frees the period for a valid replacement, exactly as revenue_tax_rates once did.';

-- Prove it, in the same transaction that added it, rather than assuming.
do $$
declare v_org uuid; v_unit uuid; v_actor uuid; v_ok boolean;
begin
  select id into v_org from public.organizations limit 1;
  select p.id into v_actor from public.profiles p limit 1;
  select id into v_unit from public.business_units where code = 'CCR';

  -- Adjacent ranges are legal: [Apr, Jun) then [Jun, open).
  insert into public.business_unit_tax_statuses
    (org_id, business_unit_id, effective_from, effective_to, status_code, created_by)
    values (v_org, v_unit, '2026-04-01', '2026-06-01', 'PROBE_A', v_actor);
  insert into public.business_unit_tax_statuses
    (org_id, business_unit_id, effective_from, effective_to, status_code, created_by)
    values (v_org, v_unit, '2026-06-01', null, 'PROBE_B', v_actor);

  -- An overlapping one is not.
  v_ok := false;
  begin
    insert into public.business_unit_tax_statuses
      (org_id, business_unit_id, effective_from, effective_to, status_code, created_by)
      values (v_org, v_unit, '2026-05-01', '2026-07-01', 'PROBE_C', v_actor);
  exception when exclusion_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'A2: an overlapping premises status was accepted';
  end if;

  -- And exactly one applies on any date.
  if (select count(*) from public.business_unit_tax_statuses
       where business_unit_id = v_unit and archived_at is null
         and effective_from <= date '2026-08-01'
         and (effective_to is null or effective_to > date '2026-08-01')) <> 1 then
    raise exception 'A2: resolution did not yield exactly one status';
  end if;

  -- Leave nothing behind: no premises status is seeded (the baseline needs none).
  delete from public.business_unit_tax_statuses where status_code like 'PROBE_%';
end $$;

do $$
begin
  if (select count(*) from public.business_unit_tax_statuses) <> 0 then
    raise exception 'no premises status may be seeded';
  end if;
end $$;
