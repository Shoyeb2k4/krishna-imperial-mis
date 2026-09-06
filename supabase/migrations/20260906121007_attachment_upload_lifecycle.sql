-- Phase 4 Slice 11 closure · the upload lifecycle after the bytes have landed
-- (full reasoning in the committed file of the same name)

create or replace function public.attachment_object_is_registered(p_name text)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select exists (select 1 from public.expense_attachments where storage_path = p_name)
      or exists (select 1 from public.revenue_attachments where storage_path = p_name);
$fn$;

comment on function public.attachment_object_is_registered(text) is
  'True when a metadata row names this object path, i.e. the object is canonical '
  'evidence. Answers over both tables regardless of the caller scope, because the '
  'question is whether the object is evidence at all, not whether this caller may see it.';

revoke all on function public.attachment_object_is_registered(text) from public, anon;
grant execute on function public.attachment_object_is_registered(text) to authenticated;

create or replace function public.may_attach_to_expense(p_expense_id uuid)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select public.may_read_expense_attachments(p_expense_id)
     and public.has_capability_anywhere('attachment.upload')
     and exists (select 1 from public.expenses e
                  where e.id = p_expense_id
                    and e.org_id = public.current_org_id()
                    and e.voided_at is null);
$fn$;

comment on function public.may_attach_to_expense(uuid) is
  'Whether this caller may put bytes in the bucket for this expense: the read predicate, '
  'plus attachment.upload, plus a parent that is not voided. Separate from the read '
  'predicate because a voided document keeps its evidence readable and accepts no more, '
  'and the two halves of an upload disagreeing about that is what stranded objects.';

create or replace function public.may_attach_to_revenue(p_entry_id uuid)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select public.may_read_revenue_attachments(p_entry_id)
     and public.has_capability_anywhere('attachment.upload')
     and exists (select 1 from public.revenue_entries e
                  where e.id = p_entry_id
                    and e.org_id = public.current_org_id()
                    and e.voided_at is null);
$fn$;

comment on function public.may_attach_to_revenue(uuid) is
  'The same for a sale. Mirrors revenue_attachment_register own refusals, so Storage and '
  'the registration boundary now agree about which parents accept evidence.';

revoke all on function public.may_attach_to_expense(uuid) from public, anon;
revoke all on function public.may_attach_to_revenue(uuid) from public, anon;
grant execute on function public.may_attach_to_expense(uuid) to authenticated;
grant execute on function public.may_attach_to_revenue(uuid) to authenticated;

drop policy if exists expense_attachments_write on storage.objects;
create policy expense_attachments_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'expense-attachments'
    and public.may_attach_to_expense(public.storage_expense_id(name))
    and not public.attachment_object_is_registered(name)
  );

drop policy if exists expense_attachments_update on storage.objects;
create policy expense_attachments_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'expense-attachments'
    and public.may_attach_to_expense(public.storage_expense_id(name))
    and not public.attachment_object_is_registered(name)
  );

drop policy if exists revenue_attachments_storage_write on storage.objects;
create policy revenue_attachments_storage_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'expense-attachments'
    and public.may_attach_to_revenue(public.storage_revenue_id(name))
    and not public.attachment_object_is_registered(name)
  );

drop policy if exists revenue_attachments_storage_update on storage.objects;
create policy revenue_attachments_storage_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'expense-attachments'
    and public.may_attach_to_revenue(public.storage_revenue_id(name))
    and not public.attachment_object_is_registered(name)
  );

drop policy if exists expense_attachments_discard on storage.objects;
create policy expense_attachments_discard on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'expense-attachments'
    and owner_id = auth.uid()::text
    and public.may_read_expense_attachments(public.storage_expense_id(name))
    and not public.attachment_object_is_registered(name)
  );

drop policy if exists revenue_attachments_discard on storage.objects;
create policy revenue_attachments_discard on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'expense-attachments'
    and owner_id = auth.uid()::text
    and public.may_read_revenue_attachments(public.storage_revenue_id(name))
    and not public.attachment_object_is_registered(name)
  );

comment on policy revenue_attachments_discard on storage.objects is
  'Lets the client that wrote an object take it back when registration terminally refused '
  'it. Cannot touch an object a metadata row names, which is what makes it a reclamation '
  'of stranded bytes rather than a way to remove evidence (spec section 23).';

do $inv$
declare v_bad text;
begin
  select string_agg(policyname, ', ') into v_bad
    from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd in ('INSERT', 'UPDATE')
     and policyname like '%attachment%'
     and coalesce(qual, '') || coalesce(with_check, '') like '%may_read_%_attachments%';
  if v_bad is not null then
    raise exception
      'an attachment write policy still decides on the READ predicate, so Storage will '
      'accept bytes the register RPC refuses: %', v_bad;
  end if;

  select string_agg(policyname, ', ') into v_bad
    from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd in ('INSERT', 'UPDATE', 'DELETE')
     and policyname like '%attachment%'
     and coalesce(qual, '') || coalesce(with_check, '')
         not like '%attachment_object_is_registered%';
  if v_bad is not null then
    raise exception
      'an attachment write or delete policy can touch an object that is already '
      'canonical evidence: %', v_bad;
  end if;

  select string_agg(policyname, ', ') into v_bad
    from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd = 'DELETE' and policyname like '%attachment%'
     and coalesce(qual, '') not like '%owner_id%';
  if v_bad is not null then
    raise exception 'an attachment delete policy is not restricted to its own uploader: %',
      v_bad;
  end if;
end $inv$;

do $inv$
declare v_bad text;
begin
  select string_agg(policyname, ', ') into v_bad
    from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd = 'SELECT' and policyname like '%attachment%'
     and coalesce(qual, '') like '%may_attach_to_%';
  if v_bad is not null then
    raise exception
      'an attachment READ policy now requires attach authority, so a voided document '
      'would lose the evidence for what was recorded (D-006): %', v_bad;
  end if;
end $inv$;

do $inv$
declare v_bad text;
begin
  select string_agg(p.proname, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('attachment_object_is_registered', 'may_attach_to_expense',
                       'may_attach_to_revenue')
     and (p.prosecdef is not true
          or not exists (select 1 from unnest(coalesce(p.proconfig, array[]::text[])) c
                          where c like 'search_path=%'));
  if v_bad is not null then
    raise exception 'a new predicate is not a search_path-pinned security definer: %', v_bad;
  end if;
end $inv$;