/// Supporting evidence for a financial document, and where its bytes currently are.
///
/// This library was extracted from `domain/expenses/expense.dart` in Phase 4 Slice 11,
/// unchanged in substance. Nothing in it was ever about expenses: a lifecycle, a size
/// policy and a file record are the same three things whether the document they support
/// is a bill or a day's takings. Copying them for revenue would have produced a second
/// definition of a lifecycle this project has already paid to get right once (D-073), and
/// the two would have drifted — which is the failure D-119 records for a duplicated
/// `switch` and D-131 for a duplicated join.
///
/// **What an attachment is, and what it is not.** It is evidence *for* a document. It is
/// never a financial source of truth: no total, no tax figure and no reporting
/// contribution is derived from it, and adding or losing one changes no amount. The
/// canonical record that a document *has* evidence is a row in Postgres, not an object in
/// a bucket (spec §23).
library;

/// Which kind of financial document an attachment supports.
///
/// One enum rather than a boolean, because three genuinely different strings hang off it —
/// the noun a refusal message uses, the segment of the storage path, and the sync entity
/// type — and a boolean would have each of them spelled out at its own call site.
enum AttachmentOwnerKind {
  expense,
  sale;

  /// What to call the document when speaking to the person who attached the file.
  String get noun => switch (this) {
    AttachmentOwnerKind.expense => 'expense',
    AttachmentOwnerKind.sale => 'sale',
  };

  /// The segment of the deterministic object path that says which document this is.
  ///
  /// `expenses` is what every object written since D-073a already uses, and it is not
  /// changed: an object path is where bytes actually live, and renaming it would strand
  /// every bill already uploaded. `revenue` is the new one.
  String get storageSegment => switch (this) {
    AttachmentOwnerKind.expense => 'expenses',
    AttachmentOwnerKind.sale => 'revenue',
  };
}

/// One durable state per attachment, persisted, and the only place its lifecycle is
/// written down (D-073 §3).
///
/// Deliberately not a set of booleans. `isUploading && !isUploaded && hasError` is four
/// bits describing eight states, six of which are nonsense, and the two that matter —
/// "waiting for its document" and "refused permanently" — cannot be told apart at all.
///
/// The order below is the order a file actually moves through:
///
/// ```
///   staged ─▶ waitingForExpense ─▶ pendingUpload ─▶ uploading ─▶ uploaded
///                                        ▲              │
///                                        └─ retryNeeded ┘   └─▶ rejected
///                                                                  (terminal)
/// ```
///
/// **`waitingForExpense` keeps its name for both document kinds, deliberately.** It means
/// *the parent financial document has not been accepted by the server yet*, and it is
/// named for the first document that needed it. The identifier is the value stored in
/// `upload_state` on every device already in the field and is named by two SQLite check
/// constraints, so renaming it would be a data migration of live expense rows for no
/// behavioural gain. D-104's lesson is to pin a wire name, not to churn one.
enum AttachmentUploadState {
  /// Copied into app-private storage and hashed. The document it belongs to has not been
  /// saved yet, so there is nothing to attach it to.
  staged,

  /// The document is saved locally and queued, and the server has not accepted it.
  ///
  /// **Not uploadable yet, and this is a rule rather than an optimisation.** The Storage
  /// write policy calls the parent document's read predicate, which requires the document
  /// to exist canonically — so an upload attempted now would be refused for a reason that
  /// looks like a permission problem and is really an ordering one (D-073 §2).
  waitingForExpense,

  /// The server has accepted the document. The file is eligible to be uploaded.
  pendingUpload,

  /// An upload is in flight. Persisted so a crash mid-upload is recoverable rather than
  /// invisible.
  uploading,

  /// On the server, hash-verified against the local copy, and recorded as canonical
  /// metadata in Postgres. All three, or it is not `uploaded`.
  uploaded,

  /// Uploaded, verified, and the full-resolution local staging copy has been reclaimed.
  /// The canonical copy is the server's; a thumbnail may still be cached locally.
  stagingReclaimed,

  /// A transient failure. Carries a `nextAttemptAt`, and will be retried on the durable
  /// backoff clock.
  retryNeeded,

  /// A terminal refusal — the server declined, or the local copy is gone or changed.
  /// **Never retried automatically**, and deliberately carries no `nextAttemptAt`, because
  /// a null there once meant "due now" and retried a refusal for ever.
  rejected;

