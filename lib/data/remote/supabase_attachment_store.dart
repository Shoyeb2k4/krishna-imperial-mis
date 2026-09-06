/// The production object store: Supabase Storage, plus the canonical metadata row that
/// makes an uploaded object part of the financial record (D-073).
///
/// ## Two writes, and why both are needed
///
/// Uploading the bytes puts a bill in a private bucket. It does not put it in the books.
/// Postgres is the canonical metadata store (spec §23): the object listing carries no
/// content hash this application controls, no uploading actor, no audit row, and no
/// foreign key to the expense. So an upload is *stored* when the object is written **and**
/// `attachment_register` has recorded it — and only then does the worker call it
/// `uploaded`.
///
/// ## What authorises it
///
/// The signed-in user's own Supabase session, and nothing else. There is no service-role
/// key here, the bucket is private, and the object path is derived rather than secret —
/// path predictability is not authorisation (spec §15.2). Every one of these calls is
/// evaluated against the Storage policies from migration 0031, which hold D-063's
/// complete-document predicate: a caller who receives a scoped projection of a shared
/// bill cannot read its original, and cannot write one either.
///
/// ## Transient versus terminal
///
/// The distinction is the whole reason [UploadOutcome] has three arms. A network that
/// failed says nothing about whether the upload is allowed, so it is retried on the
/// durable clock. A refusal is the server's considered answer, and repeating the
/// identical request cannot change it — it can only spin (D-048 §1, and the same
/// reasoning `RemoteOutcome` encodes for every other call).
library;

import 'dart:typed_data';

import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/data/attachments/attachment_upload_worker.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/supabase_gateway.dart';
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The private bucket the migrations create. Named once.
///
/// **Its id still reads `expense-attachments`, and that is deliberate.** It holds both
/// kinds since Slice 11, under two path prefixes decided by two separate policies. A
/// bucket id is where bytes physically live: renaming it would strand every bill already
/// uploaded, for the sake of a word. One bucket rather than two is the substantive
/// decision — a second one would duplicate the size limit, the MIME list and four
/// policies, all of which then have to be kept in step by hand.
const String financialAttachmentBucket = 'expense-attachments';

class SupabaseAttachmentStore extends SupabaseGateway
    implements AttachmentObjectStore {
  SupabaseAttachmentStore(super.client);

  @override
  Future<UploadOutcome> upload({
    required String orgId,
    required AttachmentOwnerKind owner,
    required String ownerId,
    required String attachmentId,
    required String fileName,
    required String contentType,
    required List<int> bytes,
  }) async {
    final path = attachmentStoragePath(
      orgId: orgId,
      owner: owner,
      ownerId: ownerId,
      attachmentId: attachmentId,
      fileName: fileName,
    );

    try {
      await client.storage
          .from(financialAttachmentBucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              contentType: contentType,
              // The same bytes uploaded twice overwrite themselves rather than creating a
              // second object. That is what makes a retry after a lost response safe
              // (D-073 §8): one deterministic path, one object, however many attempts.
              upsert: true,
            ),
          );
    } on StorageException catch (error) {
      final outcome = _classifyStorage(error);
      if (outcome != null) return outcome;
      return UploadUnreachable(error.message);
    } on Object catch (error) {
      // Anything that is not the server answering is, by definition, not an answer.
      return UploadUnreachable('$error');
    }

    // The object exists. Now make it part of the record, or it is a file nobody can find
    // from the ledger.
    //
    // Two RPCs rather than one with a discriminator: each re-checks the authority of its
    // own parent document, and a single endpoint taking "which kind" from the caller
    // would be a client telling the server which rules to apply to it.
    final registered = await guard<Map<String, dynamic>>(
      () async =>
          (await client.rpc<dynamic>(
                switch (owner) {
                  AttachmentOwnerKind.expense => 'attachment_register',
                  AttachmentOwnerKind.sale => 'revenue_attachment_register',
                },
                params: {
                  'p_id': attachmentId,
                  switch (owner) {
                    AttachmentOwnerKind.expense => 'p_expense_id',
                    AttachmentOwnerKind.sale => 'p_revenue_entry_id',
                  }: ownerId,
                  'p_file_name': fileName,
                  'p_content_type': contentType,
                  'p_byte_size': bytes.length,
                  'p_content_hash': sha256Of(bytes),
                  'p_storage_path': path,
                  'p_mutation_id': attachmentId,
                },
              ))
              as Map<String, dynamic>,
    );

    return switch (registered) {
      RemoteOk(:final value) => UploadStored(
        storagePath: value['storage_path'] as String? ?? path,
        // The server echoes back the hash it recorded. Comparing it to the local one is
        // what turns "the request succeeded" into a statement about bytes.
        reportedHash: value['content_hash'] as String?,
      ),
      RemoteRefused(:final refusal) => UploadRefused(refusal.message),
      RemoteUnreachable() => const UploadUnreachable(
        'The bill was uploaded but could not be recorded. It will be retried.',
      ),
    };
  }

  @override
  Future<String?> hashOf(AttachmentOwnerKind owner, String storagePath) async {
    // Read it from the metadata row rather than from the object: this is the hash the
    // application controls and audits, and each metadata table is readable only to a
    // caller entitled to the parent document — the whole of it, for an expense (D-063).
    try {
      final row = await client
          .from(switch (owner) {
            AttachmentOwnerKind.expense => 'expense_attachments',
            AttachmentOwnerKind.sale => 'revenue_attachments',
          })
          .select('content_hash')
          .eq('storage_path', storagePath)
          .maybeSingle();
      return row?['content_hash'] as String?;
    } on Object {
      // Not knowing is not the same as a mismatch, and the worker treats null as "no
      // second opinion available" rather than as a failure.
      return null;
    }
  }

  /// Storage errors that are the server *deciding*, rather than the network failing.
  ///
  /// A 403 is the policy from migration 0031 answering — the caller may not write here,
  /// most often because the expense has not been accepted yet or because they hold only a
  /// scoped projection of it. Retrying that on a timer would spin for ever.
  UploadOutcome? _classifyStorage(StorageException error) {
    final status = int.tryParse('${error.statusCode}');
    if (status == null) return null;
    if (status == 401 || status == 403) {
      return const UploadRefused(
        'You are not permitted to attach a file to this record. It may still '
        'be syncing, or you may only be able to see part of the document.',
      );
    }
    if (status == 413) {
      return const UploadRefused('That file is larger than the limit.');
    }
    if (status == 415) {
      return const UploadRefused('That file type cannot be attached.');
    }
    if (status >= 400 && status < 500) {
      return UploadRefused(error.message);
    }
    return null;
  }
}
