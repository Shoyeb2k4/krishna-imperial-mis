-- ─────────────────────────────────────────────────────────────────────────────
-- 0028 · Row-level security for expenses, and the scoped projection
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.1 · Phase 3
--
-- **Line-level RLS alone is not sufficient, and this migration exists because of that.**
--
--     Invoice total          ₹58,000
--       Crystal Canopy       ₹25,000
--       Hotel Krishna        ₹33,000
--
-- Filter `expense_allocations` by scope and a Crystal Canopy manager sees their ₹25,000.
-- Then hand them the document header and they read ₹58,000 — and ₹58,000 − ₹25,000 is
-- Hotel Krishna's ₹33,000, exactly. The header total is a covert channel for every other
-- unit's share, and so is any unrestricted aggregate over the same expense.
--
-- So the rule is: **no client role holds SELECT on `public.expenses` at all.** The header
-- is reachable only through `public.expense_document`, a security-barrier view that runs
-- with the owner's rights, carries the scope predicate itself, returns the caller's own
-- visible subtotal, and returns **null** where the true total would be.
--
-- A `security_invoker` view would have been the obvious choice and is the wrong one here:
-- it would need the caller to hold SELECT on the base table, which is precisely the grant
-- that makes the covert channel reachable. The view therefore owns its scoping outright,
-- and the predicate below is the whole of it — there is no policy underneath doing half
-- the work.
--
-- Nothing here relies on Flutter hiding a field. A modified client asking PostgREST
-- directly gets the same projection, because the projection is what the policy allows it
-- to reach.
--
-- Five surfaces, all closed the same way: the document, the lines, the period
-- contributions, the attachments, and any aggregate built on them.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.expenses                   enable row level security;
alter table public.expense_allocations        enable row level security;
alter table public.expense_period_allocations enable row level security;
alter table public.expense_attachments        enable row level security;

-- No client writes a financial table directly. Every mutation goes through the
-- SECURITY DEFINER RPCs in the next migration, which re-check capability, scope,
-- hierarchy, archive state, period lock, edit window and row version in one transaction.
-- `anon` holds nothing at all on a financial table. A default grant is easy to inherit
-- and impossible to notice, so every one is revoked explicitly and asserted at the end.
revoke all on public.expenses                   from anon, public;
revoke all on public.expense_allocations        from anon, public;
revoke all on public.expense_period_allocations from anon, public;
revoke all on public.expense_attachments        from anon, public;
revoke all on public.document_number_counters   from anon, public, authenticated;

revoke insert, update, delete on public.expenses                   from authenticated;
revoke insert, update, delete on public.expense_allocations        from authenticated;
revoke insert, update, delete on public.expense_period_allocations from authenticated;
revoke insert, update, delete on public.expense_attachments        from authenticated;

-- The header is not readable directly, by anybody, ever. `expense_document` is the read
-- path, and the reason it exists.
revoke select on public.expenses from authenticated;

grant select on public.expense_allocations        to authenticated;
grant select on public.expense_period_allocations to authenticated;
grant select on public.expense_attachments        to authenticated;

-- ── Does this caller hold an unscoped grant? ─────────────────────────────────
-- "Every unit" is an absence of restriction, not a list, and by D-025 only the Owner
-- role may hold it. Published because policies need it and cannot reach `app`.
create or replace function public.has_unscoped_capability(p_capability text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.user_roles ur
      join public.role_capabilities rc on rc.role_id = ur.role_id
     where ur.user_id = (select auth.uid())
       and ur.revoked_at is null
       and ur.business_unit_id is null
       and rc.capability_code = p_capability
  );
$$;

comment on function public.has_unscoped_capability(text) is
  'True only for an organisation-wide grant. `has_capability_anywhere` answers "anywhere '
  'at all", which is a different and weaker question.';

revoke all on function public.has_unscoped_capability(text) from public, anon;
grant execute on function public.has_unscoped_capability(text) to authenticated;

-- ── Which units may this caller see? ─────────────────────────────────────────
-- Published, because a policy is evaluated with the querying user's privileges and
-- `authenticated` has no USAGE on `app` — the mistake that made every Phase 2 table
-- return 403 until D-045 caught it.
create or replace function public.expense_visible_units()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select bu.id
    from public.business_units bu
   where bu.org_id = public.current_org_id()
     and (public.has_unscoped_capability('expense.view.all')
          or public.has_capability('expense.view.all', bu.id)
          or public.has_capability('expense.view.own', bu.id));
$$;

comment on function public.expense_visible_units() is
  'The business units this caller may see expense data for. One definition, used by every '
  'expense policy, so the five surfaces cannot drift apart.';

-- Whether the caller sees the company rather than a property. Only an unscoped grant
-- does, which by D-025 only the Owner role may hold.
create or replace function public.expense_sees_whole_org()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_unscoped_capability('expense.view.all');
$$;

-- ── Lines, contributions, attachments ────────────────────────────────────────
drop policy if exists expense_allocations_read on public.expense_allocations;
create policy expense_allocations_read on public.expense_allocations
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and business_unit_id in (select public.expense_visible_units())
  );

drop policy if exists expense_period_allocations_read on public.expense_period_allocations;
create policy expense_period_allocations_read on public.expense_period_allocations
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and business_unit_id in (select public.expense_visible_units())
  );

-- An attachment belongs to the document, not to a line, so it is reachable only by
-- somebody entitled to the document as a whole. A share of a shared bill does not carry
-- a right to the other property's invoice image.
drop policy if exists expense_attachments_read on public.expense_attachments;
create policy expense_attachments_read on public.expense_attachments
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and public.has_capability_anywhere('attachment.view')
    and exists (
      select 1 from public.expenses e
       where e.id = expense_id
         and not exists (
           select 1 from public.expense_allocations a
            where a.expense_id = e.id
              and a.business_unit_id not in (select public.expense_visible_units())))
  );

