/// The dashboard's application state (Phase 6 Slice 4).
///
/// This connects the Slice 3 [DashboardEngine] to the session, and does nothing else. It
/// builds no chart and no screen; those are Slices 5 to 9.
///
/// ## There is one financial authorization model, and this is not a second one
///
/// A property's dashboard qualifies on exactly the intersection [PnlAuthority] already
/// decides for the P&L — `reports.view` ∩ `revenue.view` ∩ `expense.view.all` for that
/// property, all three unscoped for consolidated (D-164, D-187). `expense.view.own` never
/// qualifies, no role name is read, and an Owner Accounts capability grants nothing here.
///
/// The scopes are not merely decided the same way: they are the **same provider**
/// ([pnlScopeOptionsProvider]). A dashboard therefore cannot offer a property the P&L would
/// refuse, and a later change to what qualifies cannot move one surface and leave the other.
///
/// ## Authority identity is part of dashboard identity
///
/// Every state carries the [PnlAuthority.readKey] of the authority it was assembled under,
/// and [dashboardShownTo] refuses to show it to any other. That covers both transitions
/// that matter: a different person, and the **same** person whose capabilities have moved.
///
/// It is needed because a provider re-reading keeps its previous value while it loads —
/// right when a synchronisation lands, and wrong the moment authority changes, because the
/// previous authority's figures would then be the visible dashboard for as long as the next
/// read takes (D-231, D-242). The key is captured **before** anything is read, so an
/// assembly that spans a change is stamped with the authority that started it and can never
/// become the visible dashboard.
///
/// ## Everything else is somebody else's, on purpose
///
/// Periods come from the Slice 2 planner ([DashboardPeriods]) under each property's own
/// business-date rules; nothing here does date arithmetic. Figures come from the Slice 3
/// engine through one path; nothing here calls a reporting engine directly or reassembles a
/// part of the view. Freshness is the engine's combined claim, passed through — when the
/// engine can name no one snapshot this provider names none either.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:meta/meta.dart';

// ── Selection ───────────────────────────────────────────────────────────────

/// Which period a dashboard covers, as the reader chose it.
@immutable
sealed class DashboardPeriodChoice {
  const DashboardPeriodChoice();

  DashboardPeriodKind get kind;
}

/// One of the relative periods, resolved under each property's own calendar.
final class DashboardRelativePeriod extends DashboardPeriodChoice {
  const DashboardRelativePeriod(this.kind)
    : assert(
        kind != DashboardPeriodKind.custom,
        'a custom period needs explicit dates',
      );

  @override
  final DashboardPeriodKind kind;

  @override
  bool operator ==(Object other) =>
      other is DashboardRelativePeriod && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}

/// Explicit P&L dates. Needs no property's calendar.
final class DashboardCustomPeriod extends DashboardPeriodChoice {
  const DashboardCustomPeriod(this.from, this.to);

  final BusinessDate from;
  final BusinessDate to;

  @override
  DashboardPeriodKind get kind => DashboardPeriodKind.custom;

  @override
  bool operator ==(Object other) =>
      other is DashboardCustomPeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// What the reader has chosen. The scope is [PnlScopeChoice] — the same type the P&L
/// selector uses, because it is the same set of qualifying scopes.
@immutable
final class DashboardSelection {
  const DashboardSelection({required this.period, this.scope});

  /// Null until the reader picks one; [PnlScopeOptions.defaultScope] then applies.
  final PnlScopeChoice? scope;
  final DashboardPeriodChoice period;
}

final dashboardSelectionProvider =
    NotifierProvider<DashboardSelectionController, DashboardSelection>(
      DashboardSelectionController.new,
    );

class DashboardSelectionController extends Notifier<DashboardSelection> {
  @override
  DashboardSelection build() {
    // Keyed on the authority, not merely on the person. A new person, or the same person
    // whose qualifying capabilities have changed, starts from a clean selection — a
    // property the previous authority chose may be one this authority may not see
    // (D-074, D-242). A session state change that leaves the authority identical keeps
    // the reader's chosen property and period (D-245).
    ref.watch(sessionProvider.select((s) => PnlAuthority.readKey(s.principal)));
    return const DashboardSelection(
      period: DashboardRelativePeriod(DashboardPeriodKind.monthToDate),
    );
  }

