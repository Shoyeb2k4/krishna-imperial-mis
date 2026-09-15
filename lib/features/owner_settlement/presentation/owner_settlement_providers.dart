/// The settlement surface's state: which month, what the preview says, and whether a
/// refresh is running.
///
/// Phase 5 OA-3. Every provider here depends on the session, so a user switch rebuilds
/// all of it: the month resets, the preview is recomputed for the new person from their
/// own owner-keyed cache, and a refresh in flight for the previous person can no longer
/// write into this person's state (D-074).
///
/// **Authority is decided before anything is read**, by the preview service and not by
/// the widget. A screen that forgot to check would still be handed a refusal.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_preview.dart';
import 'package:krishna_mis/data/sync/owner_settlement_refresh.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart'
    show currentBusinessDateProvider;
import 'package:meta/meta.dart';

/// A calendar month — the settlement grain (OA-2 section 21).
@immutable
final class SettlementMonth {
  const SettlementMonth(this.year, this.month);

  factory SettlementMonth.of(BusinessDate date) =>
      SettlementMonth(date.year, date.month);

  final int year;
  final int month;

  SettlementMonth get previous => month == 1
      ? SettlementMonth(year - 1, 12)
      : SettlementMonth(year, month - 1);

  SettlementMonth get next => month == 12
      ? SettlementMonth(year + 1, 1)
      : SettlementMonth(year, month + 1);

  /// The last trading day of the month, from the period math in `domain/finance`.
  BusinessDate get lastDay =>
      (MonthPeriod(year, month).resolve() as ReportRangeResolved).range.to;

  bool isAfter(SettlementMonth other) =>
      year > other.year || (year == other.year && month > other.month);

  @override
  bool operator ==(Object other) =>
      other is SettlementMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => 'SettlementMonth($year-$month)';
}

/// The month being previewed. Starts at the current trading month and never moves past
/// it — a settlement for a month that has not begun would be a statement about nothing.
final settlementMonthProvider =
    NotifierProvider<SettlementMonthController, SettlementMonth>(
      SettlementMonthController.new,
    );

class SettlementMonthController extends Notifier<SettlementMonth> {
  @override
  SettlementMonth build() {
    // Keyed on the person, never on the whole session: a stale or unchanged authority
    // refresh for the same person must not move the month they chose (Slice 11, D-245).
    ref.watch(sessionProvider.select((s) => s.principal.userId));
    return SettlementMonth.of(ref.watch(currentBusinessDateProvider));
  }

  SettlementMonth get current =>
      SettlementMonth.of(ref.read(currentBusinessDateProvider));

  bool get canGoNext => current.isAfter(state);

  void previous() => state = state.previous;

  void next() {
    if (canGoNext) state = state.next;
  }
}

/// The preview for the selected month.
///
/// Reads only: the owner-keyed canonical cache, the local reporting engine over the
/// canonical reporting cache, and the cached business units. **Never the network** —
/// offline reporting is not gated on connectivity (spec section 21.4) — and never the
/// OA-1 owner masters (D-208).
final ownerSettlementPreviewProvider = FutureProvider<OwnerSettlementPreview>((
  ref,
) async {
  final principal = ref.watch(sessionProvider).principal;

  // Decided before any cache is opened. The service decides it again; this saves opening
  // the reporting engine for somebody who will be refused anyway.
  if (!OwnerSettlementPreviewService.mayReadSettlement(principal)) {
    return const OwnerSettlementPreviewUnavailable(
      OwnerSettlementUnavailableReason.notAuthorised,
    );
  }

  final month = ref.watch(settlementMonthProvider);
  final graph = await ref.watch(masterGraphProvider.future);
  final engine = await ref.watch(localReportingEngineProvider.future);

  return OwnerSettlementPreviewService(
    lock: ref.watch(canonicalCacheLockProvider),
    repository: ref.watch(ownerSettlementRepositoryProvider),
    reporting: engine,
    principal: principal,
  ).preview(
    year: month.year,
    month: month.month,
    // Every property the organisation's P&L covers, archived ones included: a property
    // archived today still earned or spent in the months being settled.
    businessUnitIds: {
      for (final unit in graph.businessUnits(includeArchived: true)) unit.id,
    },
  );
});

/// Where a refresh stands.
enum OwnerSettlementSyncPhase {
  /// Nothing has been asked yet in this session.
  idle,

  /// Both pulls are running.
  synchronising,

  /// Both pulls arrived.
  succeeded,

  /// At least one did not. What the device already holds is untouched (D-048).
  failed,

  /// There is no server to ask — no backend configured, or a reader the settlement
  /// transport is closed to.
  unavailable,
}

@immutable
final class OwnerSettlementSyncStatus {
  const OwnerSettlementSyncStatus(this.phase, {this.report});

  final OwnerSettlementSyncPhase phase;
  final OwnerSettlementRefreshReport? report;
}

final ownerSettlementSyncProvider =
    NotifierProvider<OwnerSettlementSyncController, OwnerSettlementSyncStatus>(
      OwnerSettlementSyncController.new,
    );

/// Starts both pulls, and makes the preview re-read what they left on disk.
class OwnerSettlementSyncController
    extends Notifier<OwnerSettlementSyncStatus> {
  @override
  OwnerSettlementSyncStatus build() {
    // A new person, a new status: a refresh the previous person started is not this
    // person's result (D-074). Keyed on the person, so a session state change for the same
    // person does not drop a refresh that is still running (D-245).
    ref.watch(sessionProvider.select((s) => s.principal.userId));
    return const OwnerSettlementSyncStatus(OwnerSettlementSyncPhase.idle);
  }

  Future<void> refresh() async {
    final refresher = ref.read(ownerSettlementRefresherProvider);
    if (refresher == null) {
      state = const OwnerSettlementSyncStatus(
        OwnerSettlementSyncPhase.unavailable,
      );
      return;
    }
    if (state.phase == OwnerSettlementSyncPhase.synchronising) return;

    state = const OwnerSettlementSyncStatus(
      OwnerSettlementSyncPhase.synchronising,
    );

    final month = ref.read(settlementMonthProvider);
    final graph = await ref.read(masterGraphProvider.future);
    final report = await refresher.refresh(
      businessUnitIds: {
        for (final unit in graph.businessUnits(includeArchived: true)) unit.id,
      },
      periodEnd: month.lastDay,
      today: ref.read(currentBusinessDateProvider),
      // Inside the shared lock: the next report or drill-down read loads the coverage these
      // runs wrote, not the markers it held before them (D-227).
      onCommitted: () {
        if (!ref.mounted) return;
        ref
          ..invalidate(localReportingSourceProvider)
          ..invalidate(reportingDrilldownSourceProvider);
      },
    );
    if (!ref.mounted) return;

    // Superseded by a session or authority transition (D-231): nothing was written.
    if (report.owner is OwnerSettlementSyncAbandoned ||
        (report.reporting?.any((r) => r.abandoned) ?? false)) {
      state = const OwnerSettlementSyncStatus(OwnerSettlementSyncPhase.idle);
      ref.invalidate(ownerSettlementPreviewProvider);
      return;
    }

    state = OwnerSettlementSyncStatus(
      report.succeeded
          ? OwnerSettlementSyncPhase.succeeded
          : OwnerSettlementSyncPhase.failed,
      report: report,
    );

    // The coverage markers are loaded once per reporting source; a refresh that wrote new
    // ones must make the engine read them, and the preview re-read everything.
    ref.invalidate(localReportingSourceProvider);
    ref.invalidate(ownerSettlementPreviewProvider);
  }
}
