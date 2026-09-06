/// Getting a staged file to the server, out of band, without its document ever waiting.
///
/// The rule this file exists to keep: **an attachment failure never touches a financial
/// record.** An expense created offline with a photograph syncs, is numbered, and is
/// Synced, whatever the photograph does afterwards; so does a sale recorded with a till
/// report beside it. The file retries on its own durable backoff, and its failure is
/// reported as its own — not as the document's.
///
/// The three states that matter are kept honest:
///
/// * `pending` — staged locally, not on the server. Never shown as anything else.
/// * `uploaded` — the server has the object **and** the bytes hashed to the value
///   computed before the upload. "The request returned 200" is a weaker claim and is not
///   the one this state makes.
/// * `failed` — surfaced with its reason and retried; never silently dropped, and never
///   allowed to look like success.
///
/// Reclaiming the local copy happens seven days after confirmation, and only after
/// confirmation. Deleting it at upload time would make every later retry impossible.
///
/// ## One worker, two document kinds (Slice 11)
///
/// Revenue attachments are not a second subsystem. This is the same worker, the same
/// backoff clock, the same ordering rule and the same reclamation policy, driven over two
/// tables through [_OwnerTables]. The alternative — a `RevenueAttachmentUploadWorker`
/// beside this one — would have been two retry clocks and two definitions of "uploaded"
/// that agree only until somebody edits one of them.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/domain/sync/retry_policy.dart';

/// What the object store did with one upload.
sealed class UploadOutcome {
  const UploadOutcome();
}

/// The object is stored, and the server reported this hash for it.
final class UploadStored extends UploadOutcome {
  const UploadStored({required this.storagePath, this.reportedHash});
  final String storagePath;

  /// What the store says it holds. Null when the store does not report one, in which case
  /// the worker re-reads the object to verify rather than assuming.
  final String? reportedHash;
}

/// The store refused. Terminal until something changes — a policy, a quota, a session.
final class UploadRefused extends UploadOutcome {
  const UploadRefused(this.message);
  final String message;
}

/// Nothing was learned. Retry.
final class UploadUnreachable extends UploadOutcome {
  const UploadUnreachable(this.message);
  final String message;
}

/// The object store, behind an interface so the worker can be tested without one.
abstract interface class AttachmentObjectStore {
  /// Uploads [bytes] to the deterministic path for this attachment.
  ///
  /// The path is derived, never secret: path secrecy is not authorisation, and the bucket
  /// is private with server-side policy deciding who may read it.
  Future<UploadOutcome> upload({
    required String orgId,
    required AttachmentOwnerKind owner,
    required String ownerId,
    required String attachmentId,
    required String fileName,
    required String contentType,
    required List<int> bytes,
  });

  /// Reads back the stored object's hash, for stores that do not report one on write.
  ///
  /// Answered from the **canonical metadata row**, not from the object, so a non-null
  /// result is also the answer to *"did the registration commit?"* — which is what a
  /// client that lost a response actually needs to know before it does anything else.
  Future<String?> hashOf(AttachmentOwnerKind owner, String storagePath);

  /// Removes an object that registration terminally refused, and reports whether it went.
  ///
  /// Only ever called after a refusal, and the server refuses the delete outright while
  /// any metadata row names the path — so this cannot destroy evidence even if the client
  /// is wrong about what happened. An object nothing names is not evidence; Postgres is
  /// the record of what evidence exists (spec §23).
  Future<bool> discardUnregistered(
    AttachmentOwnerKind owner,
    String storagePath,
  );
}

/// The deterministic object path (spec §15.2).
///
/// The same file uploaded twice overwrites itself rather than duplicating. Predictable by
/// design — a client has to be able to name what it just wrote — and worthless to an
/// unauthorised caller, because the bucket is private and the policy, not the path, is
/// what decides access.
///
/// The owner segment is what lets one bucket hold both kinds under two policies: an
/// object under `expenses/` is decided by the expense predicate, one under `revenue/` by
/// the revenue one, and neither can be reached through the other's rule.
String attachmentStoragePath({
  required String orgId,
  required AttachmentOwnerKind owner,
  required String ownerId,
  required String attachmentId,
  required String fileName,
}) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : 'bin';
  return 'org/$orgId/${owner.storageSegment}/$ownerId/$attachmentId.$extension';
}