  void selectScope(PnlScopeChoice scope) =>
      state = DashboardSelection(scope: scope, period: state.period);

  void selectPeriod(DashboardPeriodKind kind) => state = DashboardSelection(
    scope: state.scope,
    period: DashboardRelativePeriod(kind),
  );

  void selectCustom(BusinessDate from, BusinessDate to) =>
      state = DashboardSelection(
        scope: state.scope,
        period: DashboardCustomPeriod(from, to),
      );
}

// ── The engine ──────────────────────────────────────────────────────────────

/// The one dashboard path. Every figure a surface shows comes through this.
///
/// Derived from the reporting engine, so it answers once ([noAutomaticRetry]); a dashboard
/// Try again reaches it ([retryFailedDashboardInputs], Phase 8 Slice 3).
final dashboardEngineProvider = FutureProvider<DashboardEngine>(
  (ref) async => DashboardEngine(
    reports: await ref.watch(localReportingEngineProvider.future),
    lock: ref.watch(canonicalCacheLockProvider),
  ),
  retry: noAutomaticRetry,
);

/// [retryFailedReportInputs] for a dashboard, whose engine is one input more.
void retryFailedDashboardInputs(
  bool Function(FutureProvider<Object?> provider) exists,
  AsyncValue<Object?> Function(FutureProvider<Object?> provider) read,
  void Function(FutureProvider<Object?> provider) invalidate,
) => retryFailedReportInputs(
  exists,
  read,
  invalidate,
  also: [dashboardEngineProvider],
);

// ── What a dashboard asks the engine for ────────────────────────────────────

/// How many lines a Top N grouping keeps (D-258).
const dashboardTopN = 5;

/// The request a period implies: one series per measure at the grain that period offers,
/// a daily Net Sales ranking where a daily grain exists, and Top N.
///
/// **The grains are [DashboardTrends.grainsFor]'s answer** (D-255, D-263), so nothing here
/// decides that a period may be trended a way the rulings do not permit. Where a period
/// offers more than one grain for a measure the first is taken; a reader's choice among
/// them belongs to the surface slices.
DashboardRequest dashboardRequestFor({
  required DashboardPeriodPair pair,
  required ReportingScope scope,
}) {
  final trends = <DashboardTrendRequest>[];
  var daily = false;
  for (final measure in TrendMeasure.values) {
    final grains = DashboardTrends.grainsFor(
      pair.kind,
      measure: measure,
      range: pair.kind == DashboardPeriodKind.custom ? pair.current : null,
    );
    if (grains.isEmpty) continue;
    trends.add(DashboardTrendRequest(measure: measure, grain: grains.first));
    if (measure == TrendMeasure.netSales && grains.first == TrendGrain.daily) {
      daily = true;
    }
  }
  return DashboardRequest(
    pair: pair,
    scope: scope,
    trends: trends,
    rankDailyNetSales: daily,
    topN: dashboardTopN,
    // Free: a grouping of the lines the headline already carries, which refuses by itself
    // when the report covers one property (Slice 6).
    compareProperties: true,
  );
}

// ── What the surface reads ──────────────────────────────────────────────────

/// A dashboard's state, stamped with the authority it was assembled under.
@immutable
sealed class DashboardState {
  const DashboardState(this.authorityKey);

  /// [PnlAuthority.readKey] of the authority that started this assembly. A state is never
  /// shown to any other ([dashboardShownTo]).
  final String authorityKey;
}

/// No qualifying scope, or a scope this authority may not read. Nothing was read.
final class DashboardNotAuthorised extends DashboardState {
  const DashboardNotAuthorised(super.authorityKey);
}

/// The chosen period does not describe one pair for this scope — the properties disagree
/// (D-254), a property's calendar could not be read (D-225), or a custom range ends before
/// it starts. **Not a zero report.**
final class DashboardPeriodUnavailable extends DashboardState {
  const DashboardPeriodUnavailable(
    super.authorityKey, {
    required this.kind,
    required this.refusal,
    required this.rejection,
  });

