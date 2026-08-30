/// Who may record, correct and void an expense.
///
/// The general rules — capability, unit scope, record state, period lock, edit window —
/// already live in [Authorizer] and are not restated here. What is here is what an
/// *expense* adds, and each addition exists because an expense can touch more than one
/// property and more than one accounting period at once:
///
///  * **every** business unit it charges must be within scope, not just the first;
///  * **every** accounting period it reports into must be open, not just the document's;
///  * a cross-unit split needs its own capability, over and above holding both scopes;
///  * a deliberate period split needs its own capability;
///  * voiding is finance work, and never available in a closed period.
///
/// None of this is the security boundary. The server re-decides all of it and its answer
/// is final (D-037); this exists so the interface can refuse honestly, offline, before
/// anybody fills in a form they are not allowed to submit.
library;

import 'package:krishna_mis/domain/auth/authorizer.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/period/period_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// The approved void policy (project-lead decision, 2026-08-29).
///
/// Data Entry and Manager cannot void at all — it is not in their capability bundle, so
/// this is a statement of fact about the bundles rather than a second rule. Accountant
/// and the Owner role may void for as long as the period is open, with **no separate age
/// limit**: a three-month-old document in an open period is as correctable as yesterday's.
///
/// Once the period is closed, a void is refused. The route back is the existing audited
/// reopen workflow — an explicit, reasoned, recorded act by the Owner role — and then the
/// void. The period lock is never bypassed, and no capability shortcut around it exists.
abstract final class VoidPolicy {
  static const Capability capability = Capability.expenseVoid;

  /// Voiding is not governed by the edit window.
  ///
  /// The window exists to stop operational users quietly reworking last week's entries.
  /// A void is a different act: it is deliberate, reasoned, audited, and reverses nothing
  /// silently. Gating it on age as well as on the period lock would mean a genuine
  /// correction to an old-but-open month needed a second privilege to undo a mistake
  /// somebody already made.
  static const bool respectsEditWindow = false;

  static const String reasonRequiredMessage =
      'A void always states why. The reason is recorded against the document and cannot '
      'be changed afterwards.';
}

/// What an expense authorisation refused, when the general [Authorizer] would have
/// allowed it.
enum ExpenseDenialReason {
  /// One or more of the units the expense charges is outside this user's scope.
  unitOutsideScope,

  /// The expense charges more than one unit and the user may not do that.
  crossUnitNotPermitted,

  /// The expense splits a line across accounting periods and the user may not do that.
  periodSplitNotPermitted,

  /// One of the accounting periods the expense reports into is closed.
  periodClosed,

  /// A void was attempted with no reason.
  voidReasonMissing;

  String get message => switch (this) {
    ExpenseDenialReason.unitOutsideScope =>
      'This expense charges a business unit you do not have access to.',
    ExpenseDenialReason.crossUnitNotPermitted =>
      'Splitting one expense across business units needs permission you do not have. '
          'Record it against a single business unit, or ask someone in finance.',
    ExpenseDenialReason.periodSplitNotPermitted =>
      'Splitting a cost across accounting periods needs permission you do not have.',
    ExpenseDenialReason.periodClosed =>
      'One of the accounting periods this expense belongs to is closed.',
    ExpenseDenialReason.voidReasonMissing => VoidPolicy.reasonRequiredMessage,
  };
}

/// The answer, with the specific reason when it is no.
sealed class ExpenseDecision {
  const ExpenseDecision();
  const factory ExpenseDecision.allowed() = ExpenseAllowed;
  const factory ExpenseDecision.denied(
    ExpenseDenialReason reason, {
    String? detail,
  }) = ExpenseDenied;

  bool get isAllowed => this is ExpenseAllowed;
}

final class ExpenseAllowed extends ExpenseDecision {
  const ExpenseAllowed();
  @override
  String toString() => 'ExpenseAllowed';
}

final class ExpenseDenied extends ExpenseDecision {
  const ExpenseDenied(this.reason, {this.detail});
  final ExpenseDenialReason reason;

  /// Which unit, or which period. Named so the message can be specific.
  final String? detail;

  String get message =>
      detail == null ? reason.message : '${reason.message} ($detail)';

  @override
  String toString() =>
      'ExpenseDenied(${reason.name}${detail == null ? '' : ', $detail'})';
}