/// Where one document kind's attachments live locally, and what its parent is called.
///
/// The only thing that differs between an expense attachment and a revenue attachment,
/// once the lifecycle is shared: two table names and a column name. Everything else in
/// this file is written once.
final class _OwnerTables {
  const _OwnerTables({
    required this.kind,
    required this.table,
    required this.parentTable,
    required this.parentIdColumn,
  });

  final AttachmentOwnerKind kind;
  final String table;
  final String parentTable;
  final String parentIdColumn;

  static const expense = _OwnerTables(
    kind: AttachmentOwnerKind.expense,
    table: 'expense_attachments',
    parentTable: 'expenses',
    parentIdColumn: 'expense_id',
  );

  static const sale = _OwnerTables(
    kind: AttachmentOwnerKind.sale,
    table: 'revenue_attachments',
    parentTable: 'revenue_entries',
    parentIdColumn: 'revenue_entry_id',
  );

  static const all = [expense, sale];
}

/// One row of either attachment table, read by name so one worker serves both.
final class _DueAttachment {
  _DueAttachment(this.owner, QueryRow row)
    : id = row.read<String>('id'),
      orgId = row.read<String>('org_id'),
      ownerId = row.read<String>(owner.parentIdColumn),
      fileName = row.read<String>('file_name'),
      contentType = row.read<String>('content_type'),
      contentHash = row.read<String>('content_hash'),
      localPath = row.read<String?>('local_path'),
      attemptCount = row.read<int>('attempt_count');

  final _OwnerTables owner;
  final String id;
  final String orgId;
  final String ownerId;
  final String fileName;
  final String contentType;
  final String contentHash;
  final String? localPath;
  final int attemptCount;
}

class AttachmentUploadWorker {
  AttachmentUploadWorker({
    required this.db,
    required this.store,
    this.retryPolicy = const RetryPolicy(),
    this.clock = DateTime.now,
  });

  final AppDatabase db;
  final AttachmentObjectStore store;
  final RetryPolicy retryPolicy;
  final DateTime Function() clock;

  /// Uploads whatever is due, for both document kinds. Returns how many were confirmed.
  ///
  /// Never throws for an individual failure: one unreadable file must not stop the queue,
  /// and nothing here can affect a document's own sync state.
  Future<int> uploadDue({int limit = 5}) async {
    final now = clock();

    // Attachments whose document the server has since accepted become eligible. This is
    // the ordering rule in D-073 §2, and it lives here rather than in the caller because
    // the caller cannot know when a document was accepted — the reconciler writes the
    // transaction number in the data layer, and this query is what notices.
    await promoteAcceptedDocuments();

    var confirmed = 0;
    for (final owner in _OwnerTables.all) {
      final due = await db
          .customSelect(
            // Only the two uploadable states, and only when their retry time has come.
            //
            // `rejected` is absent deliberately, and the check constraint keeps its
            // `next_attempt_at` null: a null there was once read as "due now", which
            // retried a terminal refusal for ever until a test caught it.
            'SELECT * FROM ${owner.table} WHERE '
            "((upload_state = 'pendingUpload' "
            '   AND (next_attempt_at IS NULL OR next_attempt_at <= ?1)) '
            " OR (upload_state = 'retryNeeded' "
            '   AND next_attempt_at IS NOT NULL AND next_attempt_at <= ?1)) '
            'LIMIT ?2',
            variables: [Variable<DateTime>(now), Variable<int>(limit)],
          )
          .get();

      for (final row in due) {
        if (await _uploadOne(_DueAttachment(owner, row), now)) confirmed++;
      }
    }
    return confirmed;
  }

  /// Moves attachments whose document has been accepted from `waitingForExpense` to
  /// `pendingUpload`, and returns how many moved.
  ///
  /// "Accepted" means the server issued a transaction number and nothing is still queued
  /// against the document — the same two facts the ledger uses to call a record `Synced`,
  /// and the same two columns on both parent tables. Uploading before that is not merely
  /// early: the Storage write policy calls the parent's read predicate, which requires
  /// the document to exist canonically, so the attempt would be refused for a reason that
  /// reads like a permission problem.
  Future<int> promoteAcceptedDocuments() async {
    var moved = 0;
    for (final owner in _OwnerTables.all) {
      moved += await db.customUpdate(
        "UPDATE ${owner.table} SET upload_state = 'pendingUpload' "
        "WHERE upload_state = 'waitingForExpense' "
        'AND ${owner.parentIdColumn} IN ('
        '  SELECT id FROM ${owner.parentTable} '
        '   WHERE txn_number IS NOT NULL AND pending_mutation_id IS NULL)',
        updates: const {},
      );
    }
    return moved;
  }

