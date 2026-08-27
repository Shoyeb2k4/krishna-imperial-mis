/// The one place a financial write is authorised.
///
/// Authorisation is never a single question. It depends on all five of:
///
///   user · capability · business-unit scope · record state · period state
///
/// Scattering those checks would guarantee that some path eventually forgets one. They
/// are therefore decided here, in order, and everything else — UI, repositories, the sync
/// push path — asks this and obeys the answer. The client's answer shapes the UI only;
/// the server re-runs the identical rules and is the authority (master spec §13.1).
library;

import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/period/period_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:meta/meta.dart';

/// Why a request was refused. Each maps to a message that tells the user the *real*
/// reason, so a closed period never masquerades as a permissions problem.
enum DenialReason {
  missingCapability,
  outOfUnitScope,
  notRecordOwner,
  recordVoided,
  periodClosed,
  outsideEditWindow,
}

@immutable
sealed class AuthorizationDecision {
  const AuthorizationDecision();

  const factory AuthorizationDecision.allowed() = Allowed;
  const factory AuthorizationDecision.denied(DenialReason reason) = Denied;

  bool get isAllowed => this is Allowed;

  /// Throws when refused. For call sites where proceeding would be a defect.
  void enforce() {
    if (this case final Denied denied) {
      throw AuthorizationFailure(denied.reason, denied.message);
    }
  }
}

final class Allowed extends AuthorizationDecision {
  const Allowed();
  @override
  String toString() => 'Allowed';
}

final class Denied extends AuthorizationDecision {
  const Denied(this.reason);

  final DenialReason reason;

  /// Plain language, aimed at the manager rather than the developer.
  String get message => switch (reason) {
    DenialReason.missingCapability => 'You do not have permission to do this.',
    DenialReason.outOfUnitScope =>
      'You do not have permission to do this for this business unit.',
    DenialReason.notRecordOwner =>
      'You can only change entries you created yourself.',
    DenialReason.recordVoided =>
      'This entry has been voided and can no longer be changed. '
          'Record a new entry instead.',
    DenialReason.periodClosed =>
      'This period has been closed. The owner must reopen it before it can be changed.',
    DenialReason.outsideEditWindow =>
      'The edit window for this entry has passed. Ask an accountant or the owner to '
          'make the correction.',
  };

  @override
  String toString() => 'Denied(${reason.name})';
}

class AuthorizationFailure implements Exception {
  const AuthorizationFailure(this.reason, this.message);
  final DenialReason reason;
  final String message;

  @override
  String toString() => 'AuthorizationFailure(${reason.name}): $message';
}

/// The state of the record being acted on. Absent for a create.
@immutable
final class RecordContext {
  const RecordContext({
    required this.createdByUserId,
    required this.businessDate,
    this.isVoided = false,
  });

  final String createdByUserId;

  /// Drives the edit window. Deliberately the *business* date, not the capture instant:
  /// an entry recorded late for an earlier trading day gets the window of the day it
  /// belongs to, not the day it was typed.
  final BusinessDate businessDate;

  final bool isVoided;
}

/// Ordinary edit-window length. Configuration, not a constant in code — the value comes
/// from `org_settings.edit_window_days` and this is only the seeded default (spec §13.3).
const int defaultEditWindowDays = 7;

class Authorizer {
  const Authorizer({
    required this.periodRegistry,
    this.editWindowDays = defaultEditWindowDays,
  });

  final PeriodRegistry periodRegistry;
  final int editWindowDays;

  /// Authorises creating a new record.
  ///
  /// There is no record state yet, but the period still governs: back-dating an entry
  /// into a closed month is exactly as prohibited as editing one that is already there.
  AuthorizationDecision authorizeCreate({
    required Principal principal,
    required Capability capability,
    required String businessUnitId,
    required BusinessDate businessDate,
  }) {
    final permission = _checkCapability(principal, capability, businessUnitId);
    if (permission != null) return permission;

    return _checkPeriod(
          businessDate: businessDate,
          businessUnitId: businessUnitId,
        ) ??
        const AuthorizationDecision.allowed();
  }

