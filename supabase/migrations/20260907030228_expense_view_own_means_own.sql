-- Phase 5 Slice 1 · E1 — `expense.view.own` means the expenses that user created (D-169).
--
-- The capability catalogue describes `expense.view.own` as "View expenses this user
-- created". `expense_visible_units()` returns the units where the caller holds
-- `expense.view.all` OR `expense.view.own`, and no read path anywhere applied a
-- `created_by` predicate. Read as the development Data Entry identity, which holds
-- `expense.view.own` on Crystal Canopy and nothing else:
--
--     expense_document               787 rows visible,  724 created by other people
--     expense_period_contributions   865 rows visible,  802 created by other people
--     expense_allocations            787 rows visible,  724 created by other people
--
-- including every expense the Owner and both managers had recorded.
--
-- ── Why the unit set could not simply be edited ──────────────────────────────
--
-- Ownership is a property of a *document*. `expense_visible_units()` answers a question
-- about *units*, and a set of unit ids cannot express "mine". So the two questions are
-- separated rather than conflated:
--
--     expense_visible_units()      unchanged — whose LINES may I see, per unit
--     public.may_read_expense(id)  new      — may I see this DOCUMENT at all
--
-- and the document predicate is AND-ed into every read path. It has to be every path:
-- `expense_allocations_read` is line-level, so leaving it alone would go on handing a
-- `view.own` holder another person's allocation rows through the child table.
--
-- ── It can only narrow ───────────────────────────────────────────────────────
--
-- For a pure `view.all` holder the own-branch is unreachable (their `view.own` unit set is
-- empty), so the predicate reduces to exactly the old one. For a holder of both, it is the
-- old predicate with the own-only units additionally requiring authorship. No read that is
-- permitted today becomes permitted that was not, and the Owner's unscoped grant is
-- untouched because `has_capability` is already true for every unit under it (D-025).

-- ── The document predicate ───────────────────────────────────────────────────
-- `public`, not `app`, and granted to `authenticated`: a policy expression is evaluated
-- with the querying user's privileges, and a predicate they cannot execute fails every
-- read rather than refusing one (D-045, D-109).
create or replace function public.may_read_expense(p_expense_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select p_expense_id is not null and exists (
    select 1
      from public.expenses e
     where e.id = p_expense_id
       and e.org_id = public.current_org_id()
       and (
         -- Somebody entitled to the property's expenses, whoever recorded them.
         exists (select 1 from public.expense_allocations a
                  where a.expense_id = e.id
                    and public.has_capability('expense.view.all', a.business_unit_id))
         -- Or the person who recorded it, in a property where they may see their own.
         or (e.created_by = (select auth.uid())
             and exists (select 1 from public.expense_allocations a
                          where a.expense_id = e.id
                            and public.has_capability('expense.view.own',
                                                      a.business_unit_id)))
       )
  );
$fn$;

comment on function public.may_read_expense(uuid) is
  'Whether this caller may see this expense document at all. One definition, AND-ed into '
  'every expense read path, so the line-level policies cannot hand out a document the '
  'document-level rules refuse. expense.view.all is any author; expense.view.own is this '
  'author only, which is what the capability has always said and did not do (D-169).';

revoke all on function public.may_read_expense(uuid) from public, anon;
grant execute on function public.may_read_expense(uuid) to authenticated;

-- ── The child tables ─────────────────────────────────────────────────────────
-- Line scope is unchanged and still decides WHICH lines; the document predicate decides
-- whether the caller reaches the document those lines belong to.
drop policy if exists expense_allocations_read on public.expense_allocations;
create policy expense_allocations_read on public.expense_allocations
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and business_unit_id in (select public.expense_visible_units())
    and public.may_read_expense(expense_id)
  );

drop policy if exists expense_period_allocations_read on public.expense_period_allocations;
create policy expense_period_allocations_read on public.expense_period_allocations
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and business_unit_id in (select public.expense_visible_units())
    and public.may_read_expense(expense_id)
  );

drop policy if exists expense_attachments_read on public.expense_attachments;
create policy expense_attachments_read on public.expense_attachments
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and public.has_capability_anywhere('attachment.view')
    and public.may_read_expense(expense_id)
    and exists (
      select 1 from public.expenses e
       where e.id = expense_id
         and not exists (
           select 1 from public.expense_allocations a
            where a.expense_id = e.id
              and a.business_unit_id not in (select public.expense_visible_units())))
  );

-- ── The document ─────────────────────────────────────────────────────────────
drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and public.may_read_expense(id)
  );

-- ── The two projections a client actually reads ──────────────────────────────
-- Recreated in full rather than patched, because a view is replaced whole and a reader
-- comparing this against the original must be able to see every line that decides access.
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

  (select coalesce(sum(a.amount_minor), 0)
     from public.expense_allocations a
    where a.expense_id = e.id
      and a.business_unit_id in (select public.expense_visible_units())
  ) as visible_amount_minor,

  (not exists (
     select 1 from public.expense_allocations a
      where a.expense_id = e.id
        and a.business_unit_id not in (select public.expense_visible_units()))
  ) as is_complete,

  (case when not exists (
          select 1 from public.expense_allocations a
           where a.expense_id = e.id
             and a.business_unit_id not in (select public.expense_visible_units()))
        then e.total_amount_minor
        else null end
  ) as total_amount_minor
from public.expenses e
where e.org_id = public.current_org_id()
  and public.may_read_expense(e.id);