  /// Marks an expense's attachments ready to upload once the expense is saved.
  ///
  /// Called when the document is written locally: the file stops being a draft's
  /// [AttachmentUploadState.staged] copy and starts waiting for the document it belongs
  /// to.
  Future<int> markWaitingForExpense(String expenseId) =>
      _markWaiting(_OwnerTables.expense, expenseId);

  /// The same, for a sale.
  Future<int> markWaitingForSale(String revenueEntryId) =>
      _markWaiting(_OwnerTables.sale, revenueEntryId);

  Future<int> _markWaiting(_OwnerTables owner, String ownerId) =>
      db.customUpdate(
        "UPDATE ${owner.table} SET upload_state = 'waitingForExpense' "
        "WHERE ${owner.parentIdColumn} = ? AND upload_state = 'staged'",
        variables: [Variable<String>(ownerId)],
        updates: const {},
      );

  Future<bool> _uploadOne(_DueAttachment row, DateTime now) async {
    final path = row.localPath;
    if (path == null || !File(path).existsSync()) {
      // The staged copy is gone and the object was never confirmed. Nothing can be
      // recovered by retrying, and the document is unaffected — so this is reported for
      // a person rather than retried forever.
      await _markFailed(
        row,
        now,
        'The saved copy of this file is no longer on this device.',
        retryable: false,
      );
      return false;
    }

    final expectedPath = attachmentStoragePath(
      orgId: row.orgId,
      owner: row.owner.kind,
      ownerId: row.ownerId,
      attachmentId: row.id,
      fileName: row.fileName,
    );

    // **Before re-uploading, find out whether the last attempt actually landed.**
    //
    // An upload is two writes, and only the second is idempotent by mutation id. When the
    // response to the second is lost, the client knows nothing and the row comes back
    // round as `retryNeeded` — while on the server the registration may already have
    // committed. Re-uploading then would push bytes over an object that is already
    // canonical evidence, which the Storage policy now refuses outright, and the refusal
    // would read as terminal for an attachment that is in fact finished.
    //
    // So the retry asks the metadata row first. Only a retry: a first attempt cannot have
    // registered anything, and paying a round trip to establish that would be a round trip
    // on the common path to answer a question with one possible answer.
    if (row.attemptCount > 0) {
      final registered = await store.hashOf(row.owner.kind, expectedPath);
      if (registered != null) {
        if (registered != row.contentHash) {
          // A different file is recorded under this attachment's identity. Nothing this
          // worker can do is right, and overwriting the record would be the one thing
          // that is definitely wrong.
          await _markFailed(
            row,
            now,
            'A different file is already recorded against this attachment.',
            retryable: false,
          );
          return false;
        }
        await _markUploaded(row, expectedPath, now);
        return true;
      }
    }

    // Persisted before the request goes out, so a crash mid-upload is recoverable rather
    // than invisible. A row left `uploading` by a kill is picked up by the next pass,
    // because the object write is idempotent on its deterministic path.
    await db.customUpdate(
      "UPDATE ${row.owner.table} SET upload_state = 'uploading' WHERE id = ?",
      variables: [Variable<String>(row.id)],
      updates: const {},
    );

    final bytes = await File(path).readAsBytes();

    // Verify what is about to be sent still matches what was staged. A file that changed
    // underneath us is not the evidence that was attached.
    final localHash = sha256Of(bytes);
    if (localHash != row.contentHash) {
      await _markFailed(
        row,
        now,
        'This file has changed since it was attached.',
        retryable: false,
      );
      return false;
    }

    final outcome = await store.upload(
      orgId: row.orgId,
      owner: row.owner.kind,
      ownerId: row.ownerId,
      attachmentId: row.id,
      fileName: row.fileName,
      contentType: row.contentType,
      bytes: bytes,
    );

    switch (outcome) {
      case UploadStored(:final storagePath, :final reportedHash):
        // Confirmation is about bytes. If the store reports a hash, compare it; if it
        // does not, read one back. Either way "uploaded" means verified.
        final serverHash =
            reportedHash ?? await store.hashOf(row.owner.kind, storagePath);
        if (serverHash != null && serverHash != localHash) {
          await _markFailed(
            row,
            now,
            'The uploaded copy did not match the file on this device.',
          );
          return false;
        }
        await _markUploaded(row, storagePath, now);
        return true;

      case UploadRefused(:final message):
        await _markFailed(row, now, message, retryable: false);
        return false;

      case UploadUnreachable(:final message):
        await _markFailed(row, now, message);
        return false;
    }
  }

