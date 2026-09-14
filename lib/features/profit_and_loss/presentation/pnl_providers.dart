/// The Windows P&L surface's state: which scope and period, what the report says, and
/// where its synchronisation stands (Phase 5 Slice 8).
///
/// ## Authority is decided here, before anything is read
///
/// A property is offered — and may be read — only when the principal holds the full D2
/// intersection for it, and consolidated only with all three capabilities unscoped
/// ([PnlAuthority], D-164, D-187). A scope chosen any other way, by a stale selection or a
/// direct provider read, is refused as [PnlNotAuthorised] without opening the cache. The
/// cache adapter and the server refuse again; this is not the boundary, it is the reason a
/// surface never shows a figure it would be refused.
///
/// ## Periods are resolved per property
///
/// A relative preset is resolved under every included property's **own** business-date
/// rules at one instant, and a consolidated report may use it only when every property gives
/// the same range ([resolvePresetForUnits]). No property is the master calendar.
///
/// ## A read never interleaves with a synchronisation
///
/// A report is several queries over the cache and a synchronisation is one transaction
/// writing it. Were a synchronisation to land between two of those queries, a P&L could pair
/// revenue from one snapshot with expenses from another — a report of a moment that never
/// existed (D-188). Every report read and every synchronisation this surface starts takes
/// [ReportingCacheLock], so the two are serialised.
///
/// ## Nothing here calculates
///
/// Figures come from `LocalReportingEngine` over the canonical cache, and every derived
/// figure from `Pnl.compute` in `domain/finance` (D-020).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/reporting/reporting_engine.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:meta/meta.dart';

// ── Inputs ──────────────────────────────────────────────────────────────────

/// The instant the surface treats as "now", in UTC.
///
/// Only ever turned into a business date through a property's own rules. Overridden in
/// tests to a fixed instant.
final reportingClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// Each cached property's business-date rules. Absent for a property whose stored rules
/// cannot be read, which then refuses a relative preset rather than being defaulted.
final businessDayRulesProvider = FutureProvider<Map<String, BusinessDayRule>>((
  ref,
) {
  ref.watch(sessionProvider);
  return ref.watch(masterRepositoryProvider).businessDayRules();
});

// ── Selection ───────────────────────────────────────────────────────────────

/// Which properties a report covers.
@immutable
sealed class PnlScopeChoice {
  const PnlScopeChoice();
}

final class PnlUnitScope extends PnlScopeChoice {
  const PnlUnitScope(this.businessUnitId);
  final String businessUnitId;

  @override
  bool operator ==(Object other) =>
      other is PnlUnitScope && other.businessUnitId == businessUnitId;

  @override
  int get hashCode => businessUnitId.hashCode;
}

final class PnlConsolidatedScope extends PnlScopeChoice {
  const PnlConsolidatedScope();

  @override
  bool operator ==(Object other) => other is PnlConsolidatedScope;

  @override
  int get hashCode => 1;
}

/// Which period a report covers, as the reader chose it.
@immutable
sealed class PnlPeriodChoice {
  const PnlPeriodChoice();
}

final class PnlPresetPeriod extends PnlPeriodChoice {
  const PnlPresetPeriod(this.preset);
  final RelativePreset preset;

  @override
  bool operator ==(Object other) =>
      other is PnlPresetPeriod && other.preset == preset;

  @override
  int get hashCode => preset.hashCode;
}

/// Explicit P&L dates. Needs no property's calendar.
final class PnlCustomPeriod extends PnlPeriodChoice {
  const PnlCustomPeriod(this.from, this.to);
  final BusinessDate from;
  final BusinessDate to;

  @override
  bool operator ==(Object other) =>
      other is PnlCustomPeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

@immutable
final class PnlSelection {
  const PnlSelection({required this.period, this.scope});

  /// Null until the reader picks one; the surface then uses [PnlScopeOptions.defaultScope].
  final PnlScopeChoice? scope;
  final PnlPeriodChoice period;
}

final pnlSelectionProvider =
    NotifierProvider<PnlSelectionController, PnlSelection>(
      PnlSelectionController.new,
    );

class PnlSelectionController extends Notifier<PnlSelection> {
  @override
  PnlSelection build() {
    // A new person starts from a clean selection: a scope the previous person chose may be
    // one this person is not permitted to see (D-074).
    ref.watch(sessionProvider);
    return const PnlSelection(
      period: PnlPresetPeriod(RelativePreset.thisMonth),
    );
  }

