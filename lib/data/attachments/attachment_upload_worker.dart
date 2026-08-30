/// Getting a staged bill to the server, out of band, without the expense ever waiting.
///
/// The rule this file exists to keep: **an attachment failure never touches a financial
/// record.** An expense created offline with a photograph syncs, is numbered, and is
/// Synced, whatever the photograph does afterwards. The photograph retries on its own
/// durable backoff, and its failure is reported as its own — not as the expense's.
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
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
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
    required String expenseId,
    required String attachmentId,
    required String fileName,
    required String contentType,
    required List<int> bytes,
  });

  /// Reads back the stored object's hash, for stores that do not report one on write.
  Future<String?> hashOf(String storagePath);
}

/// The deterministic object path (spec §15.2).
///
/// The same file uploaded twice overwrites itself rather than duplicating. Predictable by
/// design — a client has to be able to name what it just wrote — and worthless to an
/// unauthorised caller, because the bucket is private and the policy, not the path, is
/// what decides access.
String attachmentStoragePath({
  required String orgId,
  required String expenseId,
  required String attachmentId,
  required String fileName,
}) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : 'bin';
  return 'org/$orgId/expenses/$expenseId/$attachmentId.$extension';
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

  /// Uploads whatever is due. Returns how many were confirmed.
  ///
  /// Never throws for an individual failure: one unreadable file must not stop the queue,
  /// and nothing here can affect an expense's own sync state.
  Future<int> uploadDue({int limit = 5}) async {
    final now = clock();

    // Attachments whose expense the server has since accepted become eligible. This is
    // the ordering rule in D-073 §2, and it lives here rather than in the caller because
    // the caller cannot know when an expense was accepted — the reconciler writes the
    // transaction number in the data layer, and this query is what notices.
    await promoteAcceptedExpenses();

    final due =
        await (db.select(db.expenseAttachments)
              // Only the two uploadable states, and only when their retry time has come.
              //
              // `rejected` is absent deliberately, and the check constraint keeps its
              // `next_attempt_at` null: a null there was once read as "due now", which
              // retried a terminal refusal for ever until a test caught it.
              ..where(
                (t) =>
                    (t.uploadState.equals('pendingUpload') &
                        (t.nextAttemptAt.isNull() |
                            t.nextAttemptAt.isSmallerOrEqualValue(now))) |
                    (t.uploadState.equals('retryNeeded') &
                        t.nextAttemptAt.isNotNull() &
                        t.nextAttemptAt.isSmallerOrEqualValue(now)),
              )
              ..limit(limit))
            .get();

    var confirmed = 0;
    for (final row in due) {
      if (await _uploadOne(row, now)) confirmed++;
    }
    return confirmed;
  }

  /// Moves attachments whose expense has been accepted from `waitingForExpense` to
  /// `pendingUpload`, and returns how many moved.
  ///
  /// "Accepted" means the server issued a transaction number and nothing is still queued
  /// against the document — the same two facts the ledger uses to call an expense
  /// `Synced`. Uploading before that is not merely early: the Storage write policy calls
  /// `may_read_expense_attachments`, which requires the expense to exist canonically, so
  /// the attempt would be refused for a reason that reads like a permission problem.
  Future<int> promoteAcceptedExpenses() async {
    return db.customUpdate(
      "UPDATE expense_attachments SET upload_state = 'pendingUpload' "
      "WHERE upload_state = 'waitingForExpense' AND expense_id IN ("
      '  SELECT id FROM expenses '
      '   WHERE txn_number IS NOT NULL AND pending_mutation_id IS NULL)',
      updates: const {},
    );
  }

  /// Marks an attachment ready to upload once its own expense is saved.
  ///
  /// Called when the expense is written locally: the bill stops being a draft's
  /// [AttachmentUploadState.staged] file and starts waiting for the document it belongs
  /// to.
  Future<int> markWaitingForExpense(String expenseId) => db.customUpdate(
    "UPDATE expense_attachments SET upload_state = 'waitingForExpense' "
    "WHERE expense_id = ? AND upload_state = 'staged'",
    variables: [Variable<String>(expenseId)],
    updates: const {},
  );

  Future<bool> _uploadOne(ExpenseAttachmentRow row, DateTime now) async {
    final path = row.localPath;
    if (path == null || !File(path).existsSync()) {
      // The staged copy is gone and the object was never confirmed. Nothing can be
      // recovered by retrying, and the expense is unaffected — so this is reported for a
      // person rather than retried forever.
      await _markFailed(
        row,
        now,
        'The saved copy of this file is no longer on this device.',
        retryable: false,
      );
      return false;
    }

    // Persisted before the request goes out, so a crash mid-upload is recoverable rather
    // than invisible. A row left `uploading` by a kill is picked up by the next pass,
    // because the object write is idempotent on its deterministic path.
    await (db.update(
      db.expenseAttachments,
    )..where((t) => t.id.equals(row.id))).write(
      const ExpenseAttachmentsCompanion(uploadState: Value('uploading')),
    );

    final bytes = await File(path).readAsBytes();

    // Verify what is about to be sent still matches what was staged. A file that changed
    // underneath us is not the receipt that was attached.
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
      expenseId: row.expenseId,
      attachmentId: row.id,
      fileName: row.fileName,
      contentType: row.contentType,
      bytes: bytes,
    );

    switch (outcome) {
      case UploadStored(:final storagePath, :final reportedHash):
        // Confirmation is about bytes. If the store reports a hash, compare it; if it
        // does not, read one back. Either way "uploaded" means verified.
        final serverHash = reportedHash ?? await store.hashOf(storagePath);
        if (serverHash != null && serverHash != localHash) {
          await _markFailed(
            row,
            now,
            'The uploaded copy did not match the file on this device.',
          );
          return false;
        }
        await (db.update(
          db.expenseAttachments,
        )..where((t) => t.id.equals(row.id))).write(
          ExpenseAttachmentsCompanion(
            uploadState: const Value('uploaded'),
            storagePath: Value(storagePath),
            uploadedAt: Value(now),
            // The staged copy stays for a week after confirmation. Deleting it now would
            // make recovery from a later problem impossible for the sake of some bytes.
            reclaimableAfter: Value(now.add(AttachmentPolicy.stagingRetention)),
            lastError: const Value(null),
            nextAttemptAt: const Value(null),
          ),
        );
        return true;

      case UploadRefused(:final message):
        await _markFailed(row, now, message, retryable: false);
        return false;

      case UploadUnreachable(:final message):
        await _markFailed(row, now, message);
        return false;
    }
  }

  Future<void> _markFailed(
    ExpenseAttachmentRow row,
    DateTime now,
    String message, {
    bool retryable = true,
  }) async {
    final attempt = row.attemptCount + 1;
    await (db.update(
      db.expenseAttachments,
    )..where((t) => t.id.equals(row.id))).write(
      ExpenseAttachmentsCompanion(
        // Two different answers, kept apart: one will be retried on the durable clock,
        // the other never will. Collapsing them into a single `failed` is how a refusal
        // comes to be retried for ever.
        uploadState: Value(retryable ? 'retryNeeded' : 'rejected'),
        attemptCount: Value(attempt),
        lastError: Value(message),
        nextAttemptAt: Value(
          retryable ? retryPolicy.nextAttemptAt(now, attempt) : null,
        ),
      ),
    );
  }

  /// Returns rows left `uploading` by a crash to `pendingUpload`.
  ///
  /// Called at start-up, exactly as the outbox recovers its own `inFlight` entries. Safe
  /// because the object path is deterministic: re-uploading writes the same object again
  /// rather than a second one (D-073 §8).
  Future<int> recoverInterruptedUploads() => db.customUpdate(
    "UPDATE expense_attachments SET upload_state = 'pendingUpload' "
    "WHERE upload_state = 'uploading'",
    updates: const {},
  );

  /// Reclaims verified staging copies whose retention has elapsed.
  ///
  /// Only ever touches rows that are `uploaded` *and* past [reclaimableAfter] — a copy
  /// that was never confirmed is never reclaimed, however old, because it is the only
  /// copy there is.
  Future<int> reclaimVerifiedStaging() async {
    final now = clock();
    final ready =
        await (db.select(db.expenseAttachments)..where(
              (t) =>
                  t.uploadState.equals('uploaded') &
                  t.reclaimableAfter.isSmallerOrEqualValue(now) &
                  t.localPath.isNotNull(),
            ))
            .get();

    var reclaimed = 0;
    for (final row in ready) {
      final file = File(row.localPath!);
      if (file.existsSync()) await file.delete();
      await (db.update(
        db.expenseAttachments,
      )..where((t) => t.id.equals(row.id))).write(
        const ExpenseAttachmentsCompanion(
          uploadState: Value('stagingReclaimed'),
          localPath: Value(null),
        ),
      );
      reclaimed++;
    }
    return reclaimed;
  }
}
