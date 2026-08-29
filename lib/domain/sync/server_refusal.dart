/// What the server said no to, and what the user should be told about it.
///
/// Postgres refuses with a distinct `SQLSTATE` and a machine-readable JSON `DETAIL`
/// carrying a stable `code` (`supabase/README.md`). Those codes are a contract, not an
/// implementation detail — but a raw `KM005` or a PostgREST error body is not something
/// to put in front of a manager.
///
/// So the mapping lives here, once. Two rules govern it:
///
///  * **A refusal keeps its real reason.** A closed period must never surface as a
///    permissions problem, and a stale version must never surface as a closed period.
///    The server already distinguishes them; throwing that away at the client boundary
///    would waste the whole design.
///  * **The original code survives for diagnostics.** [ServerRefusal.code] is kept so a
///    support log can say exactly what happened, while [message] stays in plain language.
library;

import 'package:meta/meta.dart';

/// The refusals Phase 2 can produce, in the vocabulary the application reasons about.
enum RefusalKind {
  /// No permission at all — `KM001`.
  missingCapability,

  /// Permission, but not for this property — `KM002`.
  outOfUnitScope,

  /// The record moved since it was read — `KM003`.
  versionConflict,

  /// The accounting period is closed — `KM004`.
  periodClosed,

  /// D-039: live children block the archive — `KM005`.
  hasActiveChildren,

  /// The record, or its parent, is archived — `KM006`.
  archivedRecord,

  /// A tax period collision or an impossible range — `KM007`.
  taxPeriodProblem,

  /// Reopening a period demands a reason — `KM008`.
  reasonRequired,

  /// A permanent code cannot change, or was malformed — `KM009`.
  immutableCode,

  /// The structure asked for cannot exist — `KM010`.
  hierarchyViolation,

  /// Not signed in, or the account was deactivated — `KM011`.
  notAuthenticated,

  /// A name is required, or already taken — `KM012`.
  nameProblem,

  /// The record does not exist — `KM015`.
  unknownEntity,

  /// Audit and event rows are written once — `KM016`.
  appendOnly,

  /// D-038: the rename touches recorded history — `KM017`.
  acknowledgementRequired,

  /// The allocation lines do not add up to the expense total — `KM018`.
  allocationImbalance,

  /// An accounting-period split does not add up to its line — `KM019`.
  periodImbalance,

  /// The document has been voided and is immutable — `KM020`.
  recordVoided,

  /// The entry is older than the edit window and the caller cannot correct beyond it —
  /// `KM021`.
  editWindowExpired,

  /// The transport failed, or the server said something this version does not know.
  unrecognised;

  /// Whether a queued mutation carrying this refusal may be retried automatically.
  ///
  /// Almost nothing may. A refusal is the server's considered answer, and repeating the
  /// identical request cannot change it — it can only spin. Every one of these needs a
  /// person to decide something: acknowledge, re-read, ask for permission, or abandon.
  bool get isAutomaticallyRetryable => false;

  /// Whether the refusal is about **authority** rather than about the record.
  ///
  /// These are the ones that survive a scope change: the user was allowed to queue the
  /// work and is not allowed to complete it (D-048 §2). They are shown differently,
  /// because "you no longer have permission" is a different conversation from
  /// "somebody edited this while you were away".
  bool get isAuthorityRefusal =>
      this == RefusalKind.missingCapability ||
      this == RefusalKind.outOfUnitScope ||
      this == RefusalKind.notAuthenticated;
}

/// One refusal, as the application understands it.
@immutable
final class ServerRefusal implements Exception {
  const ServerRefusal({
    required this.kind,
    required this.code,
    required this.message,
    this.detail = const {},
  });

  final RefusalKind kind;

  /// The stable server code (`has_active_children`, `version_conflict`, …), retained for
  /// diagnostics. Never shown to a manager as-is.
  final String code;

  /// Plain language, aimed at the person who hit it.
  final String message;

  /// The structured payload the server attached — child counts, row versions, the
  /// transaction count behind a D-038 acknowledgement. Lets a screen say something
  /// specific rather than something generic.
  final Map<String, Object?> detail;

  int? get childCount => _int('child_count');
  int? get transactionCount => _int('transaction_count');
  int? get currentRowVersion => _int('current_row_version');
  String? get childKind => detail['child_kind'] as String?;
  String? get entityType => detail['entity_type'] as String?;

  int? _int(String key) => switch (detail[key]) {
    final int value => value,
    final String value => int.tryParse(value),
    _ => null,
  };

  /// Builds a refusal from the code and detail a server error carried.
  ///
  /// An unrecognised code is deliberately **not** treated as success, and not silently
  /// mapped onto the nearest familiar kind either: it becomes [RefusalKind.unrecognised]
  /// with the server's own message, so a newer backend talking to an older client is
  /// visibly odd rather than quietly wrong.
  factory ServerRefusal.fromCode(
    String? code, {
    String? serverMessage,
    Map<String, Object?> detail = const {},
  }) {
    final kind = _kinds[code] ?? RefusalKind.unrecognised;
    return ServerRefusal(
      kind: kind,
      code: code ?? 'unknown',
      message: _message(kind, detail, serverMessage),
      detail: detail,
    );
  }

