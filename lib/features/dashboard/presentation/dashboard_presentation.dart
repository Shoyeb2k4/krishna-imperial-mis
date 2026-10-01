/// What a dashboard says, decided once (Phase 6 Slice 6).
///
/// The Windows Overview is built on it now; the Android Home (Slice 7) is built on the
/// same file, so the two cannot describe one dashboard differently. That is the rule
/// D-232 settled for the two P&L surfaces, applied here before the second surface exists
/// rather than after the wording has already been written twice.
///
/// ## What this file does not do
///
/// It computes no figure, decides no authority, derives no business date, judges no
/// coverage or freshness and ranks nothing. Every value arrives decided — from
/// `Pnl.compute`, `PnlComparison`, `DashboardTrends`, `TopN`, `PropertyComparison`,
/// `PnlAuthority` and the reporting envelope — and is turned into words and display
/// formatting here. The Slice 6 surface guard holds that.
///
/// In particular **no movement is worked out here**. A rupee change, a percentage, a
/// percentage-point movement and a profit-to-loss transition are all fields of a
/// [MoneyComparison] or a [MarginComparison] that `domain/finance` produced; this file
/// chooses the sentence that states them (D-253, D-256, D-264).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/design/charts/chart_series.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/core/formatting/report_dates.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_presentation.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

// ── Messages shown instead of a dashboard ──────────────────────────────────

/// What a message's single action does. The surface binds it to the synchroniser.
enum DashboardMessageAction {
  synchronise('Synchronise'),
  download('Download required data'),
  retryDownload('Try again');

  const DashboardMessageAction(this.label);
  final String label;
}