  final DashboardPeriodKind kind;
  final DashboardPairRefusal refusal;

  /// What each property resolved, when the refusal is a disagreement. No property's
  /// answer is preferred.
  final DashboardPairRejected rejection;
}

/// A dashboard the engine assembled — computed or refused, per its own rules.
final class DashboardReady extends DashboardState {
  const DashboardReady(
    super.authorityKey, {
    required this.view,
    required this.scope,
    required this.neededYears,
    required this.retainedYears,
    this.serverHasNewer = false,
  });

  final DashboardView view;

  /// The scope actually read, which is the reader's choice when they made one and the
  /// default otherwise.
  final PnlScopeChoice scope;

  final List<FinancialYear> neededYears;
  final List<FinancialYear> retainedYears;

  /// Whether an authoritative answer said the server has moved past what is held. It
  /// marks the claim and moves no figure.
  final bool serverHasNewer;

  DashboardPeriodPair get pair => view.pair;

  /// The engine's combined claim, marked where the server is known to be ahead.
  ///
  /// **Null stays null.** When the engine could not show every read to belong to one
  /// snapshot it makes no claim, and this makes none either (D-188).
  ReportingFreshness? get freshness {
    final claim = view.freshness;
    if (claim == null) return null;
    return serverHasNewer ? claim.asServerHasNewer() : claim;
  }

  /// Needed years outside normal retention: fetched only on demand (D-170).
  List<FinancialYear> get olderYears => [
    for (final year in neededYears)
      if (!retainedYears.contains(year)) year,
  ];
}

/// The dashboard a surface may show to [principal] now, or null while there is none.
///
/// The comparison is the **authority key**, not the person: the same person whose
/// qualifying capabilities have changed is a different authority, and a dashboard assembled
/// under the previous one must stop being visible at once rather than when the next read
/// happens to finish (D-231, D-242).
DashboardState? dashboardShownTo(
  AsyncValue<DashboardState> state,
  Principal principal,
) {
  final value = state.value;
  if (value == null) return null;
  return value.authorityKey == PnlAuthority.readKey(principal) ? value : null;
}

// ── Resolving a selection ───────────────────────────────────────────────────

/// A resolved target, shared by the read and the synchronisation so both mean the same
/// scope, pair and years.
@immutable
final class _Target {
  const _Target({
    required this.scope,
    required this.scopeUnits,
    required this.syncUnits,
    required this.pair,
    required this.neededYears,
    required this.retainedYears,
  });

  final PnlScopeChoice scope;
  final Set<String> scopeUnits;

  /// Every qualifying property, synchronised together so one property's dashboard and the
  /// consolidated one can share a snapshot's evidence.
  final Set<String> syncUnits;

  final DashboardPeriodPair pair;
  final List<FinancialYear> neededYears;
  final List<FinancialYear> retainedYears;