  /// Authorises changing an existing record: edit, void, or business-date correction.
  ///
  /// Check order is deliberate, so the user is told the most useful truth first:
  /// permission → ownership → record state → period → edit window. Someone with no
  /// permission at all should not learn about period state, and a voided record is
  /// immutable regardless of anything else.
  AuthorizationDecision authorizeMutation({
    required Principal principal,
    required Capability capability,
    required String businessUnitId,
    required RecordContext record,
    required BusinessDate today,
    Capability? ownScopedCapability,
  }) {
    final holdsAll = principal.can(capability, businessUnitId: businessUnitId);
    final holdsOwn =
        ownScopedCapability != null &&
        principal.can(ownScopedCapability, businessUnitId: businessUnitId);

    if (!holdsAll && !holdsOwn) {
      return AuthorizationDecision.denied(
        principal.canAnywhere(capability) ||
                (ownScopedCapability != null &&
                    principal.canAnywhere(ownScopedCapability))
            ? DenialReason.outOfUnitScope
            : DenialReason.missingCapability,
      );
    }

    // Holding only the own-scoped form limits the user to their own entries.
    if (!holdsAll && holdsOwn && record.createdByUserId != principal.userId) {
      return const AuthorizationDecision.denied(DenialReason.notRecordOwner);
    }

    if (record.isVoided) {
      return const AuthorizationDecision.denied(DenialReason.recordVoided);
    }

    final period = _checkPeriod(
      businessDate: record.businessDate,
      businessUnitId: businessUnitId,
    );
    if (period != null) return period;

    final daysElapsed = today.differenceInDays(record.businessDate);
    if (daysElapsed > editWindowDays &&
        !principal.can(
          Capability.correctBeyondWindow,
          businessUnitId: businessUnitId,
        )) {
      return const AuthorizationDecision.denied(DenialReason.outsideEditWindow);
    }

    return const AuthorizationDecision.allowed();
  }

  /// Authorises one leg of a cross-period allocation (D-034).
  ///
  /// Each target period is checked **separately**: a split that reaches into a closed
  /// month is refused exactly like any other write into it.
  AuthorizationDecision authorizePeriodAllocation({
    required Principal principal,
    required String businessUnitId,
    required String periodKey,
  }) {
    final permission = _checkCapability(
      principal,
      Capability.expenseAllocatePeriods,
      businessUnitId,
    );
    if (permission != null) return permission;

    if (periodRegistry.stateFor(
          periodKey: periodKey,
          businessUnitId: businessUnitId,
        ) ==
        PeriodState.closed) {
      return const AuthorizationDecision.denied(DenialReason.periodClosed);
    }
    return const AuthorizationDecision.allowed();
  }

  /// Closing and reopening are themselves capability-gated. Reopening additionally
  /// demands a reason, which the caller must supply — enforced here so no path can
  /// reopen a period silently (spec §13.4).
  AuthorizationDecision authorizePeriodClose({
    required Principal principal,
    required String businessUnitId,
  }) =>
      _checkCapability(principal, Capability.periodClose, businessUnitId) ??
      const AuthorizationDecision.allowed();

  AuthorizationDecision authorizePeriodReopen({
    required Principal principal,
    required String businessUnitId,
    required String reason,
  }) {
    final permission = _checkCapability(
      principal,
      Capability.periodReopen,
      businessUnitId,
    );
    if (permission != null) return permission;
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'reopening a closed period requires a reason; it is written to the audit trail',
      );
    }
    return const AuthorizationDecision.allowed();
  }

  AuthorizationDecision? _checkCapability(
    Principal principal,
    Capability capability,
    String businessUnitId,
  ) {
    if (principal.can(capability, businessUnitId: businessUnitId)) return null;
    // Distinguish "you cannot do this at all" from "not for this property" — the second
    // is actionable and the first is not.
    return AuthorizationDecision.denied(
      principal.canAnywhere(capability)
          ? DenialReason.outOfUnitScope
          : DenialReason.missingCapability,
    );
  }

  AuthorizationDecision? _checkPeriod({
    required BusinessDate businessDate,
    required String businessUnitId,
  }) {
    final state = periodRegistry.stateFor(
      periodKey: businessDate.periodKey,
      businessUnitId: businessUnitId,
    );
    return state == PeriodState.closed
        ? const AuthorizationDecision.denied(DenialReason.periodClosed)
        : null;
  }
}