/// Shown in place of a dashboard. Never a figure, never ₹0, never an empty chart.
@immutable
final class DashboardMessage {
  const DashboardMessage({
    required this.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.actionKey,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String message;
  final DashboardMessageAction? action;
  final Key? actionKey;
}

/// The approved neutral state for a reader without qualifying P&L authority (D-259).
///
/// It names no property, states no figure and offers no action: a reader who may not see
/// the analytics must not learn from this screen which properties exist.
const dashboardNotAuthorisedMessage = DashboardMessage(
  key: Key('dashboard-not-authorised'),
  icon: Icons.insights_outlined,
  title: 'Management analytics are not available for your access.',
  message:
      'A management dashboard needs report, revenue and full expense access for a '
      'property. No partial dashboard is shown.',
);

/// The message for [presentation], or null when a dashboard is to be shown as figures.
///
/// [canAsk] is whether a synchroniser exists to ask the server at all.
DashboardMessage? dashboardMessageFor(
  DashboardPresentation presentation,
  DashboardSyncStatus sync, {
  required bool canAsk,
}) => switch (presentation) {
  DashboardLoading() => null,
  DashboardAvailable() => null,
  DashboardUnavailable(reason: DashboardUnavailableReason.notAuthorised) =>
    dashboardNotAuthorisedMessage,
  DashboardUnavailable(
    reason: DashboardUnavailableReason.periodUnavailable,
    :final state,
  ) =>
    _periodMessage(state as DashboardPeriodUnavailable),
  DashboardUnavailable(:final state) => _dataMessage(
    state! as DashboardReady,
    sync,
    canAsk: canAsk,
  ),
};

DashboardMessage _periodMessage(
  DashboardPeriodUnavailable state,
) => switch (state.refusal) {
  DashboardPairRefusal.endBeforeStart => const DashboardMessage(
    key: Key('dashboard-invalid-range'),
    icon: Icons.date_range_outlined,
    title: 'That range ends before it starts',
    message:
        'Choose a start date on or before the end date. The range is never swapped '
        'for you.',
  ),
  DashboardPairRefusal.calendarUnavailable => DashboardMessage(
    key: const Key('dashboard-calendar-unavailable'),
    icon: Icons.event_busy_outlined,
    title: '${state.kind.label} cannot be worked out for this scope',
    message:
        "A property's business-date rules could not be read on this device, so "
        '"${state.kind.label}" has no dates. Use Custom to choose them explicitly.',
  ),
  DashboardPairRefusal.currentRangesDiffer ||
  DashboardPairRefusal.comparisonRangesDiffer => DashboardMessage(
    key: const Key('dashboard-periods-differ'),
    icon: Icons.event_busy_outlined,
    title: '${state.kind.label} is not available for both properties',
    message:
        'The properties in this dashboard are on different business dates, so '
        '"${state.kind.label}" does not describe one period for all of them. Use '
        'Custom to choose the dates explicitly.',
  ),
};

DashboardMessage _dataMessage(
  DashboardReady ready,
  DashboardSyncStatus sync, {
  required bool canAsk,
}) {
  final revenue = ready.view.revenueCoverage;
  final expenses = ready.view.expenseCoverage;
  final range = reportRangeLabel(ready.pair.current);

  if (revenue == ReportingCoverage.notAuthorised &&
      expenses == ReportingCoverage.notAuthorised) {
    return dashboardNotAuthorisedMessage;
  }

  final unreachable =
      sync.phase == DashboardSyncPhase.failed && sync.failure != null;
  final bothNotDownloaded =
      revenue == ReportingCoverage.notDownloaded &&
      expenses == ReportingCoverage.notDownloaded;

  if (bothNotDownloaded) {
    if (sync.phase == DashboardSyncPhase.downloading) {
      return DashboardMessage(
        key: const Key('dashboard-downloading'),
        icon: Icons.downloading_outlined,
        title: 'Downloading required history',
        message: 'Fetching the canonical figures for $range.',
      );
    }
    if (sync.phase == DashboardSyncPhase.synchronising) {
      return DashboardMessage(
        key: const Key('dashboard-synchronising'),
        icon: Icons.sync,
        title: 'Synchronising',
        message: 'Bringing the dashboard for $range up to date on this device.',
      );
    }
    if (sync.phase == DashboardSyncPhase.failed && sync.localFailure) {
      return DashboardMessage(
        key: const Key('dashboard-sync-local-failure'),
        icon: Icons.error_outline,
        title: sync.lastAction == DashboardSyncAction.download
            ? 'Download could not start'
            : 'Synchronisation could not start',
        message: dashboardLocalFailureText,
        action: !canAsk
            ? null
            : sync.lastAction == DashboardSyncAction.download
            ? DashboardMessageAction.retryDownload
            : DashboardMessageAction.synchronise,
        actionKey: sync.lastAction == DashboardSyncAction.download
            ? const Key('dashboard-download')
            : const Key('dashboard-synchronise'),
      );
    }
    if (sync.phase == DashboardSyncPhase.failed &&
        sync.lastAction == DashboardSyncAction.download) {
      return DashboardMessage(
        key: const Key('dashboard-download-failed'),
        icon: Icons.cloud_off_outlined,
        title: 'Download failed',
        message: unreachable
            ? 'A connection is required to download this history, and the server could '
                  'not be reached. Nothing is shown rather than an incomplete dashboard.'
            : 'The server did not provide this history. Nothing is shown rather than an '
                  'incomplete dashboard.',
        action: canAsk ? DashboardMessageAction.retryDownload : null,
        actionKey: const Key('dashboard-download'),
      );
    }

    final older = ready.olderYears;
    final years = older.map((y) => 'FY ${y.label}').join(', ');
    return DashboardMessage(
      key: const Key('dashboard-not-downloaded'),
      icon: Icons.download_outlined,
      title: 'Not downloaded',
      message: older.isNotEmpty
          ? 'This device does not hold the history for $range ($years). '
                '${unreachable || !canAsk ? 'A connection is required to download it.' : 'It can be downloaded now.'}'
          : unreachable || !canAsk
          ? 'This device does not hold the figures for $range yet, and a connection is '
                'required to synchronise them.'
          : 'This device does not hold the figures for $range yet.',
      action: !canAsk
          ? null
          : older.isNotEmpty
          ? DashboardMessageAction.download
          : DashboardMessageAction.synchronise,
      actionKey: older.isNotEmpty
          ? const Key('dashboard-download')
          : const Key('dashboard-synchronise'),
    );
  }

  final (key, title) = switch (ready.view.refusalOrNull) {
    PnlRefusal.revenueUnavailable => (
      const Key('dashboard-revenue-unavailable'),
      'Revenue unavailable',
    ),
    PnlRefusal.expensesUnavailable => (
      const Key('dashboard-expense-unavailable'),
      'Expenses unavailable',
    ),
    _ => (
      const Key('dashboard-both-unavailable'),
      'Revenue and expenses unavailable',
    ),
  };
  return DashboardMessage(
    key: key,
    icon: Icons.report_gmailerrorred_outlined,
    title: title,
    message:
        'Revenue: ${_coverageText(revenue)}. Expenses: ${_coverageText(expenses)}. '
        'A dashboard needs both sides complete, so no figure is shown.',
    action:
        canAsk &&
            (revenue == ReportingCoverage.notDownloaded ||
                expenses == ReportingCoverage.notDownloaded)
        ? DashboardMessageAction.synchronise
        : null,
    actionKey: const Key('dashboard-synchronise'),
  );
}

String _coverageText(ReportingCoverage coverage) => switch (coverage) {
  ReportingCoverage.complete => 'complete',
  ReportingCoverage.notDownloaded => 'not downloaded to this device',
  ReportingCoverage.notAuthorised => 'not available to your account',
};

/// A synchronisation that failed on this device before or after asking the server.
const dashboardLocalFailureText =
    'This device could not prepare or record the synchronisation, so nothing was asked '
    'of the server and nothing was changed. Nothing is shown rather than an incomplete '
    'dashboard. Try again; if it persists, report it.';

/// Shown when the dashboard could not be read at all.
const dashboardReadErrorMessage = DashboardMessage(
  key: Key('dashboard-read-error'),
  icon: Icons.error_outline,
  title: 'The dashboard could not be read on this device',
  message: 'Nothing has been changed. Try again; if it persists, report it.',
);

// ── Notices over figures already on screen ──────────────────────────────────

@immutable
final class DashboardNotice {
  const DashboardNotice({
    required this.key,
    required this.icon,
    required this.text,
  });
  final Key key;
  final IconData icon;
  final String text;
}

/// What the last synchronisation means for a **complete** dashboard already on screen.
///
/// A failed refresh never blanks the figures: a failed run writes nothing (D-048), so
/// what is shown is still the last complete canonical snapshot, and the failure is
/// reported beside it rather than instead of it.
DashboardNotice? dashboardNoticeFor(DashboardSyncStatus sync) {
  if (sync.isRunning) {
    return DashboardNotice(
      key: const Key('dashboard-refreshing'),
      icon: Icons.sync,
      text: sync.phase == DashboardSyncPhase.downloading
          ? 'Downloading. The figures below are as last synchronised.'
          : 'Refreshing. The figures below are as last synchronised.',
    );
  }
  if (sync.phase == DashboardSyncPhase.failed && sync.localFailure) {
    return const DashboardNotice(
      key: Key('dashboard-sync-local-failure-notice'),
      icon: Icons.error_outline,
      text:
          'The refresh could not run on this device, so nothing was asked of the server. '
          'These figures are the complete dashboard this device last synchronised. '
          'Refresh to try again.',
    );
  }
  if (sync.phase == DashboardSyncPhase.failed) {
    return sync.failure != null
        ? const DashboardNotice(
            key: Key('dashboard-offline'),
            icon: Icons.cloud_off_outlined,
            text:
                'The server could not be reached. These figures are the complete '
                'dashboard this device last synchronised.',
          )
        : const DashboardNotice(
            key: Key('dashboard-sync-refused'),
            icon: Icons.cloud_off_outlined,
            text:
                'The server did not accept the last synchronisation. These figures are '
                'the complete dashboard this device last synchronised.',
          );
  }
  return null;
}

// ── Freshness ───────────────────────────────────────────────────────────────

@immutable
final class DashboardFreshnessLine {
  const DashboardFreshnessLine({
    required this.key,
    required this.text,
    this.caution = false,
  });
  final Key key;
  final String text;
  final bool caution;
}

/// The freshness sentence for a dashboard, as the engine's combined claim states it.
///
/// **Null stays null.** When the engine could not show every read to belong to one
/// authoritative snapshot it makes no claim, and no timestamp is fabricated to fill the
/// gap — the figures are canonical either way, and what is withheld is the stronger
/// statement (D-188).
DashboardFreshnessLine dashboardFreshnessLine(
  DashboardReady ready,
  Map<String, BusinessDayRule> rules,
) {
  final freshness = ready.freshness;
  if (freshness == null) {
    return const DashboardFreshnessLine(
      key: Key('dashboard-freshness-none'),
      text:
          'Complete, but these figures do not come from one synchronisation, so no '
          'single time is stated.',
    );
  }
  final when = reportInstantLabel(
    freshness.synchronisedAt,
    dashboardDisplayZone(rules, ready),
  );
  return switch (freshness.state) {
    ReportingFreshnessState.synchronised => DashboardFreshnessLine(
      key: const Key('dashboard-freshness-synchronised'),
      text: 'Synchronised as of $when',
    ),
    ReportingFreshnessState.serverHasNewer => DashboardFreshnessLine(
      key: const Key('dashboard-freshness-server-newer'),
      text:
          'Synchronised as of $when · the server has newer changes. Refresh to update.',
      caution: true,
    ),
  };
}

/// The zone a server-confirmed time is displayed in: the scope's own property, or the
/// first in id order when consolidated. Display only; nothing is derived from it.
String dashboardDisplayZone(
  Map<String, BusinessDayRule> rules,
  DashboardReady ready,
) {
  // The lowest business-unit id, found without sorting: nothing in this feature may
  // reorder a list, because the one place ordering carries meaning is a ranked financial
  // list and that order is the domain's (D-258).
  String? lowest;
  for (final id in rules.keys) {
    if (lowest == null || id.compareTo(lowest) < 0) lowest = id;
  }
  final unit = switch (ready.scope) {
    PnlUnitScope(:final businessUnitId) => businessUnitId,
    PnlConsolidatedScope() => lowest,
  };
  return rules[unit]?.timeZoneId ?? 'UTC';
}

/// What the organisation scope is called, wherever it is named.
///
/// One sentence, so the Overview's chip, the phone's selector and the phone's sheet
/// cannot become three descriptions of one thing (D-232).
const String dashboardConsolidatedScopeLabel = 'Both properties (consolidated)';

// ── Period wording ──────────────────────────────────────────────────────────

/// `Month to date · 1 Sep 2026 – 19 Sep 2026`.
String dashboardPeriodLine(DashboardPeriodPair pair) =>
    '${pair.kind.label} · ${reportRangeLabel(pair.current)}';

/// `1 Aug 2026 – 19 Aug 2026`, the stretch the current one is compared with.
String dashboardComparisonRangeLabel(DashboardPeriodPair pair) =>
    reportRangeLabel(pair.comparison);

/// Why the comparator covers fewer days, when it does (D-251). Null otherwise.
String? dashboardCapNote(DashboardPeriodPair pair) => pair.comparisonCapped
    ? 'The previous period is shorter: '
          '${pair.comparison.days} days against ${pair.current.days}.'
    : null;

// ── Movements ───────────────────────────────────────────────────────────────

/// A comparison, in words. Every figure in it is the domain's.
@immutable
final class DashboardMovement {
  const DashboardMovement({
    required this.text,
    required this.available,
    this.note,
  });

  /// `+₹12,500.00 · +8.42%`, `+₹12,500.00`, `+1.80 pp`, or the unavailable sentence.
  final String text;

  /// A second line: why there is no percentage, or that a profit became a loss.
  final String? note;

  /// Whether there is a movement at all. False renders as a restrained explanation and
  /// **never as zero** (D-163).
  final bool available;

  String semanticsWith(String comparisonLabel) => available
      ? '$text compared with $comparisonLabel.${note == null ? '' : ' $note'}'
      : text;
}

/// The movement of an ordinary money figure, or Operating Profit.
///
/// The rupee change is shown in every available case; the percentage appears only where
/// the domain produced one (D-253, D-256), and the reason it did not is stated rather
/// than left as a silent absence.
DashboardMovement dashboardMoneyMovement(
  MoneyComparison comparison,
) => switch (comparison) {
  MoneyComparisonUnavailable(:final side) => DashboardMovement(
    text: switch (side) {
      ComparisonSide.previous =>
        'No comparison — the previous period is not available.',
      ComparisonSide.current => 'No comparison — this period is not available.',
      ComparisonSide.both => 'No comparison — neither period is available.',
    },
    available: false,
  ),
  MoneyComparisonAvailable(:final change, :final percentChange) =>
    DashboardMovement(
      text: switch (percentChange) {
        PercentChangeRatio() =>
          '${MoneyFormatter.movement.format(change)} · '
              '${percentChange.displayTwoDecimals}',
        PercentChangeNotApplicable() => MoneyFormatter.movement.format(change),
      },
      available: true,
      note: switch (percentChange) {
        PercentChangeRatio() => null,
        PercentChangeNotApplicable(:final reason) => _percentNote(
          reason,
          comparison,
        ),
      },
    ),
};

String _percentNote(
  PercentNotApplicableReason reason,
  MoneyComparison comparison,
) => switch (reason) {
  PercentNotApplicableReason.previousZero =>
    'No percentage: the previous period was nil.',
  PercentNotApplicableReason.previousNegative =>
    'No percentage: the previous figure was below zero.',
  PercentNotApplicableReason.currentNegative =>
    "No percentage: this period's figure is below zero.",
  PercentNotApplicableReason.negativeSide =>
    'No percentage: a loss on one side.',
  PercentNotApplicableReason.signChanged =>
    comparison is MoneyComparisonAvailable
        ? comparison.transition.wording ?? 'No percentage: the sign changed.'
        : 'No percentage: the sign changed.',
};

/// The margin movement, in percentage points.
///
/// The figure is [MarginComparison.displayTwoDecimals], which is the difference of the
/// two **displayed** margins — so the movement, this period's margin and the previous
/// one reconcile exactly on screen (D-264).
DashboardMovement dashboardMarginMovement(MarginComparison comparison) =>
    switch (comparison) {
      MarginComparisonUnavailable(:final reason) => DashboardMovement(
        text: switch (reason) {
          MarginComparisonUnavailableReason.sideUnavailable =>
            'No comparison — the previous period is not available.',
          MarginComparisonUnavailableReason.marginNotApplicable =>
            'No comparison — a period had no net sales, so it has no margin.',
        },
        available: false,
      ),
      MarginMovement() => DashboardMovement(
        text: comparison.displayTwoDecimals,
        available: true,
      ),
    };

/// The previous period's margin, printed the way this period's is, so the two and the
/// movement between them add up on screen (D-264).
String dashboardPreviousMarginLabel(MarginComparison comparison) =>
    switch (comparison) {
      MarginMovement(:final previous) => previous.displayTwoDecimals,
      MarginComparisonUnavailable() =>
        const MarginNotApplicable().displayTwoDecimals,
    };

/// One headline figure in words, for a screen reader.
///
/// Money becomes text through the application's one formatter, here rather than in a
/// surface — the same rule `MoneyText` follows for the figure it draws.
String dashboardMetricSemantics({
  required String label,
  required Money amount,
  required DashboardMovement movement,
  required String comparedWith,
}) =>
    '$label. ${MoneyFormatter.standard.format(amount)}. '
    '${movement.semanticsWith(comparedWith)}';

// ── Figure names ────────────────────────────────────────────────────────────

/// Operating Profit or Operating Loss, in words. Never colour alone (spec §20).
String dashboardProfitLabel(PnlResult result) =>
    result.operatingProfit.isNegative ? 'Operating Loss' : 'Operating Profit';

// ── Trend wording ───────────────────────────────────────────────────────────

/// `Net Sales · daily`.
String dashboardTrendTitle(TrendSeries series) => series.measure.chartLabel;

/// What one position on a trend is called.
///
/// A day is `19 Sep`, a week `22–28 Sep`, a month `Sep 2026`. A clipped bucket keeps the
/// dates it actually covers rather than being stretched to a notional whole one (D-263);
/// that it is clipped is said in the chart's footnote, by the chart layer.
String dashboardBucketLabel(TrendBucket bucket, TrendGrain grain) =>
    switch (grain) {
      TrendGrain.daily => reportDayLabel(bucket.range.from),
      TrendGrain.weekly => reportShortRangeLabel(bucket.range),
      TrendGrain.monthly =>
        bucket.partial
            ? reportShortRangeLabel(bucket.range)
            : reportMonthLabel(bucket.range.from),
    };

/// The chart data for one trend, with this application's date wording on its positions.
///
/// One composition, used by the surface and asserted by its tests, so a gap cannot be
/// handled one way on screen and another way in a check. `TrendChartData.from` turns every
/// [TrendGap] into a `ChartAbsent`, which carries **no amount at all** — never zero, never
/// the neighbours' average, never carried forward (D-263, D-268).
TrendChartData dashboardTrendChartData(TrendSeries series) =>
    TrendChartData.from(
      series,
      bucketLabel: (bucket) => dashboardBucketLabel(bucket, series.grain),
    );

// ── Custom dates from a calendar picker ─────────────────────────────────────

/// `19 Sep 2026`, as every reporting surface prints a day.
String dashboardDateLabel(BusinessDate date) => reportDateLabel(date);

/// The range a date-range picker opens on: the custom range already chosen, otherwise the
/// period being reported, otherwise nothing and the picker opens on today.
DateTimeRange? dashboardPickerRange(
  DashboardPeriodChoice period, {
  ReportRange? current,
}) {
  final (from, to) = switch (period) {
    DashboardCustomPeriod(:final from, :final to) => (from, to),
    DashboardRelativePeriod() when current != null => (
      current.from,
      current.to,
    ),
    _ => (null, null),
  };
  if (from == null || to == null || from > to) return null;
  return DateTimeRange(start: pnlCalendarDay(from), end: pnlCalendarDay(to));
}

/// The explicit P&L dates a calendar picker returned, or null when it was dismissed.
///
/// **Delegated, not copied.** The rule — the tapped day *is* the P&L date, read by year,
/// month and day, never converted through a timezone, UTC or the device clock, and the two
/// ends never swapped — is one rule and has one implementation (D-229, D-250). A second
/// copy here is exactly the drift D-119 and D-131 each record.
({BusinessDate from, BusinessDate to})? dashboardCustomDatesFrom(
  DateTimeRange? picked,
) => pnlCustomDatesFrom(picked);

// ── Opening behaviour ───────────────────────────────────────────────────────

/// Brings the dashboard up to date once when a surface opens, if nothing has been asked
/// yet under this authority. Refresh repeats it on demand.
void dashboardRefreshWhenOpened(WidgetRef ref, bool Function() mounted) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted()) return;
    if (ref.read(dashboardSyncProvider).phase == DashboardSyncPhase.idle) {
      ref.read(dashboardSyncProvider.notifier).refresh();
    }
  });
}