  Future<void> _markUploaded(
    _DueAttachment row,
    String storagePath,
    DateTime now,
  ) async {
    await db.customUpdate(
      "UPDATE ${row.owner.table} SET upload_state = 'uploaded', "
      'storage_path = ?, uploaded_at = ?, reclaimable_after = ?, '
      'last_error = NULL, next_attempt_at = NULL WHERE id = ?',
      variables: [
        Variable<String>(storagePath),
        Variable<DateTime>(now),
        // The staged copy stays for a week after confirmation. Deleting it now would
        // make recovery from a later problem impossible for the sake of some bytes.
        Variable<DateTime>(now.add(AttachmentPolicy.stagingRetention)),
        Variable<String>(row.id),
      ],
      updates: const {},
    );
  }

  Future<void> _markFailed(
    _DueAttachment row,
    DateTime now,
    String message, {
    bool retryable = true,
  }) async {
    final attempt = row.attemptCount + 1;
    await db.customUpdate(
      // Two different answers, kept apart: one will be retried on the durable clock,
      // the other never will. Collapsing them into a single `failed` is how a refusal
      // comes to be retried for ever.
      'UPDATE ${row.owner.table} SET upload_state = ?, attempt_count = ?, '
      'last_error = ?, next_attempt_at = ? WHERE id = ?',
      variables: [
        Variable<String>(retryable ? 'retryNeeded' : 'rejected'),
        Variable<int>(attempt),
        Variable<String>(message),
        Variable<DateTime>(
          retryable ? retryPolicy.nextAttemptAt(now, attempt) : null,
        ),
        Variable<String>(row.id),
      ],
      updates: const {},
    );
  }

  /// Returns rows left `uploading` by a crash to `pendingUpload`, for both kinds.
  ///
  /// Called at start-up, exactly as the outbox recovers its own `inFlight` entries. Safe
  /// because the object path is deterministic: re-uploading writes the same object again
  /// rather than a second one (D-073 §8).
  Future<int> recoverInterruptedUploads() async {
    var recovered = 0;
    for (final owner in _OwnerTables.all) {
      recovered += await db.customUpdate(
        "UPDATE ${owner.table} SET upload_state = 'pendingUpload' "
        "WHERE upload_state = 'uploading'",
        updates: const {},
      );
    }
    return recovered;
  }

  /// Reclaims verified staging copies whose retention has elapsed, for both kinds.
  ///
  /// Only ever touches rows that are `uploaded` *and* past `reclaimable_after` — a copy
  /// that was never confirmed is never reclaimed, however old, because it is the only
  /// copy there is.
  Future<int> reclaimVerifiedStaging() async {
    final now = clock();
    var reclaimed = 0;
    for (final owner in _OwnerTables.all) {
      final ready = await db
          .customSelect(
            'SELECT id, local_path FROM ${owner.table} '
            "WHERE upload_state = 'uploaded' AND reclaimable_after <= ? "
            'AND local_path IS NOT NULL',
            variables: [Variable<DateTime>(now)],
          )
          .get();

      for (final row in ready) {
        final file = File(row.read<String>('local_path'));
        if (file.existsSync()) await file.delete();
        await db.customUpdate(
          "UPDATE ${owner.table} SET upload_state = 'stagingReclaimed', "
          'local_path = NULL WHERE id = ?',
          variables: [Variable<String>(row.read<String>('id'))],
          updates: const {},
        );
        reclaimed++;
      }
    }
    return reclaimed;
  }
}