comment on view public.expense_document is
  'The only expense header a client reads. A unit-scoped user gets their own visible '
  'subtotal and a null total, because total minus own share is the other property''s '
  'share. Since D-169 the row is also gated on may_read_expense, so a expense.view.own '
  'holder sees the documents they recorded and not their colleagues''. Never grant SELECT '
  'on public.expenses to a client role.';

revoke all on public.expense_document from anon, public;
grant select on public.expense_document to authenticated;

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
  and p.business_unit_id in (select public.expense_visible_units())
  and public.may_read_expense(p.expense_id);

comment on view public.expense_period_contributions is
  'The canonical source for profitability. One row per allocation line per accounting '
  'period, already scoped by the underlying policies and, since D-169, by document '
  'authorship where the caller holds only expense.view.own. Voided documents carry '
  'voided_at and are excluded by every aggregate; they stay visible to audit.';

revoke all on public.expense_period_contributions from anon, public;
grant select on public.expense_period_contributions to authenticated;

-- ── Attachments ──────────────────────────────────────────────────────────────
-- may_attach_to_expense is built on this predicate, so the three Storage policies inherit
-- the correction without being restated: a view.own holder may put bytes only against a
-- document they recorded.
create or replace function public.may_read_expense_attachments(p_expense_id uuid)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select p_expense_id is not null
     and public.has_capability_anywhere('attachment.view')
     and public.may_read_expense(p_expense_id)
     and exists (
       select 1 from public.expenses e
        where e.id = p_expense_id
          and e.org_id = public.current_org_id())
     and exists (
       select 1 from public.expense_allocations a
        where a.expense_id = p_expense_id
          and a.business_unit_id in (select public.expense_visible_units()))
     and not exists (
       select 1 from public.expense_allocations a
        where a.expense_id = p_expense_id
          and a.business_unit_id not in (select public.expense_visible_units()));
$fn$;

comment on function public.may_read_expense_attachments(uuid) is
  'True only for a caller entitled to the document and to every line of it. An invoice '
  'image states the full total on its face, so a scoped user is not given it — and since '
  'D-169 neither is somebody who did not record it and holds only expense.view.own.';

revoke all on function public.may_read_expense_attachments(uuid) from public, anon;
grant execute on function public.may_read_expense_attachments(uuid) to authenticated;

-- ── Invariants ───────────────────────────────────────────────────────────────

-- Every expense read path consults the document predicate. Enumerated by searching the
-- catalogue rather than by listing what I remember touching, because the next read path
-- to be added is exactly the one a remembered list would miss (D-145).
do $inv$
declare v_missing text;
begin
  select string_agg(what, ', ') into v_missing from (
    select 'policy ' || polname as what
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in ('expenses', 'expense_allocations',
                         'expense_period_allocations', 'expense_attachments')
       and pol.polcmd = 'r'
       and pg_get_expr(pol.polqual, pol.polrelid) not like '%may_read_expense(%'
    union all
    select 'view ' || c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in ('expense_document', 'expense_period_contributions')
       and pg_get_viewdef(c.oid, true) not like '%may_read_expense(%'
    union all
    select 'function ' || p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'may_read_expense_attachments'
       and pg_get_functiondef(p.oid) not like '%may_read_expense(%'
  ) f;
  if v_missing is not null then
    raise exception
      'an expense read path does not consult may_read_expense, so expense.view.own can '
      'still reach another author''s document through it: %', v_missing;
  end if;
end $inv$;

-- The predicate actually distinguishes the two capabilities and actually tests authorship.
-- A version that named neither would satisfy the assertion above and fix nothing.
do $inv$
declare v_def text := pg_get_functiondef('public.may_read_expense(uuid)'::regprocedure);
begin
  if v_def not like '%expense.view.all%' then
    raise exception 'may_read_expense does not name expense.view.all';
  end if;
  if v_def not like '%expense.view.own%' then
    raise exception 'may_read_expense does not name expense.view.own';
  end if;
  if v_def not like '%created_by%' then
    raise exception
      'may_read_expense does not test authorship, which is the whole of D-169';
  end if;
end $inv$;

-- The capabilities it names are held by somebody. D-116 shipped three rules requiring a
-- capability no role had, and they refused everybody silently.
do $inv$
declare v_missing text;
begin
  select string_agg(c, ', ') into v_missing
    from unnest(array['expense.view.all', 'expense.view.own']) as c
   where not exists (select 1 from public.role_capabilities rc
                      where rc.capability_code = c);
  if v_missing is not null then
    raise exception 'may_read_expense requires a capability no role holds: %', v_missing;
  end if;
end $inv$;

-- The base tables stay unreadable and the projections stay readable. A migration that
-- closed the boundary by breaking the application would otherwise pass every check above.
do $inv$
begin
  if has_table_privilege('authenticated', 'public.expenses', 'SELECT') then
    raise exception 'authenticated can read public.expenses directly';
  end if;
  if not has_table_privilege('authenticated', 'public.expense_document', 'SELECT')
     or not has_table_privilege('authenticated', 'public.expense_period_contributions',
                                'SELECT') then
    raise exception 'a client can no longer read an expense projection';
  end if;
  if has_table_privilege('anon', 'public.expense_document', 'SELECT')
     or has_table_privilege('anon', 'public.expense_period_contributions', 'SELECT') then
    raise exception 'anon can read financial data';
  end if;
end $inv$;