  String get key =>
      '${(scopeUnits.toList()..sort()).join(',')}|${pair.current.from.iso}|'
      '${pair.current.to.iso}|${pair.comparison.from.iso}|'
      '${pair.comparison.to.iso}';
}

/// The scope a selection resolves to, or null when this authority may read none.
///
/// One place, so the availability probe and the read cannot disagree about what qualifies.
/// The chosen scope is checked against the options **and** against the principal itself —
/// the second is what refuses a scope that arrived any other way than through the selector.
PnlScopeChoice? _authorisedScope(
  PnlScopeOptions options,
  PnlScopeChoice? chosen,
  Principal principal,
) {
  final scope = chosen ?? options.defaultScope;
  if (scope == null || !options.permits(scope)) return null;
  final authorised = switch (scope) {
    PnlConsolidatedScope() => PnlAuthority.mayReadConsolidated(principal),
    PnlUnitScope(:final businessUnitId) => PnlAuthority.mayReadUnit(
      principal,
      businessUnitId,
    ),
  };
  return authorised ? scope : null;
}

/// Resolves a selection into a target, or into the state that explains why there is none.
Object _resolve({
  required String authorityKey,
  required Principal principal,
  required PnlScopeOptions options,
  required DashboardSelection selection,
  required Map<String, BusinessDayRule> rules,
  required DateTime now,
}) {
  final scope = _authorisedScope(options, selection.scope, principal);
  if (scope == null) return DashboardNotAuthorised(authorityKey);

  final scopeUnits = options.unitIdsFor(scope);
  final todayByUnit = <String, BusinessDate>{
    for (final unit in scopeUnits)
      if (rules[unit] case final rule?) unit: rule.businessDateAt(now),
  };
  final withoutCalendar = {
    for (final unit in scopeUnits)
      if (!todayByUnit.containsKey(unit)) unit,
  };

  // The Slice 2 planner decides every date. Both the current range and the comparator are
  // required to agree across the properties in scope (D-254).
  final outcome = switch (selection.period) {
    DashboardCustomPeriod(:final from, :final to) => DashboardPeriods.forCustom(
      from: from,
      to: to,
    ),
    DashboardRelativePeriod(:final kind) => DashboardPeriods.forUnits(
      kind,
      todayByUnit,
      unitsWithoutCalendar: withoutCalendar,
    ),
  };
  if (outcome is DashboardPairRejected) {
    return DashboardPeriodUnavailable(
      authorityKey,
      kind: selection.period.kind,
      refusal: outcome.reason,
      rejection: outcome,
    );
  }
  final pair = (outcome as DashboardPairResolved).pair;

  final retained = <FinancialYear>{
    for (final today in todayByUnit.values)
      ...ReportingRetention.retainedAt(today),
  }.toList()..sort();

  return _Target(
    scope: scope,
    scopeUnits: scopeUnits,
    syncUnits: {for (final u in options.units) u.id},
    pair: pair,
    // Both ranges: a comparator reaching into an earlier financial year needs that year.
    neededYears: <FinancialYear>{
      ...financialYearsCovering(pair.current),
      ...financialYearsCovering(pair.comparison),
    }.toList()..sort(),
    retainedYears: retained,
  );
}

// ── The dashboard ───────────────────────────────────────────────────────────

final dashboardViewProvider = FutureProvider<DashboardState>((ref) async {
  final principal = ref.watch(sessionProvider).principal;
  // Captured before anything is read, so an assembly that spans an authority change is
  // stamped with the authority that started it and can never become the visible dashboard.
  final authorityKey = PnlAuthority.readKey(principal);

  final options = await ref.watch(pnlScopeOptionsProvider.future);
  final selection = ref.watch(dashboardSelectionProvider);
  final rules = await ref.watch(businessDayRulesProvider.future);
  final now = ref.watch(reportingClockProvider)();

  final resolved = _resolve(
    authorityKey: authorityKey,
    principal: principal,
    options: options,
    selection: selection,
    rules: rules,
    now: now,
  );
  if (resolved is DashboardState) return resolved;
  final target = resolved as _Target;

  final newer = ref.watch(
    dashboardSyncProvider.select((s) => s.serverHasNewer ? s.newerKey : null),
  );

  final engine = await ref.watch(dashboardEngineProvider.future);
  final view = await engine.build(
    dashboardRequestFor(
      pair: target.pair,
      scope: ReportingScope(target.scopeUnits),
    ),
  );

  return DashboardReady(
    authorityKey,
    view: view,
    scope: target.scope,
    neededYears: target.neededYears,
    retainedYears: target.retainedYears,
    serverHasNewer: newer == target.key,
  );
});

/// Whether each period describes one pair for the current scope.
///
/// A consolidated dashboard disables a period its properties disagree about, on either
/// range, and the reader is directed to Custom (D-254).
final dashboardPeriodAvailabilityProvider =
    FutureProvider<Map<DashboardPeriodKind, bool>>((ref) async {
      final principal = ref.watch(sessionProvider).principal;
      final options = await ref.watch(pnlScopeOptionsProvider.future);
      final selection = ref.watch(dashboardSelectionProvider);
      final rules = await ref.watch(businessDayRulesProvider.future);
      final now = ref.watch(reportingClockProvider)();
      final key = PnlAuthority.readKey(principal);
      // A custom period needs no property's calendar, so it is offerable whenever there is
      // a scope to read at all. Which dates a reader would pick is not known here, and a
      // probe with invented ones would be answering a different question.
      final custom =
          _authorisedScope(options, selection.scope, principal) != null;
      return {
        for (final kind in DashboardPeriodKind.values)
          kind: kind == DashboardPeriodKind.custom
              ? custom
              : _resolve(
                      authorityKey: key,
                      principal: principal,
                      options: options,
                      selection: DashboardSelection(
                        scope: selection.scope,
                        period: DashboardRelativePeriod(kind),
                      ),
                      rules: rules,
                      now: now,
                    )
                    is _Target,
      };
    });

// ── What a surface renders ──────────────────────────────────────────────────

enum DashboardUnavailableReason {
  /// No qualifying scope, or a scope this authority may not read.
  notAuthorised,

