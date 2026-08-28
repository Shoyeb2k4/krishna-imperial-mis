/// The synchronisation states a record can be in, exactly as the user sees them.
///
/// Master spec §22. These five values are the whole vocabulary — no screen invents its
/// own wording, and no state is hidden from the user.
library;

enum SyncState {
  /// Local and server agree. Nothing outstanding.
  synced,

  /// Saved locally and queued. It exists, it counts, it is not on the server yet.
  pendingSync,

  /// Currently being pushed.
  syncing,

  /// The push failed. The reason is shown and a manual retry is offered; the entry is
  /// never dropped.
  syncFailed,

  /// The server rejected the change because it was based on a stale version. A human
  /// must choose — nothing is overwritten silently (docs/DECISIONS.md D-021).
  conflict,

  /// The server refused the change outright, on its own current authority or state:
  /// the permission or business-unit scope that allowed it to be queued no longer
  /// exists, or the period it touches has since been closed (D-048 §2).
  ///
  /// The label stays general because the *reason* is specific and comes from the
  /// server's own refusal — "You do not have permission to do this for this business
  /// unit", "This period has been closed" — and that sentence is what the user reads.
  /// A state label that guessed which of them applied would sometimes be wrong.
  ///
  /// Distinct from [conflict], which is about the *record* moving, and from
  /// [syncFailed], which is about the *transport* and retries on its own. This one is
  /// settled: repeating the request cannot change the answer. The attempt is kept and
  /// stays inspectable — it is never dropped, never marked synced, and never retried in
  /// a loop against an answer the server has already given.
  rejected;

  String get label => switch (this) {
    SyncState.synced => 'Synced',
    SyncState.pendingSync => 'Pending Sync',
    SyncState.syncing => 'Syncing',
    SyncState.syncFailed => 'Sync Failed',
    SyncState.conflict => 'Conflict / Attention Required',
    SyncState.rejected => 'Rejected — needs attention',
  };

  /// Whether the user must do something. Drives badge prominence, not colour alone.
  bool get needsAttention =>
      this == SyncState.conflict ||
      this == SyncState.syncFailed ||
      this == SyncState.rejected;

  /// Whether the record is on the server. Deliberately false for [rejected]: the user
  /// attempted something, the server declined, and showing that as synchronised would be
  /// a lie about company data.
  bool get isOnServer => this == SyncState.synced;
}

/// The lifecycle of a queued mutation inside the local outbox.
///
/// Distinct from [SyncState]: this is the queue's own bookkeeping, one level below what
/// the user is shown.
enum OutboxStatus {
  /// Waiting for its next attempt window.
  pending,

  /// Handed to the transport; the outcome is not yet known.
  inFlight,

  /// A transient failure. Will be retried on the backoff schedule.
  failed,

  /// Rejected for a stale base version. Requires a human decision; never auto-retried.
  conflict,

  /// Refused by the server under its current authority: the capability or the
  /// business-unit scope was withdrawn between queueing and delivery. Terminal — the
  /// entry is kept for inspection and never retried automatically (D-048 §2).
  rejected,

  /// The session expired and could not be refreshed. The queue is paused, not drained:
  /// no entry is dropped and no attempt counter burns (docs/ARCHITECTURE.md §5.1).
  blockedAuth,

  /// Applied by the server and confirmed. Retained briefly for diagnostics, then purged.
  done;

  static OutboxStatus fromName(String value) => OutboxStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'unknown outbox status'),
  );

  /// Whether the sync worker may pick this entry up on its own.
  ///
  /// Conflicts, rejections and auth blocks are deliberately excluded: each needs a
  /// human, and retrying them automatically would either overwrite someone's edit, spin
  /// pointlessly against an expired session, or hammer the server with a request it has
  /// already refused on authority it is not going to change its mind about.
  bool get isAutomaticallyRetryable =>
      this == OutboxStatus.pending || this == OutboxStatus.failed;

  SyncState get userVisibleState => switch (this) {
    OutboxStatus.pending => SyncState.pendingSync,
    OutboxStatus.inFlight => SyncState.syncing,
    OutboxStatus.failed => SyncState.syncFailed,
    OutboxStatus.conflict => SyncState.conflict,
    OutboxStatus.rejected => SyncState.rejected,
    OutboxStatus.blockedAuth => SyncState.pendingSync,
    OutboxStatus.done => SyncState.synced,
  };
}
