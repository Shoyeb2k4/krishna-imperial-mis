-- Phase 5 Slice 1 · a regression I introduced one migration ago, and the guard that
-- should have caught it (D-174).
--
-- `expense_view_own_means_own` rebuilt `expense_attachments_read` from
-- `20260829090300_expense_rls.sql`, which is the migration that first *created* that
-- policy — not `20260830130000_attachment_metadata_uses_definer_predicate.sql`, which is
-- the one that last *replaced* it. The older body inlines
--
--     exists (select 1 from public.expenses e where e.id = expense_id and ...)
--
-- and a policy expression is evaluated with the querying user's privileges, which for
-- every client role means no SELECT on `public.expenses` at all. So the table stopped
-- being readable by anybody, Owner included:
--
--     select count(*) from public.expense_attachments
--       -> 42501: permission denied for table expenses
--
-- Fail-closed rather than a leak, and still a defect: D-063's read authority became
-- unavailable to the users it exists to serve.
--
-- This is D-045 and D-109 for the third time, arriving by a new route: not a predicate
-- written against the wrong schema, but a correct predicate **restored from a superseded
-- version of itself**. A `create or replace` has to be built from what the object is now.

drop policy if exists expense_attachments_read on public.expense_attachments;
create policy expense_attachments_read on public.expense_attachments
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and public.may_read_expense_attachments(expense_id)
  );

comment on policy expense_attachments_read on public.expense_attachments is
  'Complete-document callers only (D-063), and since D-169 the author too where the '
  'caller holds only expense.view.own — both inherited from may_read_expense_attachments '
  'rather than restated. Calls the security-definer predicate the Storage policies use, '
  'because a policy subquery runs with the caller''s own privileges and so cannot read '
  'the financial tables it would need in order to decide.';

-- ── The guard ────────────────────────────────────────────────────────────────
-- No RLS policy on a financial relation may read a financial base table inline. Every
-- such question goes through a security-definer predicate, which is the rule D-045 and
-- D-109 each established and neither turned into a check. Stated generally, over the
-- catalogue, so it holds for policies nobody has written yet.
do $inv$
declare v_bad text;
begin
  select string_agg(format('%s on %s', pol.polname, c.relname), ', ') into v_bad
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('expenses', 'expense_allocations', 'expense_period_allocations',
                       'expense_attachments', 'revenue_entries', 'revenue_components',
                       'revenue_attachments')
     and (
       -- the policy expression names a financial base table directly
       coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') ~
         '(from|join)\s+public\.(expenses|expense_allocations|expense_period_allocations|revenue_entries|revenue_components)\M'
       or coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') ~
         '(from|join)\s+public\.(expenses|expense_allocations|expense_period_allocations|revenue_entries|revenue_components)\M'
     );
  if v_bad is not null then
    raise exception
      'a policy reads a financial base table inline; policy expressions run with the '
      'caller''s privileges and no client role may read those tables, so this refuses '
      'everybody rather than deciding anything (D-045, D-109, D-174): %', v_bad;
  end if;
end $inv$;

-- And the table is readable again by somebody who is entitled to it. Asserted by asking,
-- rather than by reading the policy back: the defect above was invisible to review and
-- obvious to a single count(*).
do $inv$
declare v_n bigint;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', (select p.id::text from public.profiles p
                                                join public.user_roles ur on ur.user_id = p.id
                                                join public.roles r on r.id = ur.role_id
                                               where r.code = 'owner'
                                                 and ur.revoked_at is null limit 1),
                                       'role', 'authenticated')::text,
                     true);
  select count(*) into v_n from public.expense_attachments;
  reset role;
  raise notice 'the Owner reads % expense attachment rows', v_n;
exception when others then
  reset role;
  raise exception 'expense_attachments is still unreadable by the Owner: %', sqlerrm;
end $inv$;