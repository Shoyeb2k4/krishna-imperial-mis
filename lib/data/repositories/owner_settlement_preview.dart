/// The Owner Profit & Settlement Statement **preview**: authority first, then evidence,
/// then the OA-2 calculator — and nothing computed here.
///
/// Phase 5 OA-3. The one place the settlement surface asks for a figure, so the rules the
/// project lead set for it are enforced in the data layer rather than in a widget:
///
/// ```
///         a preview is available only when
///           owner_settlement.view is held                          (Q2)
///           the consolidated P&L is authorised and complete        (D-164, D-187)
///           the canonical owner history is authorised and complete (OA-2 section 18)
///           the 50:50 start date is configured                     (Q1)
/// ```
///
/// Missing any of them, it **refuses with the reason**, and never substitutes ₹0 for a
/// missing side (D-163). A widget reading this cannot bypass it, because a widget is never
/// handed a repository to read around it with.
///
/// ## What it does not do
///
/// **No arithmetic.** Operating Profit is `domain/finance`'s (`PnlResult.operatingProfit`,
/// D-020), the entitlement split and every position are `OwnerSettlement.compute`'s (OA-2),
/// and this file only decides which canonical ranges to ask for and passes the answers
/// through. The single literal amount in it is `Money.zero` for the cumulative profit
/// *before* the start date, which is not a calculation but the definition of "from the
/// start": nothing precedes it. A structural guard asserts the rest.
///
/// **Preview only.** No finalize, reopen, lock, approval or statement versioning exists in
/// OA-3, by ruling; a later slice defines finalized statements, and nothing here pretends
/// to be one.
library;

import 'package:krishna_mis/data/reporting/reporting_engine.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/owner_accounts/settlement/owner_settlement.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Why a preview could not be produced. Each is a different thing to do about it.
enum OwnerSettlementUnavailableReason {
  /// This reader does not hold `owner_settlement.view`, or the owner-ledger authority the
  /// settlement composes with. Never a figure, and never ₹0.
  notAuthorised,

  /// The reader may see a settlement but not the **consolidated** P&L it allocates —
  /// unscoped `reports.view`, `revenue.view` and `expense.view.all` (D-164, D-187). A
  /// scoped reader must never receive a partial owner settlement (OA-3 Q2).
  reportingNotAuthorised,

  /// This device has not established complete canonical owner history (OA-2 section 18).
  ownerHistoryNotDownloaded,

  /// The date 50:50 ownership and settlement begin has not been configured (OA-3 Q1).
  startDateNotConfigured,

  /// The month asked for begins before that date.
  beforeStartDate,

  /// The canonical P&L for a required range is not on this device.
  reportingNotDownloaded,

  /// The ownership vector does not resolve to the V1 `[5000, 5000]` for the month (D-204).
  ownershipUnavailable,
}

/// The outcome of asking for a preview.
sealed class OwnerSettlementPreview {
  const OwnerSettlementPreview();
}

final class OwnerSettlementPreviewUnavailable extends OwnerSettlementPreview {
  const OwnerSettlementPreviewUnavailable(this.reason);
  final OwnerSettlementUnavailableReason reason;

  @override
  String toString() => 'OwnerSettlementPreviewUnavailable(${reason.name})';
}

/// A computed preview, and the evidence each half of it rests on — **kept separate**.
///
/// The owner history and the P&L come from two distinct authoritative snapshots, so there
/// is no single "as of" to state. Each keeps its own, and nothing here manufactures a
/// combined one (D-188, and the project lead's OA-3 sync ruling).
final class OwnerSettlementPreviewReady extends OwnerSettlementPreview {
  const OwnerSettlementPreviewReady({
    required this.statement,
    required this.ownershipStartDate,
    required this.ownerNames,
    required this.ownerHistory,
    required this.reportingFreshness,
  });

  /// The OA-2 result, unmodified. Every figure a surface shows comes from here.
  final OwnerSettlementComputed statement;

  final BusinessDate ownershipStartDate;

  /// Owner display names from the **owner-keyed** canonical cache (D-208).
  final Map<String, String> ownerNames;

  /// The owner history's own evidence: snapshot identity and server-confirmed time.
  final OwnerSettlementCoverageState ownerHistory;

  /// The P&L's own freshness, or **null** when its segments cannot be shown to belong to
  /// one synchronisation (D-188). Null is not a third state and is never rendered as one.
  final ReportingFreshness? reportingFreshness;
}

/// Produces previews for one signed-in person.
final class OwnerSettlementPreviewService {
  const OwnerSettlementPreviewService({
    required this.repository,
    required this.reporting,
    required this.principal,
  });

  /// The owner-keyed canonical cache, for **this** person (D-074).
  final OwnerSettlementRepository repository;

  /// The local engine over the canonical reporting cache. Never the remote one: offline
  /// reporting is not gated on the network, and a remote fallback would change the
  /// established local/remote architecture (spec section 21.4).
  final ReportingEngine reporting;

  final Principal principal;

  /// The owner-domain capabilities a preview composes: the settlement permission and the
  /// owner-ledger read it rests on — the same pair the server's settlement transport
  /// requires. The P&L half is [mayReadConsolidatedProfit], asked separately so a refusal
  /// can say which half is missing.
  static bool mayReadSettlement(Principal principal) =>
      principal.canAnywhere(Capability.ownerSettlementView) &&
      principal.canAnywhere(Capability.ownerLedgerView);