  void selectScope(PnlScopeChoice scope) =>
      state = PnlSelection(scope: scope, period: state.period);

  void selectPreset(RelativePreset preset) =>
      state = PnlSelection(scope: state.scope, period: PnlPresetPeriod(preset));

  void selectCustom(BusinessDate from, BusinessDate to) => state = PnlSelection(
    scope: state.scope,
    period: PnlCustomPeriod(from, to),
  );
}

// ── Scope options ───────────────────────────────────────────────────────────

@immutable
final class PnlUnitOption {
  const PnlUnitOption({required this.id, required this.name});
  final String id;
  final String name;
}

/// The scopes this principal may report on.
@immutable
final class PnlScopeOptions {
  const PnlScopeOptions({
    required this.units,
    required this.consolidatedAllowed,
    required this.viewerUserId,
  });

  /// The person these options were decided for. A surface shows them to nobody else
  /// ([pnlScopeOptionsShownTo]).
  final String viewerUserId;

  /// P&L-authorised properties, in id order.
  final List<PnlUnitOption> units;

  /// Whether the unscoped consolidated authority is held.
  final bool consolidatedAllowed;

  bool get isEmpty => units.isEmpty;

  /// Consolidated when permitted, otherwise the first permitted property, otherwise none.
  PnlScopeChoice? get defaultScope => consolidatedAllowed
      ? const PnlConsolidatedScope()
      : units.isEmpty
      ? null
      : PnlUnitScope(units.first.id);

  bool permits(PnlScopeChoice scope) => switch (scope) {
    PnlConsolidatedScope() => consolidatedAllowed && units.isNotEmpty,
    PnlUnitScope(:final businessUnitId) => units.any(
      (u) => u.id == businessUnitId,
    ),
  };

  Set<String> unitIdsFor(PnlScopeChoice scope) => switch (scope) {
    PnlConsolidatedScope() => {for (final u in units) u.id},
    PnlUnitScope(:final businessUnitId) => {businessUnitId},
  };
}

final pnlScopeOptionsProvider = FutureProvider<PnlScopeOptions>((ref) async {
  final principal = ref.watch(sessionProvider).principal;
  final graph = await ref.watch(masterGraphProvider.future);
  // Archived properties included: a property archived today still traded in the periods
  // being reported.
  final names = {
    for (final unit in graph.businessUnits(includeArchived: true))
      unit.id: unit.name,
  };
  final permitted = PnlAuthority.permittedUnits(principal, names.keys);
  return PnlScopeOptions(
    units: [
      for (final id in permitted) PnlUnitOption(id: id, name: names[id]!),
    ],
    consolidatedAllowed: PnlAuthority.mayReadConsolidated(principal),
    viewerUserId: principal.userId,
  );
});

// ── What a surface may show, and to whom ────────────────────────────────────

/// The view a surface may show to [principal] now, or null while there is none.
///
/// A provider re-reading keeps its previous value while it loads. That is right when a
/// synchronisation lands — the report stays on screen instead of flashing to a spinner —
/// and wrong when the person changes: the previous person's figures would be shown to the
/// next person for as long as the next person's first read waits, and that read queues
/// behind the reporting cache lock, so a synchronisation still running at the switch held
/// them there for its whole duration (D-074). A report is therefore shown only to the person
/// it was computed for. Views that carry no figure are shown as they are.
PnlView? pnlViewShownTo(AsyncValue<PnlView> view, Principal principal) =>
    switch (view.value) {
      PnlReportView(:final viewerUserId)
          when viewerUserId != principal.userId =>
        null,
      final value => value,
    };

/// The scope options a surface may show to [principal] now, or null while there are none.
///
/// For the same reason as [pnlViewShownTo]: the previous person's properties, and their
/// consolidated choice, are never offered to the next person while theirs load.
PnlScopeOptions? pnlScopeOptionsShownTo(
  AsyncValue<PnlScopeOptions> options,
  Principal principal,
) => switch (options.value) {
  final PnlScopeOptions value when value.viewerUserId == principal.userId =>
    value,
  _ => null,
};

// ── Resolving what a report covers ──────────────────────────────────────────

/// What the surface reads.
@immutable
sealed class PnlView {
  const PnlView();
}

/// No P&L-authorised scope, or a scope this principal may not read. Nothing was read.
final class PnlNotAuthorised extends PnlView {
  const PnlNotAuthorised();
}

/// A relative preset that does not describe one period for this scope.
final class PnlPresetUnavailable extends PnlView {
  const PnlPresetUnavailable(this.preset, this.resolution);
  final RelativePreset preset;

