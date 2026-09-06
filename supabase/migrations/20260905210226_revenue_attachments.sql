-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 4 Slice 11 · Supporting evidence for a revenue entry
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.2 · Phase 4
--
-- Revenue attachments are the Phase 3 architecture (D-073, D-073a) applied to a second
-- document, not a second architecture. Same private bucket, same deterministic path
-- shape, same "two writes and neither alone is enough" rule, same idempotency on the
-- client-generated attachment id, same refusal of a voided parent. What differs is the
-- authority the parent carries, and that difference is the reason this file exists rather
-- than a discriminator column on `expense_attachments`.
--
-- ## The parent's authority is the attachment's authority, and revenue's is simpler
--
-- An expense attachment is **complete-document-only** (D-063): a shared invoice states
-- ₹58,000 on its face, so a manager entitled to ₹25,000 of it does not get the image, in
-- a form no policy could redact. That rule exists because an expense can be partly
-- visible.
--
-- **A revenue entry cannot be.** It names exactly one business unit and one revenue
-- category on its header (spec §8), there is no allocation model and no scoped
-- projection — `revenue_tables.sql` says so at length and declines to reproduce the
-- expense visibility columns for exactly this reason. So the predicate here is the one
-- the revenue projection already uses: this organisation, and `revenue.view` for the
-- entry's own business unit. Copying `may_read_expense_attachments`' allocation
-- arithmetic would be cargo cult — there are no lines to be outside anybody's scope.
--
-- ## One bucket, two prefixes, two predicates
--
-- `expense-attachments` holds both kinds. A second bucket would duplicate the size limit,
-- the MIME list and four policies, all then kept in step by hand — and the id is where
-- bytes physically live, so renaming it would strand every bill already uploaded. Objects
-- under `org/{org}/expenses/…` are decided by the expense predicate and objects under
-- `org/{org}/revenue/…` by this one; neither prefix is reachable through the other's rule.
--
-- ## What is deliberately NOT here
--
-- **No removal.** V1 ships no destructive attachment removal for expenses either
-- (D-072a), and `expense_attachments.removed_at` has no writer anywhere in the product.
-- Building one for revenue because the expense schema contains the concept would be
-- expanding V1 scope on the strength of a column name. `revenue_attachments` therefore
-- carries no removal columns at all — a constraint with no writer is the shape D-145 had
-- to reason about, and the honest answer is not to create the second one.
--
-- **No download RPC and no signed-URL issuer.** Phase 3 built none: the expense pipeline
-- uploads and registers, and reading an object back is Storage's own authenticated
-- download under the read policy. Revenue gets the same and nothing more.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── The metadata table ───────────────────────────────────────────────────────
--
-- Column for column the expense table, minus the removal trio and with the parent pointer
-- changed. Nothing here is a financial figure: an attachment supports a document and is
-- never a source of truth about one, so there is no amount, no tax and no contribution.
create table if not exists public.revenue_attachments (
  id               uuid primary key,
  org_id           uuid   not null,
  revenue_entry_id uuid   not null
                     references public.revenue_entries (id) on delete restrict,

  file_name        text   not null,
  content_type     text   not null,
  byte_size        bigint not null check (byte_size > 0),

  -- SHA-256 of the bytes. The upload is confirmed only when the server's copy hashes to
  -- the same value; "the request returned 200" is a weaker claim.
  content_hash     text   not null,
  storage_path     text   not null,

  uploaded_by      uuid   not null references public.profiles (id),
  uploaded_at      timestamptz not null default now(),

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  row_version      integer     not null default 1,
  change_seq       bigint      not null default nextval('app.global_change_seq'),

  constraint revenue_attachments_path_unique unique (storage_path)
);

comment on table public.revenue_attachments is
  'Supporting evidence for a revenue entry — a till report, a banquet billing document, a '
  'photograph. Never a financial source of truth: no amount, tax or reporting '
  'contribution is derived from it, and adding or losing one changes no figure.';

create index if not exists ix_revenue_attachments_entry
  on public.revenue_attachments (revenue_entry_id);
create index if not exists ix_revenue_attachments_change_seq
  on public.revenue_attachments (change_seq);

alter table public.revenue_attachments enable row level security;
alter table public.revenue_attachments force row level security;