  /// The chosen period does not describe one pair for this scope.
  periodUnavailable,

  /// The engine could not stand behind the figures: nothing downloaded for this range,
  /// or a side this authority may not read. **Never a zero dashboard** (D-163).
  requiredDataUnavailable,
}

/// The five states a surface has to tell apart, as one value.
@immutable
sealed class DashboardPresentation {
  const DashboardPresentation();
}

/// Nothing to show yet — including the moment after an authority change, when the previous
/// authority's dashboard is deliberately no longer visible.
final class DashboardLoading extends DashboardPresentation {
  const DashboardLoading();
}

/// A complete dashboard, and — separately — whether the last refresh failed.
final class DashboardAvailable extends DashboardPresentation {
  const DashboardAvailable(this.dashboard, {this.refreshFailure});

  final DashboardReady dashboard;

  /// Why the last refresh did not arrive, when it did not. The figures are untouched by
  /// it: a failed run writes nothing (D-048), so what is shown is the last complete
  /// canonical snapshot.
  final RemoteFailure? refreshFailure;

  bool get refreshFailed => refreshFailure != null;
}

/// No dashboard, and the reason. Never fabricated figures.
final class DashboardUnavailable extends DashboardPresentation {
  const DashboardUnavailable(this.reason, {this.state});

  final DashboardUnavailableReason reason;

  /// The state behind the reason, for a surface that says something specific.
  final DashboardState? state;
}

/// What [principal] may be shown, from the dashboard and its synchronisation.
///
/// Pure, so a surface cannot arrive at a different answer from the one that is tested.
DashboardPresentation dashboardPresentation({
  required AsyncValue<DashboardState> state,
  required DashboardSyncStatus sync,
  required Principal principal,
}) {
  final shown = dashboardShownTo(state, principal);
  if (shown == null) return const DashboardLoading();
  return switch (shown) {
    DashboardNotAuthorised() => DashboardUnavailable(
      DashboardUnavailableReason.notAuthorised,
      state: shown,
    ),
    DashboardPeriodUnavailable() => DashboardUnavailable(
      DashboardUnavailableReason.periodUnavailable,
      state: shown,
    ),
    DashboardReady(:final view) when !view.isComputed => DashboardUnavailable(
      DashboardUnavailableReason.requiredDataUnavailable,
      state: shown,
    ),
    final DashboardReady ready => DashboardAvailable(
      ready,
      refreshFailure: sync.phase == DashboardSyncPhase.failed
          ? sync.failure
          : null,
    ),
  };
}

// ── Synchronisation ─────────────────────────────────────────────────────────

enum DashboardSyncPhase {
  /// Nothing asked yet under this authority.
  idle,

  /// A refresh is running.
  synchronising,

  /// Older history is being downloaded.
  downloading,

  /// The last run landed for every dataset it asked for.
  succeeded,

  /// The last run did not land. What the device holds is untouched (D-048).
  failed,