  static const Map<String, RefusalKind> _kinds = {
    'missing_capability': RefusalKind.missingCapability,
    'unit_scope_required': RefusalKind.missingCapability,
    'unit_scope_not_applicable': RefusalKind.missingCapability,
    'out_of_unit_scope': RefusalKind.outOfUnitScope,
    'version_conflict': RefusalKind.versionConflict,
    'period_closed': RefusalKind.periodClosed,
    'has_active_children': RefusalKind.hasActiveChildren,
    'archived_master': RefusalKind.archivedRecord,
    'archived_parent': RefusalKind.archivedRecord,
    'tax_period_overlap': RefusalKind.taxPeriodProblem,
    'ends_before_it_starts': RefusalKind.taxPeriodProblem,
    'rate_out_of_range': RefusalKind.taxPeriodProblem,
    'reason_required': RefusalKind.reasonRequired,
    'immutable_code': RefusalKind.immutableCode,
    'invalid_code': RefusalKind.immutableCode,
    'hierarchy_violation': RefusalKind.hierarchyViolation,
    'not_authenticated': RefusalKind.notAuthenticated,
    'name_required': RefusalKind.nameProblem,
    'duplicate_name': RefusalKind.nameProblem,
    'unknown_entity': RefusalKind.unknownEntity,
    'invalid_period': RefusalKind.unknownEntity,
    'period_not_closed': RefusalKind.unknownEntity,
    'append_only': RefusalKind.appendOnly,
    'acknowledgement_required': RefusalKind.acknowledgementRequired,
    // Phase 3. Each is its own kind because each is a different conversation with the
    // user: a sum that does not add up, a document that is finished, and an entry that
    // is simply too old for this person to change.
    'allocation_imbalance': RefusalKind.allocationImbalance,
    'period_imbalance': RefusalKind.periodImbalance,
    'record_voided': RefusalKind.recordVoided,
    'edit_window_expired': RefusalKind.editWindowExpired,
  };

  static String _message(
    RefusalKind kind,
    Map<String, Object?> detail,
    String? serverMessage,
  ) => switch (kind) {
    RefusalKind.allocationImbalance =>
      'The amounts charged do not add up to the expense total.',
    RefusalKind.periodImbalance =>
      'The accounting-period split does not add up to its line.',
    RefusalKind.recordVoided =>
      'This expense has been voided and can no longer be changed. To correct '
          'it, record a new one.',
    RefusalKind.editWindowExpired =>
      'This entry is older than the correction window and can no longer be '
          'changed here.',
    RefusalKind.missingCapability => 'You do not have permission to do this.',
    RefusalKind.outOfUnitScope =>
      'You do not have permission to do this for this business unit.',
    RefusalKind.versionConflict =>
      'Someone else changed this record while you were working on it. Review the '
          'current version before applying your change.',
    RefusalKind.periodClosed =>
      'This period has been closed. The owner must reopen it before it can be changed.',
    RefusalKind.hasActiveChildren => _childrenMessage(detail),
    RefusalKind.archivedRecord =>
      'That record has been archived, or sits under one that has. Restore the record '
          'above it first.',
    RefusalKind.taxPeriodProblem =>
      serverMessage ??
          'Another tax rule already covers part of that period for this category.',
    RefusalKind.reasonRequired =>
      'Reopening a closed period requires a reason. It is written to the audit trail.',
    RefusalKind.immutableCode =>
      'The permanent code of a record cannot be changed once it is created.',
    RefusalKind.hierarchyViolation =>
      'That combination of business unit, department, section and category cannot exist.',
    RefusalKind.notAuthenticated =>
      'You are not signed in, or this account has been deactivated.',
    RefusalKind.nameProblem => serverMessage ?? 'That name cannot be used.',
    RefusalKind.unknownEntity => 'That record no longer exists.',
    RefusalKind.appendOnly => 'Audit history cannot be changed.',
    RefusalKind.acknowledgementRequired => _acknowledgementMessage(detail),
    RefusalKind.unrecognised =>
      serverMessage ??
          'The server refused this change for a reason this version of the app does '
              'not recognise. Nothing was changed.',
  };

  static String _childrenMessage(Map<String, Object?> detail) {
    final count = detail['child_count'];
    final kind = detail['child_kind'];
    if (count == null || kind == null) {
      return 'Archive the records underneath this one first.';
    }
    return 'Archive the $count $kind underneath this one first.';
  }

  static String _acknowledgementMessage(Map<String, Object?> detail) {
    final count = detail['transaction_count'];
    final where = count == null
        ? 'recorded transactions'
        : '$count recorded transactions';
    return 'This record is used by $where. Renaming is permitted only when the meaning '
        'is unchanged — correcting a spelling, not re-purposing the record. Confirm '
        'that before the rename can be applied.';
  }

  @override
  String toString() => 'ServerRefusal(${kind.name}/$code): $message';
}