  /// [PresetRangesDiffer] or [PresetCalendarUnavailable].
  final PresetResolution resolution;
}

/// A custom range whose end precedes its start.
final class PnlInvalidRange extends PnlView {
  const PnlInvalidRange();
}

/// A report — computed or refused — for a resolved scope and range.
final class PnlReportView extends PnlView {
  const PnlReportView({
    required this.envelope,
    required this.scope,
    required this.range,
    required this.neededYears,
    required this.retainedYears,
    required this.viewerUserId,
  });

  /// The person this report was computed for. Shown to nobody else ([pnlViewShownTo]).
  final String viewerUserId;

  final ReportEnvelope envelope;
  final PnlScopeChoice scope;
  final ReportRange range;

  /// Every financial year the range touches.
  final List<FinancialYear> neededYears;

  /// The years normal retention keeps for the properties in scope.
  final List<FinancialYear> retainedYears;

  /// Needed years outside normal retention: fetched only on demand (D-170).
  List<FinancialYear> get olderYears => [
    for (final year in neededYears)
      if (!retainedYears.contains(year)) year,
  ];

  /// Whether the report is missing history that a download could supply.
  bool get offersDownload =>
      !envelope.isComputed &&
      (envelope.revenueCoverage == ReportingCoverage.notDownloaded ||
          envelope.expenseCoverage == ReportingCoverage.notDownloaded) &&
      olderYears.isNotEmpty;
}

/// A resolved target, shared by the report read and the synchronisation so both mean the
/// same scope, range and years.
@immutable
final class _Target {
  const _Target({
    required this.scope,
    required this.scopeUnits,
    required this.syncUnits,
    required this.period,
    required this.range,
    required this.neededYears,
    required this.retainedYears,
  });

  final PnlScopeChoice scope;
  final Set<String> scopeUnits;

  /// Every P&L-authorised property, synchronised together so a consolidated report and any
  /// one property's report can share one snapshot's evidence.
  final Set<String> syncUnits;

  final ReportingPeriod period;
  final ReportRange range;
  final List<FinancialYear> neededYears;
  final List<FinancialYear> retainedYears;

  String get key =>
      '${(scopeUnits.toList()..sort()).join(',')}|${range.from.iso}|${range.to.iso}';
}

/// Resolves a selection into a target, or into the view that explains why there is none.
Object _resolve({
  required Principal principal,
  required PnlScopeOptions options,
  required PnlSelection selection,
  required Map<String, BusinessDayRule> rules,
  required DateTime now,
}) {
  final scope = selection.scope ?? options.defaultScope;
  if (scope == null || !options.permits(scope)) return const PnlNotAuthorised();

  // Decided again against the principal itself, not only against the options it produced.
  final authorised = switch (scope) {
    PnlConsolidatedScope() => PnlAuthority.mayReadConsolidated(principal),
    PnlUnitScope(:final businessUnitId) => PnlAuthority.mayReadUnit(
      principal,
      businessUnitId,
    ),
  };
  if (!authorised) return const PnlNotAuthorised();

  final scopeUnits = options.unitIdsFor(scope);
  final todayByUnit = <String, BusinessDate>{
    for (final unit in scopeUnits)
      if (rules[unit] case final rule?) unit: rule.businessDateAt(now),
  };

  final ReportingPeriod period;
  final ReportRange range;
  switch (selection.period) {
    case PnlPresetPeriod(:final preset):
      final resolution = resolvePresetForUnits(
        preset,
        todayByUnit,
        unitsWithoutCalendar: {
          for (final unit in scopeUnits)
            if (!todayByUnit.containsKey(unit)) unit,
        },
      );
      if (resolution is! PresetResolved) {
        return PnlPresetUnavailable(preset, resolution);
      }
      period = resolution.period;
      range = resolution.range;
    case PnlCustomPeriod(:final from, :final to):
      final custom = CustomRangePeriod(from: from, to: to);
      final resolved = custom.resolve();
      if (resolved is! ReportRangeResolved) return const PnlInvalidRange();
      period = custom;
      range = resolved.range;
  }

  final retained = <FinancialYear>{
    for (final today in todayByUnit.values)
      ...ReportingRetention.retainedAt(today),
  }.toList()..sort();

  return _Target(
    scope: scope,
    scopeUnits: scopeUnits,
    syncUnits: {for (final u in options.units) u.id},
    period: period,
    range: range,
    neededYears: financialYearsCovering(range),
    retainedYears: retained,
  );
}

// ── The report ──────────────────────────────────────────────────────────────

/// Serialises cache reads and cache writes started by this surface.
final class ReportingCacheLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return previous.then((_) => action()).whenComplete(released.complete);
  }
}