class ExpenseAuthorizer {
  const ExpenseAuthorizer(this.authorizer);

  final Authorizer authorizer;

  /// May this principal record this expense?
  ///
  /// Order matters, as it does everywhere else in this project: scope, then the
  /// privileges the *shape* of the expense demands, then the periods. Somebody with no
  /// scope over a unit learns nothing about whether its months are closed.
  ExpenseDecision authorizeCreate({
    required Principal principal,
    required ExpenseDocument expense,
  }) {
    // 1 · Scope over every unit the expense charges — not merely the first one.
    for (final unit in expense.businessUnitIds) {
      final decision = authorizer.authorizeCreate(
        principal: principal,
        capability: Capability.expenseCreate,
        businessUnitId: unit,
        businessDate: expense.businessDate,
      );
      if (decision is Denied) {
        return ExpenseDecision.denied(
          ExpenseDenialReason.unitOutsideScope,
          detail: unit,
        );
      }
    }

    // 2 · The shape of the expense.
    final shape = _authorizeShape(principal, expense);
    if (shape != null) return shape;

    // 3 · Every accounting period it reports into, checked individually (D-034).
    return _authorizePeriods(principal, expense);
  }

  /// May this principal edit this expense?
  ///
  /// The record's own state, ownership and the edit window are the general
  /// [Authorizer]'s business. What is added is the same three expense-specific checks,
  /// applied to the *edited* shape — because an edit can introduce a cross-unit split or
  /// move a line into a closed month just as easily as a create can.
  ExpenseDecision authorizeEdit({
    required Principal principal,
    required ExpenseDocument expense,
    required RecordContext record,
    required BusinessDate today,
  }) {
    for (final unit in expense.businessUnitIds) {
      final decision = authorizer.authorizeMutation(
        principal: principal,
        capability: principal.canAnywhere(Capability.expenseEditAll)
            ? Capability.expenseEditAll
            : Capability.expenseEditOwn,
        businessUnitId: unit,
        record: record,
        today: today,
      );
      if (decision is Denied) {
        return ExpenseDecision.denied(
          ExpenseDenialReason.unitOutsideScope,
          detail: unit,
        );
      }
    }

    final shape = _authorizeShape(principal, expense);
    if (shape != null) return shape;

    return _authorizePeriods(principal, expense);
  }

  /// May this principal edit this expense, judged from the pieces a reader holds?
  ///
  /// The counterpart of [authorizeVoidOf], and it exists for the same reason: an
  /// interface has to decide whether to *offer* Edit before any draft is built. It
  /// answers only the question about the person — capability, scope, the edit window and
  /// the period lock. Whether the *document* can be edited at all (a scoped share, a
  /// voided record, one the server has not accepted) is a separate question with a
  /// separate answer, because those refusals hold however privileged the reader is.
  ///
  /// Unlike [authorizeEdit] this cannot check the *shape* privileges — a cross-unit
  /// split needs `expense.allocate_cross_unit`, a deliberate period split needs
  /// `expense.allocate_periods` — because the shape is a property of the edited
  /// document, which does not exist yet. Those are checked when the draft is saved, and
  /// again by the server. This is deliberately the weaker, earlier question: *may this
  /// person be shown the button.*
  ExpenseDecision authorizeEditOf({
    required Principal principal,
    required Set<String> businessUnitIds,
    required Set<({String unit, String periodKey})> periods,
    required RecordContext record,
    required BusinessDate today,
  }) {
    for (final unit in businessUnitIds) {
      final decision = authorizer.authorizeMutation(
        principal: principal,
        capability: principal.canAnywhere(Capability.expenseEditAll)
            ? Capability.expenseEditAll
            : Capability.expenseEditOwn,
        businessUnitId: unit,
        record: record,
        today: today,
      );
      if (decision is Denied) {
        return ExpenseDecision.denied(
          ExpenseDenialReason.unitOutsideScope,
          detail: unit,
        );
      }
    }

    for (final period in periods) {
      if (authorizer.periodRegistry.stateFor(
            periodKey: period.periodKey,
            businessUnitId: period.unit,
          ) ==
          PeriodState.closed) {
        return ExpenseDecision.denied(
          ExpenseDenialReason.periodClosed,
          detail: '${period.periodKey} · ${period.unit}',
        );
      }
    }

    return const ExpenseDecision.allowed();
  }