  /// No server to ask.
  unavailable,
}

enum DashboardSyncAction { refresh, download }

@immutable
final class DashboardSyncStatus {
  const DashboardSyncStatus(
    this.phase, {
    this.lastAction,
    this.failure,
    this.refused = false,
    this.serverHasNewer = false,
    this.newerKey,
    this.localFailure = false,
  });

  final DashboardSyncPhase phase;
  final DashboardSyncAction? lastAction;

  /// Why the last run did not arrive, when it did not arrive.
  final RemoteFailure? failure;

  /// Whether the last run failed on this device rather than at the server. Nothing was
  /// changed, and Refresh tries again.
  final bool localFailure;

  /// Whether the server declined the last run. Never turned into "not authorised" for a
  /// dashboard: a refusal is not evidence about which figures this person may read.
  final bool refused;

  final bool serverHasNewer;
  final String? newerKey;

  bool get isRunning =>
      phase == DashboardSyncPhase.synchronising ||
      phase == DashboardSyncPhase.downloading;
}

final dashboardSyncProvider =
    NotifierProvider<DashboardSyncController, DashboardSyncStatus>(
      DashboardSyncController.new,
    );

/// Starts the canonical reporting synchronisation for the selected dashboard.
///
/// It is the Phase 5 `ReportingSync`, unchanged: the dashboard adds no second
/// synchronisation, no dashboard endpoint and no new request (D-266).
class DashboardSyncController extends Notifier<DashboardSyncStatus> {
  @override
  DashboardSyncStatus build() {
    // Keyed on the **authority**, like the selection and the dashboard itself. A run the
    // previous authority started is not this authority's status, and a capability change
    // must not leave a status describing a scope this authority cannot read.
    //
    // It is not keyed on the whole session: a refresh that could not reach the server, or
    // one that confirmed the same authority, leaves this key identical and does not drop a
    // run that is still going (D-245).
    ref.watch(sessionProvider.select((s) => PnlAuthority.readKey(s.principal)));
    return const DashboardSyncStatus(DashboardSyncPhase.idle);
  }

  Future<void> refresh() => _run(DashboardSyncAction.refresh);

  Future<void> download() => _run(DashboardSyncAction.download);

  Future<void> _run(DashboardSyncAction action) async {
    if (state.isRunning) return;
    final reportingSync = ref.read(reportingSyncProvider);
    if (reportingSync == null) {
      state = DashboardSyncStatus(
        DashboardSyncPhase.unavailable,
        lastAction: action,
      );
      return;
    }

    final principal = ref.read(sessionProvider).principal;
    final authorityKey = PnlAuthority.readKey(principal);
    // A run belongs to the authority that started it. If either the person or what they
    // may read changes while it runs, its outcome is not the current status (D-074, D-231).
    bool stillCurrent() =>
        ref.mounted &&
        PnlAuthority.readKey(ref.read(sessionProvider).principal) ==
            authorityKey;

    // Visible before anything is awaited, exactly as on the P&L (Phase 8 Slice 3).
    final before = state;
    state = DashboardSyncStatus(
      action == DashboardSyncAction.download
          ? DashboardSyncPhase.downloading
          : DashboardSyncPhase.synchronising,
      lastAction: action,
      serverHasNewer: before.serverHasNewer,
      newerKey: before.newerKey,
    );
    retryFailedDashboardInputs(ref.exists, ref.read, ref.invalidate);

    try {
      await _synchronise(
        action,
        reportingSync,
        principal,
        authorityKey,
        before,
        stillCurrent,
      );
    } on Object {
      // Never left running, and never silent. Nothing was written (D-048).
      if (!stillCurrent()) return;
      state = DashboardSyncStatus(
        DashboardSyncPhase.failed,
        lastAction: action,
        localFailure: true,
        serverHasNewer: before.serverHasNewer,
        newerKey: before.newerKey,
      );
    }
  }

