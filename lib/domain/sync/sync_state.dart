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
  conflict;

  String get label => switch (this) {
    SyncState.synced => 'Synced',
    SyncState.pendingSync => 'Pending Sync',
    SyncState.syncing => 'Syncing',
    SyncState.syncFailed => 'Sync Failed',
    SyncState.conflict => 'Conflict / Attention Required',
  };

  /// Whether the user must do something. Drives badge prominence, not colour alone.
  bool get needsAttention =>
      this == SyncState.conflict || this == SyncState.syncFailed;
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
  /// Conflicts and auth blocks are deliberately excluded: both need a human, and
  /// retrying them automatically would either overwrite someone's edit or spin
  /// pointlessly against an expired session.
  bool get isAutomaticallyRetryable =>
      this == OutboxStatus.pending || this == OutboxStatus.failed;

  SyncState get userVisibleState => switch (this) {
    OutboxStatus.pending => SyncState.pendingSync,
    OutboxStatus.inFlight => SyncState.syncing,
    OutboxStatus.failed => SyncState.syncFailed,
    OutboxStatus.conflict => SyncState.conflict,
    OutboxStatus.blockedAuth => SyncState.pendingSync,
    OutboxStatus.done => SyncState.synced,
  };
}
