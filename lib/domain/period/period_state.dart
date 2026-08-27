/// Accounting period locking (master spec §13.4).
///
/// Once a period is closed, financial transactions inside it are immutable to normal
/// users. Only the Owner may reopen it, deliberately, with a reason, and the event is
/// audited. **No code path reopens a period implicitly** — there is no auto-unlock, no
/// cascade, and no silent bypass anywhere in this file or the ones that use it.
library;

import 'package:meta/meta.dart';

enum PeriodState { open, closed }

/// A lock over one `YYYY-MM` period, either for one business unit or for all of them.
@immutable
final class PeriodLock {
  const PeriodLock({
    required this.periodKey,
    required this.state,
    this.businessUnitId,
    this.closedBy,
    this.closedAt,
    this.reopenedBy,
    this.reopenedAt,
    this.reopenReason,
  });

  final String periodKey;

  /// Null means the lock applies to every business unit.
  final String? businessUnitId;

  final PeriodState state;
  final String? closedBy;
  final DateTime? closedAt;
  final String? reopenedBy;
  final DateTime? reopenedAt;
  final String? reopenReason;

  bool get isClosed => state == PeriodState.closed;

  bool appliesTo(String unitId) =>
      businessUnitId == null || businessUnitId == unitId;

  PeriodLock closedByActor(String actorId, DateTime at) => PeriodLock(
    periodKey: periodKey,
    businessUnitId: businessUnitId,
    state: PeriodState.closed,
    closedBy: actorId,
    closedAt: at,
  );

  /// Reopening always carries an actor, a timestamp and a reason. The reason is not
  /// optional and not defaulted: it is what makes the audit trail answer "why".
  PeriodLock reopenedByActor(String actorId, DateTime at, String reason) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'a reopen reason is required',
      );
    }
    return PeriodLock(
      periodKey: periodKey,
      businessUnitId: businessUnitId,
      state: PeriodState.open,
      closedBy: closedBy,
      closedAt: closedAt,
      reopenedBy: actorId,
      reopenedAt: at,
      reopenReason: reason,
    );
  }

  @override
  String toString() =>
      'PeriodLock($periodKey, ${businessUnitId ?? 'all-units'}, ${state.name})';
}

/// Answers "is this period writable?" for the authoriser.
///
/// An org-wide lock and a unit lock can both exist; **either** closing the period closes
/// it. The permissive reading — requiring both — would let a unit-level reopen quietly
/// defeat an org-wide close.
abstract interface class PeriodRegistry {
  PeriodState stateFor({
    required String periodKey,
    required String businessUnitId,
  });
}

/// A registry over a known set of locks. Anything not locked is open.
final class InMemoryPeriodRegistry implements PeriodRegistry {
  InMemoryPeriodRegistry(Iterable<PeriodLock> locks) : _locks = List.of(locks);

  /// Nothing closed. The state before any period has ever been reviewed.
  factory InMemoryPeriodRegistry.allOpen() => InMemoryPeriodRegistry(const []);

  final List<PeriodLock> _locks;

  @override
  PeriodState stateFor({
    required String periodKey,
    required String businessUnitId,
  }) {
    for (final lock in _locks) {
      if (lock.periodKey == periodKey &&
          lock.appliesTo(businessUnitId) &&
          lock.isClosed) {
        return PeriodState.closed;
      }
    }
    return PeriodState.open;
  }

  /// All locks covering a unit, most specific first. For the administration screen.
  List<PeriodLock> locksFor(String businessUnitId) => [
    for (final lock in _locks)
      if (lock.appliesTo(businessUnitId)) lock,
  ];
}

/// A close or reopen, as written to the append-only `period_lock_events` table.
@immutable
final class PeriodLockEvent {
  const PeriodLockEvent({
    required this.periodKey,
    required this.action,
    required this.actorId,
    required this.occurredAt,
    this.businessUnitId,
    this.reason,
  });

  final String periodKey;
  final String? businessUnitId;
  final PeriodLockAction action;
  final String actorId;
  final DateTime occurredAt;

  /// Mandatory for a reopen; optional for a close.
  final String? reason;
}

enum PeriodLockAction { close, reopen }
