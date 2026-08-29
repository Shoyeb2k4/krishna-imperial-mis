-- ─────────────────────────────────────────────────────────────────────────────
-- 0032 · Usage semantics, and attachment storage
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.1 · Phase 3
--
-- Two things, both of them about not destroying evidence.
--
-- 1 · USAGE MEANS TWO DIFFERENT THINGS, AND CONFLATING THEM LOSES THE ONE THAT MATTERS.
--     `transaction_count` is HISTORICAL: how many accepted lines have ever referenced a
--     master. It never goes down. A voided expense still happened, and the D-038 rename
--     warning exists to tell an administrator that months of entries were recorded
--     against a category — which stays true after somebody voids one of them.
--     `active_count` is CURRENT: how many live, unvoided lines reference it now. That is
--     the figure a "can I stop using this?" question wants, and the one a void
--     decrements. The first version decremented the historical count on void, which would
--     have quietly erased the evidence the warning is built on.
--
-- 2 · AN ATTACHMENT IS THE WHOLE BILL. The shared electricity invoice says ₹58,000 on its
--     face. Handing it to a Crystal Canopy manager entitled to ₹25,000 gives away exactly
--     what the scoped projection withholds, in a form no policy can redact. So original
--     attachments are **complete-document-only**: a user who receives a scoped projection
--     does not receive the attachment. Not "receives it with the button hidden".
--
--     The object path is derived and predictable, and that is fine — path secrecy is not
--     authorisation. The bucket is private and every read is decided by the policy.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.master_usage_counters
  add column if not exists active_count bigint not null default 0;

comment on column public.master_usage_counters.transaction_count is
  'Historical: how many accepted lines have ever referenced this master. Never '
  'decremented — a voided expense still happened, and D-038 rename warnings rest on it.';
comment on column public.master_usage_counters.active_count is
  'Current: how many live, unvoided lines reference this master now. Decremented on void '
  'and when an edit drops a line.';

update public.master_usage_counters set active_count = transaction_count
 where active_count = 0 and transaction_count > 0;

-- The five-argument form and this one would both match a five-argument call, because the
-- sixth parameter has a default — so every existing caller becomes ambiguous the moment
-- this is added. The superseded signature goes.
drop function if exists app.record_master_usage(uuid, text, uuid, date, integer);

create or replace function app.record_master_usage(
  p_org_id        uuid,
  p_entity_type   text,
  p_entity_id     uuid,
  p_business_date date,
  p_delta         integer default 1,
  p_active_delta  integer default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  -- Absent, the active delta follows the historical one, which is what a create wants.
  -- A void passes (0, -1): the reference is no longer live, and it is still on the
  -- record.
  v_active integer := coalesce(p_active_delta, p_delta);
begin
  insert into public.master_usage_counters as c (
    entity_type, entity_id, org_id, transaction_count, active_count,
    earliest_business_date, latest_business_date, updated_at)
  values (p_entity_type, p_entity_id, p_org_id,
          greatest(p_delta, 0), greatest(v_active, 0),
          p_business_date, p_business_date, now())
  on conflict (entity_type, entity_id) do update
    set transaction_count      = greatest(c.transaction_count + p_delta, 0),
        active_count           = greatest(c.active_count + v_active, 0),
        earliest_business_date = least(coalesce(c.earliest_business_date, p_business_date),
                                       p_business_date),
        latest_business_date   = greatest(coalesce(c.latest_business_date, p_business_date),
                                          p_business_date),
        updated_at             = now();
end;
$$;

revoke all on function app.record_master_usage(uuid, text, uuid, date, integer, integer)
  from public, anon, authenticated;

do $$
declare v_count integer;
begin
  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'record_master_usage';
  if v_count <> 1 then
    raise exception 'record_master_usage must have exactly one signature, found %',
      v_count;
  end if;
end $$;

-- `expense_void` and `expense_update` pass (0, -1) where a naive implementation would
-- pass -1. Their full definitions live in 0029, which this migration's applied
-- counterpart restated; the semantics are stated here because this is where the two
-- meanings of "usage" are defined.

-- ── Attachment storage ───────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'expense-attachments',
  'expense-attachments',
  false,
  10485760,
  array['image/jpeg','image/png','image/heic','image/heif','image/webp','application/pdf'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- The expense an object path belongs to: `org/{org}/expenses/{expense}/{attachment}.{ext}`
create or replace function public.storage_expense_id(p_name text)
returns uuid language sql immutable set search_path = '' as $$
  select case
    when p_name ~ '^org/[0-9a-f-]{36}/expenses/[0-9a-f-]{36}/' then
      (string_to_array(p_name, '/'))[4]::uuid
    else null end;
$$;

revoke all on function public.storage_expense_id(text) from public, anon;
grant execute on function public.storage_expense_id(text) to authenticated;

-- Deliberately the same predicate the header projection uses for `is_complete`: one
-- definition, so an attachment can never be readable by somebody the document itself is
-- only partially visible to.
create or replace function public.may_read_expense_attachments(p_expense_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_expense_id is not null
     and public.has_capability_anywhere('attachment.view')
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
$$;

comment on function public.may_read_expense_attachments(uuid) is
  'True only for a caller entitled to every line of the expense. An invoice image states '
  'the full total on its face, so a scoped user is not given it.';

revoke all on function public.may_read_expense_attachments(uuid) from public, anon;
grant execute on function public.may_read_expense_attachments(uuid) to authenticated;

drop policy if exists expense_attachments_read on storage.objects;
create policy expense_attachments_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'expense-attachments'
    and public.may_read_expense_attachments(public.storage_expense_id(name))
  );

drop policy if exists expense_attachments_write on storage.objects;
create policy expense_attachments_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'expense-attachments'
    and public.has_capability_anywhere('attachment.upload')
    and public.may_read_expense_attachments(public.storage_expense_id(name))
  );

drop policy if exists expense_attachments_update on storage.objects;
create policy expense_attachments_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'expense-attachments'
    and public.has_capability_anywhere('attachment.upload')
    and public.may_read_expense_attachments(public.storage_expense_id(name))
  );

-- Nobody deletes an attachment through the object API. Evidence is removed, if ever,
-- through an audited application action — never by a client reaching the bucket.
drop policy if exists expense_attachments_delete on storage.objects;

do $$
begin
  if exists (select 1 from storage.buckets
              where id = 'expense-attachments' and public) then
    raise exception 'the attachment bucket must not be public';
  end if;
end $$;