-- ── The read predicate, defined once and used by three policies ──────────────
--
-- `security definer` for the same reason `may_read_expense_attachments` is: a policy
-- subquery runs with the **caller's** privileges, and `revenue_entries` has its own RLS,
-- so a predicate reading it directly would be answering with rows the caller can already
-- see rather than with the truth. That is D-045, and D-110 §1 is the version of it that
-- reached a shipped policy.
create or replace function public.may_read_revenue_attachments(p_entry_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_entry_id is not null
     and public.has_capability_anywhere('attachment.view')
     and exists (
       select 1 from public.revenue_entries e
        where e.id = p_entry_id
          and e.org_id = public.current_org_id()
          and public.has_capability('revenue.view', e.business_unit_id));
$$;

comment on function public.may_read_revenue_attachments(uuid) is
  'True for a caller who may view the parent revenue entry and holds attachment.view. A '
  'revenue entry names one business unit and is never partly visible, so unlike the '
  'expense predicate there are no allocation lines to check.';

revoke all on function public.may_read_revenue_attachments(uuid) from public, anon;
grant execute on function public.may_read_revenue_attachments(uuid) to authenticated;

-- The entry an object path belongs to: `org/{org}/revenue/{entry}/{attachment}.{ext}`
create or replace function public.storage_revenue_id(p_name text)
returns uuid language sql immutable set search_path = '' as $$
  select case
    when p_name ~ '^org/[0-9a-f-]{36}/revenue/[0-9a-f-]{36}/' then
      (string_to_array(p_name, '/'))[4]::uuid
    else null end;
$$;

revoke all on function public.storage_revenue_id(text) from public, anon;
grant execute on function public.storage_revenue_id(text) to authenticated;

drop policy if exists revenue_attachments_read on public.revenue_attachments;
create policy revenue_attachments_read on public.revenue_attachments
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and public.may_read_revenue_attachments(revenue_entry_id)
  );

comment on policy revenue_attachments_read on public.revenue_attachments is
  'Delegates to the same security-definer predicate the Storage policies use, so the '
  'object and its metadata row can never disagree about who may have them (D-073a).';

-- No client role holds INSERT, UPDATE or DELETE. `revenue_attachment_register` is the
-- only writer, exactly as `attachment_register` is for expenses (spec §23).
revoke all on table public.revenue_attachments from public, anon, authenticated;
grant select on table public.revenue_attachments to authenticated;

-- ── Storage: the revenue prefix, on its own predicate ────────────────────────
--
-- Additive. The three expense policies are untouched and keep deciding the `expenses/`
-- prefix; these three decide `revenue/`. A `delete` policy is deliberately absent for
-- both: nobody removes evidence through the object API.
drop policy if exists revenue_attachments_storage_read on storage.objects;
create policy revenue_attachments_storage_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'expense-attachments'
    and public.may_read_revenue_attachments(public.storage_revenue_id(name))
  );

drop policy if exists revenue_attachments_storage_write on storage.objects;
create policy revenue_attachments_storage_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'expense-attachments'
    and public.has_capability_anywhere('attachment.upload')
    and public.may_read_revenue_attachments(public.storage_revenue_id(name))
  );

drop policy if exists revenue_attachments_storage_update on storage.objects;
create policy revenue_attachments_storage_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'expense-attachments'
    and public.has_capability_anywhere('attachment.upload')
    and public.may_read_revenue_attachments(public.storage_revenue_id(name))
  );