  static AttachmentUploadState fromName(String value) =>
      AttachmentUploadState.values.firstWhere(
        (s) => s.name == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'unknown attachment upload state',
        ),
      );

  bool get isOnServer =>
      this == AttachmentUploadState.uploaded ||
      this == AttachmentUploadState.stagingReclaimed;

  /// Whether the upload worker may pick this row up.
  ///
  /// `staged` is excluded because there is no document yet; `waitingForExpense` because
  /// the server has not accepted it; `rejected` because it is terminal. The two that are
  /// due are the two that are ready.
  bool get isUploadable =>
      this == AttachmentUploadState.pendingUpload ||
      this == AttachmentUploadState.retryNeeded;

  /// Whether this state means the bytes still exist only on this device.
  bool get isLocalOnly => !isOnServer;

  /// Whether a person needs to do something about it.
  bool get needsAttention =>
      this == AttachmentUploadState.retryNeeded ||
      this == AttachmentUploadState.rejected;

  /// What the interface says about it, in words a manager can act on.
  ///
  /// [owner] only affects the one state that names the document it is waiting for. Every
  /// other word is the same, because the lifecycle is.
  String labelFor(AttachmentOwnerKind owner) => switch (this) {
    AttachmentUploadState.staged => 'Attached',
    AttachmentUploadState.waitingForExpense => 'Waiting for the ${owner.noun}',
    AttachmentUploadState.pendingUpload => 'Pending upload',
    AttachmentUploadState.uploading => 'Uploading',
    AttachmentUploadState.uploaded => 'Uploaded',
    AttachmentUploadState.stagingReclaimed => 'Uploaded',
    AttachmentUploadState.retryNeeded => 'Retry needed',
    AttachmentUploadState.rejected => 'Not accepted',
  };

  /// The expense wording, kept because it is what every existing expense surface reads.
  String get label => labelFor(AttachmentOwnerKind.expense);
}

/// The approved attachment limits (project-lead decision, 2026-08-29).
///
/// **One policy for both document kinds.** Revenue invents no limit of its own: a
/// different maximum size for a Z report than for an invoice would be a business rule
/// nobody decided, and the server enforces these same numbers at the boundary whatever
/// the client believes.
abstract final class AttachmentPolicy {
  static const int maxPerDocument = 5;

  /// Images are optimised on the way in, targeting this size while staying legible as an
  /// invoice, receipt or till report. It is a target, not a hard rejection: a genuinely
  /// detailed document that will not compress below it is still worth keeping.
  static const int imageTargetBytes = 2500 * 1024;

  /// Documents are not re-encoded, so this one is a limit.
  static const int maxDocumentBytes = 10 * 1024 * 1024;

  /// Across all attachments on one financial document.
  static const int maxTotalBytesPerDocument = 25 * 1024 * 1024;

  /// How long a verified local staging copy is kept before it may be reclaimed.
  ///
  /// Only ever after the server has confirmed the upload *and* the content hash matched.
  /// An unverified copy is never reclaimed, however old.
  static const Duration stagingRetention = Duration(days: 7);
}

/// One attachment, and where its bytes currently are.
///
/// Identical for an expense and for a sale, which is why there is one class. The document
/// it belongs to is named by the row that stores it, not by the type.
final class DocumentAttachment {
  const DocumentAttachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.byteSize,
    required this.contentHash,
    required this.uploadState,
    this.storagePath,
    this.localStagingPath,
  });

  final String id;
  final String fileName;
  final String contentType;
  final int byteSize;

  /// SHA-256 of the staged bytes. The upload is confirmed only when the server reports
  /// the same hash — "the request returned 200" is not the same claim.
  final String contentHash;

  final AttachmentUploadState uploadState;
  final String? storagePath;
  final String? localStagingPath;

  bool get isImage => contentType.startsWith('image/');

  DocumentAttachment copyWith({
    AttachmentUploadState? uploadState,
    String? storagePath,
    String? localStagingPath,
    bool clearLocalStagingPath = false,
  }) => DocumentAttachment(
    id: id,
    fileName: fileName,
    contentType: contentType,
    byteSize: byteSize,
    contentHash: contentHash,
    uploadState: uploadState ?? this.uploadState,
    storagePath: storagePath ?? this.storagePath,
    localStagingPath: clearLocalStagingPath
        ? null
        : (localStagingPath ?? this.localStagingPath),
  );
}
