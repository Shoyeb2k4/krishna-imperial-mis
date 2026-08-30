-- D-073 — registering an uploaded attachment as canonical metadata.
--
-- The Storage half of attachments has been in place since 0031: a private bucket, the
-- deterministic object path, and `may_read_expense_attachments` holding D-063's
-- complete-document predicate for read, write and update. What was missing was the other
-- half — a client has SELECT on `public.expense_attachments` and no INSERT, deliberately,
-- because a financial record's evidence is not something a client writes directly.
--
-- ## Why the metadata is not the object listing
--
-- Storage can be listed, and it would be tempting to treat "there is an object at this
-- path" as the record. It is not. Postgres is the canonical metadata store (spec §23):
-- the object listing carries no content hash we control, no uploading actor, no audit
-- row, and no relationship to the expense that a foreign key enforces. A bucket is where
-- bytes live; it is not the ledger.
--
-- ## Order, and why the write policy already enforces it
--
-- `expense_attachments_write` calls `may_read_expense_attachments`, which requires the
-- expense to exist in this organisation and every one of its lines to be visible to the
-- caller. So an object cannot be written for an expense the server has not accepted —
-- the client must sync the financial record first, and this RPC re-states the same rule
-- rather than trusting that the object write happened to be checked.

create or replace function public.attachment_register(
  p_id            uuid,
  p_expense_id    uuid,
  p_file_name     text,
  p_content_type  text,
  p_byte_size     bigint,
  p_content_hash  text,
  p_storage_path  text,
  p_mutation_id   uuid default null
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
  v_existing public.expense_attachments;
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
  -- id is client-generated and stable, so it is the natural identity (D-008).
  select * into v_existing from public.expense_attachments where id = p_id;
  if v_existing.id is not null then
    if v_existing.expense_id <> p_expense_id
       or v_existing.content_hash <> p_content_hash then
      perform app.refuse('KM009', 'immutable_field',
        'This attachment has already been recorded with different content.',
        jsonb_build_object('attachment_id', p_id));
    end if;
    return jsonb_build_object(
      'status', 'already_registered', 'entity_type', 'expense_attachment',
      'entity_id', p_id, 'expense_id', v_existing.expense_id,
      'storage_path', v_existing.storage_path,
      'content_hash', v_existing.content_hash,
      'uploaded_at', v_existing.uploaded_at,
      'row_version', v_existing.row_version);
  end if;

  select * into e from public.expenses where id = p_expense_id and org_id = v_org;
  if e.id is null then
    perform app.refuse('KM015', 'unknown_entity',
      'That expense does not exist.',
      jsonb_build_object('expense_id', p_expense_id));
  end if;

  -- The complete-document rule, restated at the metadata boundary. An attachment is the
  -- whole bill and states the whole total on its face (D-063), so a caller who receives a
  -- scoped projection of this document may not attach to it either — attaching implies
  -- reading it back.
  if not public.may_read_expense_attachments(p_expense_id) then
    perform app.refuse('KM002', 'out_of_unit_scope',
      'This expense is only partly visible to you, so its attachments are not '
      'available.',
      jsonb_build_object('expense_id', p_expense_id));
  end if;

  -- A voided document keeps the evidence it already has and gains none (D-006, and the
  -- project lead's V1 rule). Correct by recording a new document.
  if e.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This expense has been voided. Its existing attachments remain, but nothing '
      'further can be added.',
      jsonb_build_object('expense_id', p_expense_id));
  end if;

  -- The approved limits, enforced where a modified client cannot skip them (§18).
  select count(*), coalesce(sum(byte_size), 0)
    into v_count, v_bytes
    from public.expense_attachments
   where expense_id = p_expense_id and removed_at is null;

  if v_count >= 5 then
    perform app.refuse('KM022', 'attachment_limit',
      'An expense can carry at most 5 attachments.',
      jsonb_build_object('expense_id', p_expense_id, 'attachments', v_count));
  end if;

  if p_byte_size > 10485760 then
    perform app.refuse('KM022', 'attachment_limit',
      'A single attachment may be up to 10 MB.',
      jsonb_build_object('byte_size', p_byte_size));
  end if;

  if v_bytes + p_byte_size > 26214400 then
    perform app.refuse('KM022', 'attachment_limit',
      'Together the attachments on one expense may be up to 25 MB.',
      jsonb_build_object('total_bytes', v_bytes + p_byte_size));
  end if;

  -- The path is derived, not accepted. A client that names somebody else's object gets
  -- nowhere: path predictability is not authorisation, and this makes the row's path
  -- agree with the one the Storage policy parses (spec §15.2).
  v_expected := 'org/' || v_org || '/expenses/' || p_expense_id || '/' || p_id || '.'
              || lower(coalesce(nullif(regexp_replace(p_file_name, '^.*\.', ''), p_file_name), 'bin'));
  if p_storage_path is distinct from v_expected then
    perform app.refuse('KM010', 'impossible_structure',
      'That storage path does not belong to this attachment.',
      jsonb_build_object('expected', v_expected, 'given', p_storage_path));
  end if;

  insert into public.expense_attachments (
    id, org_id, expense_id, file_name, content_type, byte_size,
    content_hash, storage_path, uploaded_by, uploaded_at)
  values (
    p_id, v_org, p_expense_id, p_file_name, p_content_type, p_byte_size,
    p_content_hash, p_storage_path, v_actor, now());

  select * into v_existing from public.expense_attachments where id = p_id;

  v_result := jsonb_build_object(
    'status', 'registered', 'entity_type', 'expense_attachment', 'entity_id', p_id,
    'expense_id', p_expense_id, 'storage_path', v_existing.storage_path,
    'content_hash', v_existing.content_hash,
    'uploaded_at', v_existing.uploaded_at,
    'row_version', v_existing.row_version);

  perform app.write_audit(v_org, 'expense_attachment', p_id, 'attachment_registered',
    v_actor, null, to_jsonb(v_existing), null, null::uuid, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor, 'expense_attachment',
                               p_id, 'register', v_result);
end;
$$;

comment on function public.attachment_register(uuid, uuid, text, text, bigint, text, text, uuid) is
  'Records an uploaded bill as canonical metadata. Complete-document callers only '
  '(D-063), never for a voided expense, within the approved limits, and idempotent on '
  'the client-generated attachment id.';

revoke all on function public.attachment_register(uuid, uuid, text, text, bigint, text, text, uuid)
  from public, anon;
grant execute on function public.attachment_register(uuid, uuid, text, text, bigint, text, text, uuid)
  to authenticated;

-- The reviewed API surface gains `attachment_register`. Restated in full in its own
-- migration beside this one, which is where that invariant has always lived.