  /// May this principal void this expense, and has a reason been given?
  ///
  /// See [VoidPolicy]. The edit window does not apply; the period lock absolutely does,
  /// on **every** period the expense reports into, and it is never bypassed.
  ExpenseDecision authorizeVoid({
    required Principal principal,
    required ExpenseDocument expense,
    required RecordContext record,
    required BusinessDate today,
    required String? reason,
  }) => authorizeVoidOf(
    principal: principal,
    businessUnitIds: expense.businessUnitIds,
    periods: {
      for (final line in expense.allocations)
        for (final part in line.periodContributions)
          (unit: line.businessUnitId, periodKey: part.periodKey),
    },
    record: record,
    today: today,
    reason: reason,
  );

  /// The same decision, from the pieces rather than the whole aggregate.
  ///
  /// A scoped reader legitimately cannot build an [ExpenseDocument] — they do not have
  /// the document total — but they can still be told whether Void would be permitted, so
  /// the interface can decide whether to offer it. Same rules, same order, one
  /// implementation.
  ExpenseDecision authorizeVoidOf({
    required Principal principal,
    required Set<String> businessUnitIds,
    required Set<({String unit, String periodKey})> periods,
    required RecordContext record,
    required BusinessDate today,
    required String? reason,
  }) {
    for (final unit in businessUnitIds) {
      final decision = authorizer.authorizeMutation(
        principal: principal,
        capability: VoidPolicy.capability,
        businessUnitId: unit,
        record: record,
        today: today,
        // A void is deliberate, reasoned and audited; age is not the constraint the
        // period lock already is.
        ignoreEditWindow: !VoidPolicy.respectsEditWindow,
      );
      if (decision is Denied) {
        return ExpenseDecision.denied(
          ExpenseDenialReason.unitOutsideScope,
          detail: unit,
        );
      }
    }

    for (final period in periods) {
      if (authorizer.periodRegistry.stateFor(
            periodKey: period.periodKey,
            businessUnitId: period.unit,
          ) ==
          PeriodState.closed) {
        return ExpenseDecision.denied(
          ExpenseDenialReason.periodClosed,
          detail: '${period.periodKey} · ${period.unit}',
        );
      }
    }

    if (reason == null || reason.trim().isEmpty) {
      return const ExpenseDecision.denied(
        ExpenseDenialReason.voidReasonMissing,
      );
    }
    return const ExpenseDecision.allowed();
  }

  /// The two privileges the shape of an expense can demand.
  ExpenseDecision? _authorizeShape(
    Principal principal,
    ExpenseDocument expense,
  ) {
    if (expense.isCrossUnit &&
        !expense.businessUnitIds.every(
          (unit) => principal.can(
            Capability.expenseAllocateCrossUnit,
            businessUnitId: unit,
          ),
        )) {
      return const ExpenseDecision.denied(
        ExpenseDenialReason.crossUnitNotPermitted,
      );
    }

    if (expense.hasDeliberatePeriodSplit &&
        !principal.canAnywhere(Capability.expenseAllocatePeriods)) {
      return const ExpenseDecision.denied(
        ExpenseDenialReason.periodSplitNotPermitted,
      );
    }

    return null;
  }

  /// Every (unit, period) pair the expense touches, checked one at a time.
  ///
  /// A ₹60,000 bill split May/June is two writes as far as the period lock is concerned.
  /// If June is closed the whole document is refused — not silently reduced to its May
  /// half, which would be a different expense than the one somebody entered.
  ExpenseDecision _authorizePeriods(
    Principal principal,
    ExpenseDocument expense,
  ) {
    for (final allocation in expense.allocations) {
      for (final contribution in allocation.periodContributions) {
        // Deliberately the lock alone. The privilege to *create* a split was decided
        // once, on the shape, in `_authorizeShape`; asking for it again per contribution
        // would demand `expense.allocate_periods` of somebody recording an ordinary
        // one-period expense, whose single contribution the system derived for them.
        final state = authorizer.periodRegistry.stateFor(
          periodKey: contribution.periodKey,
          businessUnitId: allocation.businessUnitId,
        );
        if (state == PeriodState.closed) {
          return ExpenseDecision.denied(
            ExpenseDenialReason.periodClosed,
            detail: '${contribution.periodKey} · ${allocation.businessUnitId}',
          );
        }
      }
    }
    return const ExpenseDecision.allowed();
  }
}
