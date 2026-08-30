-- ─────────────────────────────────────────────────────────────────────────────
-- 0036 · The attachment metadata policy asks a question it can actually answer
--
-- Found by the D-073 attachment acceptance, and it is a real leak rather than an
-- inconsistency: Storage correctly refused a scoped manager the *object*, and the
-- metadata table handed them the row.
--
-- ## Why the old predicate could not work
--
-- `expense_attachments_read` was written as:
--
--     not exists (select 1 from public.expense_allocations a
--                  where a.expense_id = ...
--                    and a.business_unit_id not in (select public.expense_visible_units()))
--
-- which reads as "no line of this document is outside my scope". The intent is exactly
-- right and the implementation cannot express it, because **a policy subquery is
-- evaluated with the querying user's privileges** — the same fact that broke every table
-- in D-045. `expense_allocations` has its own RLS restricting rows to
-- `expense_visible_units()`, so the lines this predicate is hunting for are precisely
-- the lines the caller cannot see. The `not exists` is therefore *vacuously true* for
-- exactly the users it exists to exclude: a Crystal Canopy manager looking at a shared
-- bill sees no Hotel Krishna line, concludes there is none, and is allowed through.
--
-- The Storage policies were unaffected because they call
-- `public.may_read_expense_attachments`, which is `security definer` and so reads the
-- allocations as the owner. That is why the acceptance saw Storage refuse a download and
-- the table return the row for the same document, in the same session.
--
-- ## The fix is the one the original comment already claimed
--
-- 0031 says of `may_read_expense_attachments`: "Deliberately the same predicate the
-- header projection uses for `is_complete`: one definition, so an attachment can never be
-- readable by somebody the document itself is only partly visible to." There were two
-- definitions. Now there is one, and the table policy calls it.
-- ─────────────────────────────────────────────────────────────────────────────

drop policy if exists expense_attachments_read on public.expense_attachments;
create policy expense_attachments_read on public.expense_attachments
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and public.may_read_expense_attachments(expense_id)
  );

comment on policy expense_attachments_read on public.expense_attachments is
  'Complete-document callers only (D-063). Calls the same security-definer predicate the '
  'Storage policies use, because a policy subquery runs with the caller''s own '
  'privileges and so cannot see the lines it would need to exclude them by.';

-- Prove it, rather than assert it in a comment.
--
-- A predicate that is vacuously true looks identical to one that is working, which is
-- how this survived review: both return "allowed" for the Owner, and the difference only
-- shows for a scoped caller on a shared document. So the check is that the policy
-- delegates to the definer function at all — the behavioural proof is the acceptance
-- phase, which reads the table as a scoped manager and expects nothing back.
do $$
declare
  v_qual text;
begin
  select qual into v_qual
    from pg_policies
   where schemaname = 'public'
     and tablename = 'expense_attachments'
     and policyname = 'expense_attachments_read';

  if v_qual is null then
    raise exception 'expense_attachments_read is missing';
  end if;

  if v_qual not like '%may_read_expense_attachments%' then
    raise exception
      'the attachment metadata policy no longer uses the shared predicate: %', v_qual;
  end if;

  if v_qual like '%expense_allocations%' then
    raise exception
      'the attachment metadata policy reads expense_allocations directly again — that '
      'subquery runs with the caller''s privileges and cannot see the rows it needs: %',
      v_qual;
  end if;
end;
$$;
