/// The unit of work the sync engine pushes: one user intent, once.
///
/// Idempotency and concurrency are **two separate mechanisms** and this file keeps them
/// visibly apart (docs/DECISIONS.md D-021):
///
///  * [PendingMutation.mutationId] answers "have I already applied *this exact intent*?"
///    It is generated once, when the user saves, and reused for every retry forever.
///  * [PendingMutation.baseRowVersion] answers "is this intent still based on current
///    state?" A mismatch is a conflict and is refused.
library;

import 'package:meta/meta.dart';

/// The kind of state change being requested.
enum MutationOp {
  /// A new record. Cannot conflict — the identity is new and client-generated.
  create,

  /// An edit to an existing record. Requires [PendingMutation.baseRowVersion].
  update,

  /// Voiding a financial document. **Also requires a base version**: a void issued from
  /// a stale view must not silently void someone else's newer edit.
  void_,

  /// Correcting a derived business date. Privileged, audited, version-checked.
  correctBusinessDate,

  /// Archiving a master record. Version-checked.
  archive;

  static MutationOp fromName(String value) => MutationOp.values.firstWhere(
    (op) => op.name == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'unknown mutation op'),
  );

  /// Whether the server must validate the caller's base version before applying.
  ///
  /// Only [create] is exempt, and only because it establishes a new identity rather
  /// than changing existing state.
  bool get requiresBaseRowVersion => this != MutationOp.create;
}

/// One queued intent, exactly as it will be sent to the server.
@immutable
final class PendingMutation {
  PendingMutation({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.createdAt,
    this.baseRowVersion,
    this.attemptCount = 0,
  }) {
    if (op.requiresBaseRowVersion && baseRowVersion == null) {
      throw ArgumentError(
        'A ${op.name} mutation must carry baseRowVersion: without it the server '
        'cannot tell a current intent from a stale one (D-021).',
      );
    }
    if (op == MutationOp.create && baseRowVersion != null) {
      throw ArgumentError(
        'A create mutation must not carry baseRowVersion: it establishes a new '
        'identity and has no prior version to be based on.',
      );
    }
  }

  /// Generated once per user intent and **never re-rolled on retry**. This is the whole
  /// duplicate-prevention guarantee: a duplicate delivery, a crash after send and a
  /// timeout-then-retry all carry the same id and collapse to one financial record.
  final String mutationId;

  /// `expense` | `revenue_entry` | `vendor` | …
  final String entityType;
  final String entityId;
  final MutationOp op;

  /// The full canonical document, including allocation lines, as JSON.
  final Map<String, Object?> payload;

  /// The version this intent was based on. Null only for [MutationOp.create].
  final int? baseRowVersion;

  final DateTime createdAt;
  final int attemptCount;

  PendingMutation copyWith({int? attemptCount}) => PendingMutation(
    mutationId: mutationId,
    entityType: entityType,
    entityId: entityId,
    op: op,
    payload: payload,
    createdAt: createdAt,
    baseRowVersion: baseRowVersion,
    attemptCount: attemptCount ?? this.attemptCount,
  );

  @override
  bool operator ==(Object other) =>
      other is PendingMutation && other.mutationId == mutationId;

  @override
  int get hashCode => mutationId.hashCode;

  @override
  String toString() =>
      'PendingMutation($mutationId, ${op.name} $entityType/$entityId, '
      'base=$baseRowVersion, attempts=$attemptCount)';
}

/// What the server did with one mutation.
enum MutationOutcome {
  /// Applied for the first time.
  applied,

  /// The server had already processed this `mutation_id` and replayed the stored
  /// result. **Not an error** — this is the idempotency guarantee working. Exactly one
  /// financial record exists.
  duplicateIgnored,

  /// Rejected: the intent was based on a version the server has since moved past.
  /// A human resolves it; nothing was changed.
  conflict,

  /// Rejected: the affected period is closed. Distinct from [conflict] so the user can
  /// be told the real reason rather than a misleading "someone else edited this".
  periodClosed,

  /// Rejected: the caller lacks the capability or business-unit scope.
  notPermitted,

  /// The session expired. The queue pauses; nothing is dropped.
  authExpired,

  /// Network or server trouble. Retry on the backoff schedule.
  transientFailure,
}

@immutable
final class MutationResult {
  const MutationResult({
    required this.mutationId,
    required this.outcome,
    this.rowVersion,
    this.serverUpdatedAt,
    this.message,
  });

  final String mutationId;
  final MutationOutcome outcome;

  /// The authoritative version after the write, echoed back so the client can store it
  /// and base its next edit on it.
  final int? rowVersion;
  final DateTime? serverUpdatedAt;
  final String? message;

  /// Whether the local record can now be marked Synced.
  ///
  /// A duplicate replay counts as success: the server holds exactly the record this
  /// intent asked for.
  bool get isSuccess =>
      outcome == MutationOutcome.applied ||
      outcome == MutationOutcome.duplicateIgnored;

  @override
  String toString() =>
      'MutationResult($mutationId, ${outcome.name}, v$rowVersion)';
}

/// The transport the sync engine pushes through.
///
/// Deliberately narrow, and deliberately not Supabase-shaped: Phase 1 exercises the
/// whole queue against a fake implementation, long before any backend exists.
abstract interface class RemoteMutationEndpoint {
  /// Pushes a batch. Implementations must preserve one result per mutation, keyed by
  /// `mutationId`, so partial batch outcomes are representable.
  Future<List<MutationResult>> push(List<PendingMutation> mutations);
}