final pnlReportingLockProvider = Provider<ReportingCacheLock>(
  (ref) => ReportingCacheLock(),
);

final pnlViewProvider = FutureProvider<PnlView>((ref) async {
  final principal = ref.watch(sessionProvider).principal;
  final options = await ref.watch(pnlScopeOptionsProvider.future);
  final selection = ref.watch(pnlSelectionProvider);
  final rules = await ref.watch(businessDayRulesProvider.future);
  final now = ref.watch(reportingClockProvider)();

  final resolved = _resolve(
    principal: principal,
    options: options,
    selection: selection,
    rules: rules,
    now: now,
  );
  if (resolved is PnlView) return resolved;
  final target = resolved as _Target;

  final newer = ref.watch(
    pnlSyncProvider.select((s) => s.serverHasNewer ? s.newerKey : null),
  );

  final envelope = await ref.watch(pnlReportingLockProvider).run(() async {
    // Inside the lock, so the coverage markers the engine loads belong to the same
    // cache state as the figures it then reads.
    final engine = await ref.watch(localReportingEngineProvider.future);
    return switch (target.scope) {
      PnlUnitScope(:final businessUnitId) => engine.reportForUnit(
        period: target.period,
        businessUnitId: businessUnitId,
        scope: ReportingScope.unit(businessUnitId),
      ),
      PnlConsolidatedScope() => engine.report(
        ReportRequest(
          period: target.period,
          scope: ReportingScope(target.scopeUnits),
        ),
      ),
    };
  });

  return PnlReportView(
    // The figures do not move; the report is only marked as known to be behind (D-188).
    envelope: newer == target.key ? envelope.asServerHasNewer() : envelope,
    scope: target.scope,
    range: target.range,
    neededYears: target.neededYears,
    retainedYears: target.retainedYears,
    viewerUserId: principal.userId,
  );
});

/// Whether each relative preset describes one period for the current scope.
///
/// A consolidated report disables a preset its properties disagree about, and the reader is
/// directed to Custom.
final pnlPresetAvailabilityProvider = FutureProvider<Map<RelativePreset, bool>>(
  (ref) async {
    final principal = ref.watch(sessionProvider).principal;
    final options = await ref.watch(pnlScopeOptionsProvider.future);
    final selection = ref.watch(pnlSelectionProvider);
    final rules = await ref.watch(businessDayRulesProvider.future);
    final now = ref.watch(reportingClockProvider)();
    return {
      for (final preset in RelativePreset.values)
        preset:
            _resolve(
                  principal: principal,
                  options: options,
                  selection: PnlSelection(
                    scope: selection.scope,
                    period: PnlPresetPeriod(preset),
                  ),
                  rules: rules,
                  now: now,
                )
                is _Target,
    };
  },
);

// ── Synchronisation ─────────────────────────────────────────────────────────

enum PnlSyncPhase {
  /// Nothing asked yet in this session.
  idle,

  /// A refresh is running.
  synchronising,

  /// Older history is being downloaded.
  downloading,

  /// The last run landed for every dataset it asked for.
  succeeded,

  /// The last run did not land. What the device holds is untouched (D-048).
  failed,

  /// No server to ask: no backend configured, or no signed-in session.
  unavailable,
}

enum PnlSyncAction { refresh, download }

@immutable
final class PnlSyncStatus {
  const PnlSyncStatus(
    this.phase, {
    this.lastAction,
    this.failure,
    this.refused = false,
    this.serverHasNewer = false,
    this.newerKey,
  });

  final PnlSyncPhase phase;
  final PnlSyncAction? lastAction;