-- ── Registering an uploaded object as canonical metadata ─────────────────────
--
-- Deliberately its own RPC rather than a discriminator on `attachment_register`: each one
-- re-checks the authority of its own parent, and a single endpoint taking "which kind of
-- document is this" from the caller would be a client choosing which rules apply to it.
create or replace function public.revenue_attachment_register(
  p_id               uuid,
  p_revenue_entry_id uuid,
  p_file_name        text,
  p_content_type     text,
  p_byte_size        bigint,
  p_content_hash     text,
  p_storage_path     text,
  p_mutation_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor    uuid;
  v_org      uuid;
  v_replay   jsonb;
  v_result   jsonb;
  v_existing public.revenue_attachments;
  e          record;
  v_count    integer;
  v_bytes    bigint;
  v_expected text;
begin
  -- Idempotency first, as everywhere else: a redelivered registration replays its stored
  -- answer rather than inserting a second row for the same bytes (D-004).
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  -- Permission before existence (D-046).
  perform app.require_capability_anywhere('attachment.upload');

  -- A second delivery that lost its mutation id still must not duplicate. The attachment
  -- id is client-generated and stable, so it is the natural identity (D-008). This is the
  -- half of idempotency that survives a lost response with no mutation id to replay on.
  select * into v_existing from public.revenue_attachments where id = p_id;
  if v_existing.id is not null then
    if v_existing.revenue_entry_id <> p_revenue_entry_id
       or v_existing.content_hash <> p_content_hash then
      perform app.refuse('KM009', 'immutable_field',
        'This attachment has already been recorded with different content.',
        jsonb_build_object('attachment_id', p_id));
    end if;
    return jsonb_build_object(
      'status', 'already_registered', 'entity_type', 'revenue_attachment',
      'entity_id', p_id, 'revenue_entry_id', v_existing.revenue_entry_id,
      'storage_path', v_existing.storage_path,
      'content_hash', v_existing.content_hash,
      'uploaded_at', v_existing.uploaded_at,
      'row_version', v_existing.row_version);
  end if;

  select * into e from public.revenue_entries
   where id = p_revenue_entry_id and org_id = v_org;
  if e.id is null then
    perform app.refuse('KM015', 'unknown_entity',
      'That revenue entry does not exist.',
      jsonb_build_object('revenue_entry_id', p_revenue_entry_id));
  end if;

  -- The parent's own read authority, restated at the metadata boundary. Attaching implies
  -- reading back, so somebody who may not see the sale may not attach to it.
  if not public.may_read_revenue_attachments(p_revenue_entry_id) then
    perform app.refuse('KM002', 'out_of_unit_scope',
      'This sale belongs to a property you cannot see.',
      jsonb_build_object('revenue_entry_id', p_revenue_entry_id));
  end if;

  -- A voided document keeps the evidence it already has and gains none (D-006, and the
  -- expense rule this mirrors exactly). Correct by recording a new document.
  if e.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This sale has been voided. Its existing attachments remain, but nothing '
      'further can be added.',
      jsonb_build_object('revenue_entry_id', p_revenue_entry_id));
  end if;

  -- The approved limits — the same numbers as for an expense, because they are the
  -- product's attachment policy and not a per-document decision. Enforced where a
  -- modified client cannot skip them.
  select count(*), coalesce(sum(byte_size), 0)
    into v_count, v_bytes
    from public.revenue_attachments
   where revenue_entry_id = p_revenue_entry_id;

  if v_count >= 5 then
    perform app.refuse('KM022', 'attachment_limit',
      'A sale can carry at most 5 attachments.',
      jsonb_build_object('revenue_entry_id', p_revenue_entry_id,
                         'attachments', v_count));
  end if;

  if p_byte_size > 10485760 then
    perform app.refuse('KM022', 'attachment_limit',
      'A single attachment may be up to 10 MB.',
      jsonb_build_object('byte_size', p_byte_size));
  end if;

  if v_bytes + p_byte_size > 26214400 then
    perform app.refuse('KM022', 'attachment_limit',
      'Together the attachments on one sale may be up to 25 MB.',
      jsonb_build_object('total_bytes', v_bytes + p_byte_size));
  end if;

  -- The path is derived, not accepted. A client that names somebody else's object gets
  -- nowhere: path predictability is not authorisation, and this makes the row's path
  -- agree with the one the Storage policy parses (spec §15.2). A user-supplied file name
  -- reaches the object name only as its extension, lower-cased, so a name carrying `../`
  -- or a slash cannot become part of the path at all.
  v_expected := 'org/' || v_org || '/revenue/' || p_revenue_entry_id || '/' || p_id || '.'
              || lower(coalesce(nullif(regexp_replace(p_file_name, '^.*\.', ''), p_file_name), 'bin'));
  if p_storage_path is distinct from v_expected then
    perform app.refuse('KM010', 'impossible_structure',
      'That storage path does not belong to this attachment.',
      jsonb_build_object('expected', v_expected, 'given', p_storage_path));
  end if;

  insert into public.revenue_attachments (
    id, org_id, revenue_entry_id, file_name, content_type, byte_size,
    content_hash, storage_path, uploaded_by, uploaded_at)
  values (
    p_id, v_org, p_revenue_entry_id, p_file_name, p_content_type, p_byte_size,
    p_content_hash, p_storage_path, v_actor, now());

  select * into v_existing from public.revenue_attachments where id = p_id;

  v_result := jsonb_build_object(
    'status', 'registered', 'entity_type', 'revenue_attachment', 'entity_id', p_id,
    'revenue_entry_id', p_revenue_entry_id, 'storage_path', v_existing.storage_path,
    'content_hash', v_existing.content_hash,
    'uploaded_at', v_existing.uploaded_at,
    'row_version', v_existing.row_version);

  perform app.write_audit(v_org, 'revenue_attachment', p_id, 'attachment_registered',
    v_actor, null, to_jsonb(v_existing), null, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'revenue_attachment',
                               p_id, 'register', v_result);