  Future<void> _synchronise(
    DashboardSyncAction action,
    ReportingSync reportingSync,
    Principal principal,
    String authorityKey,
    DashboardSyncStatus before,
    bool Function() stillCurrent,
  ) async {
    // Read once, directly: a one-shot act does not wait on a provider's retries.
    final inputs = await readReportSyncInputs(
      ref.read(masterRepositoryProvider),
      principal,
    );
    final resolved = _resolve(
      authorityKey: authorityKey,
      principal: principal,
      options: inputs.options,
      selection: ref.read(dashboardSelectionProvider),
      rules: inputs.rules,
      now: ref.read(reportingClockProvider)(),
    );
    if (!stillCurrent()) return;
    // Nothing this authority may read, or no period to read: there is nothing to fetch,
    // and fetching anyway would ask the server about properties the surface will not show.
    // The status goes back to exactly what it was.
    if (resolved is! _Target) {
      state = before;
      return;
    }
    final target = resolved;

    final previousNewer =
        before.serverHasNewer && before.newerKey == target.key;
    state = DashboardSyncStatus(
      action == DashboardSyncAction.download
          ? DashboardSyncPhase.downloading
          : DashboardSyncPhase.synchronising,
      lastAction: action,
      serverHasNewer: previousNewer,
      newerKey: previousNewer ? target.key : null,
    );

    final retained = target.retainedYears.toSet();
    final normal = [
      for (final y in target.neededYears)
        if (retained.contains(y)) y,
    ];
    final older = <FinancialYear>[];
    if (action == DashboardSyncAction.download) {
      older.addAll(target.neededYears.where((y) => !retained.contains(y)));
    } else {
      // A refresh keeps already-downloaded older years current; it never starts a
      // download nobody asked for.
      final held = {
        for (final m
            in await ref
                .read(reportingCacheProvider)
                .markersFor(principal.userId))
          m.financialYear,
      };
      older.addAll(
        target.neededYears.where(
          (y) => !retained.contains(y) && held.contains(y.openingYear),
        ),
      );
    }

    // Ask first whether the server has moved past what is held. An unreachable answer is
    // unknown and changes nothing; a confirmed one marks the dashboard without moving a
    // figure.
    var newer = previousNewer;
    if (action == DashboardSyncAction.refresh) {
      final head = await reportingSync.checkForNewer(
        businessUnitIds: target.scopeUnits,
        years: target.neededYears,
      );
      if (head.confirmed) newer = head.serverHasNewer;
    }

    final lock = ref.read(canonicalCacheLockProvider);
    final reports = await lock.run(() async {
      final runs = <ReportingSyncReport>[
        if (normal.isNotEmpty)
          await reportingSync.synchronise(
            businessUnitIds: target.syncUnits,
            years: normal,
          ),
        if (older.isNotEmpty)
          await reportingSync.synchronise(
            businessUnitIds: target.syncUnits,
            years: older,
            onDemand: true,
          ),
      ];
      // Still inside the lock: the next read loads the markers these runs wrote.
      if (ref.mounted) {
        ref
          ..invalidate(localReportingSourceProvider)
          ..invalidate(reportingDrilldownSourceProvider);
      }
      return runs;
    });
    if (!stillCurrent()) return;

    // Superseded by a confirmed authority change while it ran (D-240): it wrote nothing,
    // and it is not the server refusing or failing. The dashboard re-reads under the new
    // authority.
    if (reports.any((r) => r.abandoned)) {
      state = DashboardSyncStatus(DashboardSyncPhase.idle, lastAction: action);
      return;
    }

    final outcomes = [for (final r in reports) ...r.outcomes];
    final landed = outcomes.every((o) => o.isApplied);
    RemoteFailure? failure;
    var refused = false;
    for (final outcome in outcomes) {
      if (outcome case DatasetUnreachable(failure: final f)) failure ??= f;
      if (outcome is DatasetRefused) refused = true;
    }
    if (landed) newer = false;

    state = DashboardSyncStatus(
      landed ? DashboardSyncPhase.succeeded : DashboardSyncPhase.failed,
      lastAction: action,
      failure: landed ? null : failure,
      refused: !landed && refused,
      serverHasNewer: newer,
      newerKey: newer ? target.key : null,
    );
  }
}