  /// Why the last run did not arrive, when it did not arrive.
  final RemoteFailure? failure;

  /// Whether the server declined the last run. Never turned into "not authorised" for a
  /// report: a refusal is not evidence about which figures this person may read.
  final bool refused;

  /// Whether the server confirmed newer canonical changes for [newerKey]'s target.
  final bool serverHasNewer;
  final String? newerKey;

  bool get isRunning =>
      phase == PnlSyncPhase.synchronising || phase == PnlSyncPhase.downloading;
}

final pnlSyncProvider = NotifierProvider<PnlSyncController, PnlSyncStatus>(
  PnlSyncController.new,
);

/// Starts the canonical reporting synchronisation for the selected report.
class PnlSyncController extends Notifier<PnlSyncStatus> {
  @override
  PnlSyncStatus build() {
    // A new person, a new status: a run the previous person started is not this person's.
    ref.watch(sessionProvider);
    return const PnlSyncStatus(PnlSyncPhase.idle);
  }

  /// Brings the selected report's retained years up to date, and any older year already
  /// downloaded.
  Future<void> refresh() => _run(PnlSyncAction.refresh);

  /// Downloads every year the selected report needs, older years on demand.
  Future<void> download() => _run(PnlSyncAction.download);

  Future<void> _run(PnlSyncAction action) async {
    if (state.isRunning) return;
    final reportingSync = ref.read(reportingSyncProvider);
    if (reportingSync == null) {
      state = PnlSyncStatus(PnlSyncPhase.unavailable, lastAction: action);
      return;
    }

    final principal = ref.read(sessionProvider).principal;
    // A run belongs to the person who started it. If the person changes while it runs, its
    // outcome is not the next person's status (D-074).
    bool stillTheSamePerson() =>
        ref.mounted &&
        ref.read(sessionProvider).principal.userId == principal.userId;
    final options = await ref.read(pnlScopeOptionsProvider.future);
    final rules = await ref.read(businessDayRulesProvider.future);
    final resolved = _resolve(
      principal: principal,
      options: options,
      selection: ref.read(pnlSelectionProvider),
      rules: rules,
      now: ref.read(reportingClockProvider)(),
    );
    if (!stillTheSamePerson()) return;
    // Nothing this person may read, or no period to read: there is nothing to fetch, and
    // fetching anyway would ask the server about properties the surface will not show.
    if (resolved is! _Target) return;
    final target = resolved;

    final previousNewer = state.serverHasNewer && state.newerKey == target.key;
    state = PnlSyncStatus(
      action == PnlSyncAction.download
          ? PnlSyncPhase.downloading
          : PnlSyncPhase.synchronising,
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
    if (action == PnlSyncAction.download) {
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
    // unknown and changes nothing; a confirmed one marks the report without moving a figure.
    var newer = previousNewer;
    if (action == PnlSyncAction.refresh) {
      final head = await reportingSync.checkForNewer(
        businessUnitIds: target.scopeUnits,
        years: target.neededYears,
      );
      if (head.confirmed) newer = head.serverHasNewer;
    }

    final lock = ref.read(pnlReportingLockProvider);
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
      // Still inside the lock: the next read loads the markers these runs wrote — for the
      // report and for the document rows beneath it (Slice 10).
      if (ref.mounted) {
        ref
          ..invalidate(localReportingSourceProvider)
          ..invalidate(reportingDrilldownSourceProvider);
      }
      return runs;
    });
    if (!stillTheSamePerson()) return;

    final outcomes = [for (final r in reports) ...r.outcomes];
    final landed = outcomes.every((o) => o.isApplied);
    RemoteFailure? failure;
    var refused = false;
    for (final outcome in outcomes) {
      if (outcome case DatasetUnreachable(failure: final f)) failure ??= f;
      if (outcome is DatasetRefused) refused = true;
    }
    if (landed) newer = false;

    state = PnlSyncStatus(
      landed ? PnlSyncPhase.succeeded : PnlSyncPhase.failed,
      lastAction: action,
      failure: landed ? null : failure,
      refused: !landed && refused,
      serverHasNewer: newer,
      newerKey: newer ? target.key : null,
    );
    // No explicit invalidation of the view: it watches this status, so invalidating it from
    // here would be a cycle. Invalidating the reporting source inside the lock already makes
    // the view re-read what these runs wrote.
  }
}