end;
$$;

comment on function public.revenue_attachment_register(uuid, uuid, text, text, bigint, text, text, uuid) is
  'Records an uploaded file as canonical evidence for a revenue entry. Callers entitled '
  'to the parent sale only, never for a voided one, within the approved limits, and '
  'idempotent on the client-generated attachment id.';

revoke all on function public.revenue_attachment_register(uuid, uuid, text, text, bigint, text, text, uuid)
  from public, anon;
grant execute on function public.revenue_attachment_register(uuid, uuid, text, text, bigint, text, text, uuid)
  to authenticated;

-- ── The projection is deliberately not changed ──────────────────────────────
--
-- No `attachment_count` column was added to `revenue_document`. It would be a derived
-- figure duplicated onto a header — the shape `revenue_tables.dart` declines for the
-- money itself, for the same reason — and a client that wants to know what evidence a
-- sale carries reads `revenue_attachments`, which is behind the parent's own authority
-- and returns the file names it is going to display anyway. One round trip either way,
-- and one place the answer lives.

-- ── Invariants ───────────────────────────────────────────────────────────────

-- The generalised capability check D-116 added, re-run over the new policy and view. It
-- refused its own migration on first run last time, which is why it is repeated here
-- rather than assumed to still hold.
do $$
declare v_missing text;
begin
  select string_agg(distinct found.m[1], ', ') into v_missing
    from (
      select regexp_matches(pg_get_viewdef(c.oid, true),
                            'has_capability\(''([a-z._]+)''', 'g') as m
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'revenue%'
      union all
      select regexp_matches(coalesce(p.qual, ''),
                            'has_capability\(''([a-z._]+)''', 'g')
        from pg_policies p
       where p.schemaname = 'public' and p.tablename like 'revenue%'
      union all
      select regexp_matches(pg_get_functiondef(p.oid),
                            'has_capability\w*\(''([a-z._]+)''', 'g')
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname like '%revenue_attachment%'
    ) as found
   where not exists (
     select 1 from public.role_capabilities rc where rc.capability_code = found.m[1]);

  if v_missing is not null then
    raise exception
      'a revenue policy, projection or attachment boundary requires a capability no role holds: %.',
      v_missing;
  end if;
end $$;

-- The bucket must still be private, and it must still be one bucket.
do $$
begin
  if exists (select 1 from storage.buckets
              where id = 'expense-attachments' and public) then
    raise exception 'the attachment bucket must not be public';
  end if;
  if exists (select 1 from storage.buckets where id like '%revenue%') then
    raise exception
      'a second attachment bucket exists — revenue shares the private bucket under its '
      'own path prefix, so that the size limit, MIME list and policies have one definition';
  end if;
end $$;

-- The two storage prefixes must be genuinely separate. A path parser that answered for
-- the wrong prefix would let one predicate decide the other's objects.
do $$
begin
  if public.storage_revenue_id(
       'org/00000000-0000-0000-0000-000000000000/expenses/'
       '11111111-1111-1111-1111-111111111111/a.jpg') is not null then
    raise exception 'the revenue path parser matches an expense object';
  end if;
  if public.storage_expense_id(
       'org/00000000-0000-0000-0000-000000000000/revenue/'
       '11111111-1111-1111-1111-111111111111/a.jpg') is not null then
    raise exception 'the expense path parser matches a revenue object';
  end if;
  if public.storage_revenue_id(
       'org/00000000-0000-0000-0000-000000000000/revenue/'
       '11111111-1111-1111-1111-111111111111/a.jpg')
     is distinct from '11111111-1111-1111-1111-111111111111'::uuid then
    raise exception 'the revenue path parser does not find its own entry id';
  end if;
end $$;

-- No client role may write the metadata table directly. The RPC is the only writer, and
-- that is what makes the content hash and the uploading actor mean anything.
do $$
declare v_grants text;
begin
  select string_agg(privilege_type, ', ') into v_grants
    from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'revenue_attachments'
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_grants is not null then
    raise exception 'a client role can write revenue_attachments directly: %', v_grants;
  end if;
end $$;

-- V1 ships no attachment removal, for either document (D-072a). Asserted rather than
-- merely intended, because a column nobody writes is how the last three findings started.
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'revenue_attachments'
                and column_name in ('removed_at', 'removed_by', 'remove_reason')) then
    raise exception
      'revenue_attachments carries removal columns, but V1 ships no removal writer — a '
      'second unwritable constraint is not a feature (D-072a, D-145)';
  end if;
end $$;