-- ── The document ─────────────────────────────────────────────────────────────
-- A policy is still declared, so that RLS is on and any future grant fails closed rather
-- than opening the table up. It is not what protects the total — the absent grant is.
drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and exists (
      select 1 from public.expense_allocations a
       where a.expense_id = id
         and a.business_unit_id in (select public.expense_visible_units()))
  );

-- ── The projection a client actually reads ───────────────────────────────────
-- `security_barrier` so the planner cannot push a user-supplied predicate inside the view
-- and infer a withheld total by probing it. Owner rights, and the scope predicate is
-- stated here in full.
create or replace view public.expense_document
with (security_barrier = true) as
select
  e.id,
  e.org_id,
  e.txn_number,
  e.financial_year,
  e.business_date,
  e.business_date_source,
  e.accounting_period_start,
  e.accounting_period_end,
  e.vendor_id,
  e.payment_status,
  e.payment_date,
  e.payment_method_id,
  e.reference_number,
  e.notes,
  e.tax_amount_minor,
  e.created_by,
  e.captured_at,
  e.voided_at,
  e.voided_by,
  e.void_reason,
  e.created_at,
  e.updated_at,
  e.row_version,
  e.change_seq,

  -- What this caller may legitimately add up: the lines they can see.
  (select coalesce(sum(a.amount_minor), 0)
     from public.expense_allocations a
    where a.expense_id = e.id
      and a.business_unit_id in (select public.expense_visible_units())
  ) as visible_amount_minor,

  -- Whether every line is visible to them.
  (not exists (
     select 1 from public.expense_allocations a
      where a.expense_id = e.id
        and a.business_unit_id not in (select public.expense_visible_units()))
  ) as is_complete,

  -- The true total, and **only** when they may see all of it. Withheld deliberately: on a
  -- two-property bill the total plus one share is the other share.
  (case when not exists (
          select 1 from public.expense_allocations a
           where a.expense_id = e.id
             and a.business_unit_id not in (select public.expense_visible_units()))
        then e.total_amount_minor
        else null end
  ) as total_amount_minor
from public.expenses e
where e.org_id = public.current_org_id()
  and exists (
    select 1 from public.expense_allocations a
     where a.expense_id = e.id
       and a.business_unit_id in (select public.expense_visible_units()));

comment on view public.expense_document is
  'The only expense header a client reads. A unit-scoped user gets their own visible '
  'subtotal and a null total, because total minus own share is the other property''s '
  'share. Never grant SELECT on public.expenses to a client role.';

revoke all on public.expense_document from anon, public;
grant select on public.expense_document to authenticated;

revoke all on function public.expense_visible_units() from public, anon;
revoke all on function public.expense_sees_whole_org() from public, anon;
grant execute on function public.expense_visible_units() to authenticated;
grant execute on function public.expense_sees_whole_org() to authenticated;

-- ── The reporting projection ─────────────────────────────────────────────────
-- Period contributions are the only reporting source (D-060). Exposing them as a named
-- view means a report cannot accidentally aggregate line amounts *and* contributions and
-- count the same money twice: there is one thing to sum, and it is this.
create or replace view public.expense_period_contributions
with (security_barrier = true) as
select
  p.id,
  p.org_id,
  p.expense_id,
  p.allocation_id,
  p.business_unit_id,
  a.department_id,
  a.section_id,
  a.category_id,
  p.accounting_period_start,
  p.accounting_period_end,
  p.pnl_date,
  p.pnl_period_key,
  p.amount_minor,
  p.is_derived,
  e.business_date,
  e.payment_status,
  e.payment_date,
  e.vendor_id,
  e.voided_at
from public.expense_period_allocations p
join public.expense_allocations a on a.id = p.allocation_id
join public.expenses e on e.id = p.expense_id
where p.org_id = public.current_org_id()
  and p.business_unit_id in (select public.expense_visible_units());

comment on view public.expense_period_contributions is
  'The canonical source for profitability. One row per allocation line per accounting '
  'period, already scoped by the underlying policies. Voided documents carry voided_at '
  'and are excluded by every aggregate; they stay visible to audit.';

revoke all on public.expense_period_contributions from anon, public;
grant select on public.expense_period_contributions to authenticated;

-- ── Prove the covert channel is actually closed ──────────────────────────────
-- Asserted here rather than left to review: the raw tables must not be readable by a
-- client role, or the view's care would be decoration.
do $$
begin
  -- The covert channel, closed by the absence of a grant rather than by care in a query.
  if has_table_privilege('authenticated', 'public.expenses', 'SELECT') then
    raise exception
      'authenticated can read public.expenses directly; the header total on a shared '
      'bill would then be reachable, and total minus own share is the other property''s '
      'share. The read path is public.expense_document.';
  end if;

  if has_table_privilege('authenticated', 'public.document_number_counters', 'SELECT')
  then
    raise exception 'document_number_counters must not be readable by a client';
  end if;

  if has_table_privilege('anon', 'public.expenses', 'SELECT')
     or has_table_privilege('anon', 'public.expense_allocations', 'SELECT')
     or has_table_privilege('anon', 'public.expense_period_allocations', 'SELECT')
     or has_table_privilege('anon', 'public.expense_attachments', 'SELECT')
     or has_table_privilege('anon', 'public.expense_document', 'SELECT')
     or has_table_privilege('anon', 'public.expense_period_contributions', 'SELECT') then
    raise exception 'anon can read financial data';
  end if;
end $$;