  /// Unscoped P&L authority on both sides — the consolidated rule (D-164, D-187).
  static bool mayReadConsolidatedProfit(Principal principal) =>
      principal.scopedUnitsFor(Capability.reportsView) == null &&
      principal.scopedUnitsFor(Capability.revenueView) == null &&
      principal.scopedUnitsFor(Capability.expenseViewAll) == null &&
      principal.canAnywhere(Capability.reportsView) &&
      principal.canAnywhere(Capability.revenueView) &&
      principal.canAnywhere(Capability.expenseViewAll);

  /// The preview for the calendar month [year]-[month], consolidated over
  /// [businessUnitIds] — every property the organisation's P&L covers.
  Future<OwnerSettlementPreview> preview({
    required int year,
    required int month,
    required Set<String> businessUnitIds,
  }) async {
    // ── Authority, before anything is read ────────────────────────────────────
    if (!mayReadSettlement(principal)) {
      return const OwnerSettlementPreviewUnavailable(
        OwnerSettlementUnavailableReason.notAuthorised,
      );
    }
    if (!mayReadConsolidatedProfit(principal)) {
      return const OwnerSettlementPreviewUnavailable(
        OwnerSettlementUnavailableReason.reportingNotAuthorised,
      );
    }

    // ── The owner history, and the date it begins from ────────────────────────
    final coverage = await repository.coverage();
    if (coverage == null) {
      return const OwnerSettlementPreviewUnavailable(
        OwnerSettlementUnavailableReason.ownerHistoryNotDownloaded,
      );
    }
    final start = coverage.ownershipStartDate;
    if (start == null) {
      return const OwnerSettlementPreviewUnavailable(
        OwnerSettlementUnavailableReason.startDateNotConfigured,
      );
    }

    final resolvedMonth =
        MonthPeriod(year, month).resolve() as ReportRangeResolved;
    final periodStart = resolvedMonth.range.from;
    final periodEnd = resolvedMonth.range.to;
    if (periodStart < start) {
      return const OwnerSettlementPreviewUnavailable(
        OwnerSettlementUnavailableReason.beforeStartDate,
      );
    }
    if (businessUnitIds.isEmpty) {
      return const OwnerSettlementPreviewUnavailable(
        OwnerSettlementUnavailableReason.reportingNotDownloaded,
      );
    }

    // ── The canonical Operating Profit, from the one P&L specification ────────
    final scope = ReportingScope(businessUnitIds);

    final atEnd = await reporting.report(
      ReportRequest(
        period: CustomRangePeriod(from: start, to: periodEnd),
        scope: scope,
      ),
    );
    final atEndProfit = atEnd.resultOrNull?.operatingProfit;
    if (atEndProfit == null) return _reportingRefused(atEnd);

    // Cumulative profit before the start date is nothing, by definition — not zero as a
    // substitute for a figure nobody has, but zero as the meaning of "from the start".
    var beforeProfit = Money.zero;
    if (periodStart > start) {
      final before = await reporting.report(
        ReportRequest(
          period: CustomRangePeriod(from: start, to: periodStart.addDays(-1)),
          scope: scope,
        ),
      );
      final profit = before.resultOrNull?.operatingProfit;
      if (profit == null) return _reportingRefused(before);
      beforeProfit = profit;
    }

    // Informational per-property figures for the month (section 25 of OA-2). Entitlement
    // is never computed from these.
    final byUnit = <String, Money>{};
    for (final unit in scope.ordered) {
      final envelope = await reporting.reportForUnit(
        period: MonthPeriod(year, month),
        businessUnitId: unit,
        scope: scope,
      );
      final profit = envelope.resultOrNull?.operatingProfit;
      if (profit == null) return _reportingRefused(envelope);
      byUnit[unit] = profit;
    }

    // ── The OA-2 calculator, and nothing else ─────────────────────────────────
    final outcome = await repository.settle(
      periodKey: periodStart.periodKey,
      periodStart: periodStart,
      periodEnd: periodEnd,
      inception: start,
      operatingProfit: CanonicalOperatingProfit(
        cumulativeBeforePeriod: beforeProfit,
        cumulativeAtPeriodEnd: atEndProfit,
        byBusinessUnitForPeriod: byUnit,
      ),
    );

    return switch (outcome) {
      OwnerSettlementComputed() => OwnerSettlementPreviewReady(
        statement: outcome,
        ownershipStartDate: start,
        ownerNames: await repository.ownerNames(),
        ownerHistory: coverage,
        reportingFreshness: atEnd.freshness,
      ),
      OwnerSettlementRefused(:final refusal) =>
        OwnerSettlementPreviewUnavailable(switch (refusal) {
          OwnerSettlementRefusal.beforeInception =>
            OwnerSettlementUnavailableReason.beforeStartDate,
          OwnerSettlementRefusal.ownershipUnavailable =>
            OwnerSettlementUnavailableReason.ownershipUnavailable,
          OwnerSettlementRefusal.operatingProfitUnavailable =>
            OwnerSettlementUnavailableReason.reportingNotDownloaded,
          OwnerSettlementRefusal.ledgerCoverageIncomplete =>
            OwnerSettlementUnavailableReason.ownerHistoryNotDownloaded,
        }),
    };
  }

  /// A refused P&L, told apart by why: a side the reader may not see is not a side the
  /// device has not downloaded, and neither is ever ₹0 (D-163, D-183).
  OwnerSettlementPreviewUnavailable _reportingRefused(
    ReportEnvelope envelope,
  ) => OwnerSettlementPreviewUnavailable(
    envelope.revenueCoverage == ReportingCoverage.notAuthorised ||
            envelope.expenseCoverage == ReportingCoverage.notAuthorised
        ? OwnerSettlementUnavailableReason.reportingNotAuthorised
        : OwnerSettlementUnavailableReason.reportingNotDownloaded,
  );
}
