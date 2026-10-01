/// What both P&L surfaces say, decided once (Phase 5 Slices 8 and 9).
///
/// Windows and Android lay a profit & loss out differently. They must never *describe* one
/// differently: two copies of "which message does this refusal get" would drift, the way a
/// duplicated status mapping and a duplicated join both had when they were found (D-119,
/// D-131). So the words live here, and each surface only arranges them.
///
/// ## What this file does not do
///
/// It computes no figure, decides no authority, derives no business date and judges no
/// coverage or freshness. Each arrives decided — from `Pnl.compute`, `PnlAuthority`, the
/// resolver in `pnl_providers.dart`, the coverage oracle and the reporting envelope — and is
/// only turned into wording and display formatting here. A structural guard holds that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/formatting/report_dates.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_line_order.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

// ── Messages shown instead of a figure ─────────────────────────────────────

/// What a message's single action does. The surface binds it to the synchroniser.
enum PnlMessageAction {
  synchronise('Synchronise'),
  download('Download required data'),
  retryDownload('Try again');

  const PnlMessageAction(this.label);
  final String label;
}

/// A message shown in place of a profit & loss. Never a figure, never ₹0 (D-163).
@immutable
final class PnlStateMessage {
  const PnlStateMessage({
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
  final PnlMessageAction? action;
  final Key? actionKey;
}

const _notAuthorised = PnlStateMessage(
  key: Key('pnl-not-authorised'),
  icon: Icons.lock_outline,
  title: 'Profit & loss not available to your account',
  message:
      'A profit & loss needs report, revenue and full expense access for a property. '
      'No partial profit & loss is shown.',
);

/// The message for [view], or null when it is a computed report to be shown as figures.
///
/// [canAsk] is whether a synchroniser exists to ask the server at all.
PnlStateMessage? pnlStateMessage(
  PnlView view,
  PnlSyncStatus sync, {
  required bool canAsk,
}) => switch (view) {
  PnlNotAuthorised() => _notAuthorised,
  PnlInvalidRange() => const PnlStateMessage(
    key: Key('pnl-invalid-range'),
    icon: Icons.date_range_outlined,
    title: 'That range ends before it starts',
    message:
        'Choose a start date on or before the end date. The range is never swapped for you.',
  ),
  PnlPresetUnavailable(:final preset, :final resolution) => PnlStateMessage(
    key: const Key('pnl-preset-unavailable'),
    icon: Icons.event_busy_outlined,
    title: '${preset.label} is not available for this report',
    message: switch (resolution) {
      PresetRangesDiffer() =>
        'The properties in this report are on different business dates, so '
            '"${preset.label}" does not describe one period for all of them. Use '
            'Custom to choose the dates explicitly.',
      _ =>
        'A property\'s business-date rules could not be read on this device, so '
            '"${preset.label}" cannot be worked out for it. Use Custom to choose the '
            'dates explicitly.',
    },
  ),
  PnlReportView() when view.envelope.isComputed => null,
  PnlReportView() => _refused(view, sync, canAsk: canAsk),
};

PnlStateMessage _refused(
  PnlReportView view,
  PnlSyncStatus sync, {
  required bool canAsk,
}) {
  final revenue = view.envelope.revenueCoverage;
  final expenses = view.envelope.expenseCoverage;
  final range = pnlRangeLabel(view.range);

  if (revenue == ReportingCoverage.notAuthorised &&
      expenses == ReportingCoverage.notAuthorised) {
    return _notAuthorised;
  }

  final bothNotDownloaded =
      revenue == ReportingCoverage.notDownloaded &&
      expenses == ReportingCoverage.notDownloaded;
  final unreachable = sync.phase == PnlSyncPhase.failed && sync.failure != null;

  if (bothNotDownloaded) {
    if (sync.phase == PnlSyncPhase.downloading) {
      return PnlStateMessage(
        key: const Key('pnl-downloading'),
        icon: Icons.downloading_outlined,
        title: 'Downloading required history',
        message: 'Fetching the canonical figures for $range.',
      );
    }
    if (sync.phase == PnlSyncPhase.synchronising) {
      return PnlStateMessage(
        key: const Key('pnl-synchronising'),
        icon: Icons.sync,
        title: 'Synchronising',
        message:
            'Bringing the profit & loss for $range up to date on this device.',
      );
    }
    if (sync.phase == PnlSyncPhase.failed && sync.localFailure) {
      return PnlStateMessage(
        key: const Key('pnl-sync-local-failure'),
        icon: Icons.error_outline,
        title: sync.lastAction == PnlSyncAction.download
            ? 'Download could not start'
            : 'Synchronisation could not start',
        message: pnlLocalFailureText,
        action: !canAsk
            ? null
            : sync.lastAction == PnlSyncAction.download
            ? PnlMessageAction.retryDownload
            : PnlMessageAction.synchronise,
      );
    }
    if (sync.phase == PnlSyncPhase.failed &&
        sync.lastAction == PnlSyncAction.download) {
      return PnlStateMessage(
        key: const Key('pnl-download-failed'),
        icon: Icons.cloud_off_outlined,
        title: 'Download failed',
        message: unreachable
            ? 'A connection is required to download this history, and the server '
                  'could not be reached. Nothing is shown rather than an incomplete figure.'
            : 'The server did not provide this history. Nothing is shown rather than '
                  'an incomplete figure.',
        action: canAsk ? PnlMessageAction.retryDownload : null,
      );
    }

    final years = view.olderYears.map((y) => 'FY ${y.label}').join(', ');
    return PnlStateMessage(
      key: const Key('pnl-not-downloaded'),
      icon: Icons.download_outlined,
      title: 'Not downloaded',
      message: view.offersDownload
          ? 'This device does not hold the history for $range '
                '($years). ${unreachable || !canAsk ? 'A connection is required to download it.' : 'It can be downloaded now.'}'
          : unreachable || !canAsk
          ? 'This device does not hold the profit & loss for $range yet, and a '
                'connection is required to synchronise it.'
          : 'This device does not hold the profit & loss for $range yet.',
      action: !canAsk
          ? null
          : view.offersDownload
          ? PnlMessageAction.download
          : PnlMessageAction.synchronise,
      actionKey: view.offersDownload
          ? const Key('pnl-download')
          : const Key('pnl-synchronise'),
    );
  }

  final (key, title) = switch (view.envelope.refusalOrNull) {
    PnlRefusal.revenueUnavailable => (
      const Key('pnl-revenue-unavailable'),
      'Revenue unavailable',
    ),
    PnlRefusal.expensesUnavailable => (
      const Key('pnl-expense-unavailable'),
      'Expenses unavailable',
    ),
    _ => (
      const Key('pnl-both-unavailable'),
      'Revenue and expenses unavailable',
    ),
  };
  return PnlStateMessage(
    key: key,
    icon: Icons.report_gmailerrorred_outlined,
    title: title,
    message:
        'Revenue: ${_coverageText(revenue)}. Expenses: ${_coverageText(expenses)}. '
        'A profit & loss needs both sides complete, so no figure is shown.',
    action:
        canAsk &&
            (revenue == ReportingCoverage.notDownloaded ||
                expenses == ReportingCoverage.notDownloaded)
        ? PnlMessageAction.synchronise
        : null,
  );
}

String _coverageText(ReportingCoverage coverage) => switch (coverage) {
  ReportingCoverage.complete => 'complete',
  ReportingCoverage.notDownloaded => 'not downloaded to this device',
  ReportingCoverage.notAuthorised => 'not available to your account',
};

/// A synchronisation that failed on this device before or after asking the server.
const pnlLocalFailureText =
    'This device could not prepare or record the synchronisation, so nothing was asked '
    'of the server and nothing was changed. Nothing is shown rather than an incomplete '
    'figure. Try again; if it persists, report it.';

/// Shown when the report could not be read at all.
const pnlReadErrorMessage = PnlStateMessage(
  key: Key('pnl-read-error'),
  icon: Icons.error_outline,
  title: 'The profit & loss could not be read on this device',
  message: 'Nothing has been changed. Try again; if it persists, report it.',
);

// ── Synchronisation and freshness ───────────────────────────────────────────

/// A one-line notice about the last synchronisation, over figures already on screen.
@immutable
final class PnlNotice {
  const PnlNotice({required this.key, required this.icon, required this.text});
  final Key key;
  final IconData icon;
  final String text;
}

/// What the last synchronisation means for a report already on screen, or null.
PnlNotice? pnlSyncNotice(PnlSyncStatus sync) {
  if (sync.isRunning) {
    return PnlNotice(
      key: const Key('pnl-refreshing'),
      icon: Icons.sync,
      text: sync.phase == PnlSyncPhase.downloading
          ? 'Downloading. The figures below are as last synchronised.'
          : 'Refreshing. The figures below are as last synchronised.',
    );
  }
  if (sync.phase == PnlSyncPhase.failed && sync.localFailure) {
    return const PnlNotice(
      key: Key('pnl-sync-local-failure-notice'),
      icon: Icons.error_outline,
      text:
          'The refresh could not run on this device, so nothing was asked of the server. '
          'These figures are the complete report this device last synchronised. Refresh '
          'to try again.',
    );
  }
  if (sync.phase == PnlSyncPhase.failed) {
    return sync.failure != null
        ? const PnlNotice(
            key: Key('pnl-offline'),
            icon: Icons.cloud_off_outlined,
            text:
                'The server could not be reached. These figures are the complete report '
                'this device last synchronised.',
          )
        : const PnlNotice(
            key: Key('pnl-sync-refused'),
            icon: Icons.cloud_off_outlined,
            text:
                'The server did not accept the last synchronisation. These figures are the '
                'complete report this device last synchronised.',
          );
  }
  return null;
}

/// The freshness sentence for a computed report, as the envelope states it.
@immutable
final class PnlFreshnessLine {
  const PnlFreshnessLine({
    required this.key,
    required this.text,
    this.caution = false,
  });
  final Key key;
  final String text;
  final bool caution;
}

PnlFreshnessLine pnlFreshnessLine(
  PnlReportView view,
  Map<String, BusinessDayRule> rules,
) {
  final freshness = view.envelope.freshness;
  if (freshness == null) {
    return const PnlFreshnessLine(
      key: Key('pnl-freshness-none'),
      text:
          'Complete, but these figures do not come from one synchronisation, so no single '
          'time is stated.',
    );
  }
  final when = pnlInstantLabel(
    freshness.synchronisedAt,
    pnlDisplayZone(rules, view),
  );
  return switch (freshness.state) {
    ReportingFreshnessState.synchronised => PnlFreshnessLine(
      key: const Key('pnl-freshness-synchronised'),
      text: 'Synchronised as of $when',
    ),
    ReportingFreshnessState.serverHasNewer => PnlFreshnessLine(
      key: const Key('pnl-freshness-server-newer'),
      text:
          'Synchronised as of $when · the server has newer changes. Refresh to update.',
      caution: true,
    ),
  };
}

/// The zone a server-confirmed time is displayed in: the first property in scope's own
/// zone. Display only; nothing is derived from it.
String pnlDisplayZone(Map<String, BusinessDayRule> rules, PnlReportView view) {
  final sorted = rules.keys.toList()..sort();
  final unit = switch (view.scope) {
    PnlUnitScope(:final businessUnitId) => businessUnitId,
    PnlConsolidatedScope() => sorted.isEmpty ? null : sorted.first,
  };
  return rules[unit]?.timeZoneId ?? 'UTC';
}

/// Brings the report up to date once when a surface opens, if nothing has been asked yet
/// in this session. Refresh and pull-to-refresh repeat it on demand.
void pnlRefreshWhenOpened(WidgetRef ref, bool Function() mounted) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted()) return;
    if (ref.read(pnlSyncProvider).phase == PnlSyncPhase.idle) {
      ref.read(pnlSyncProvider.notifier).refresh();
    }
  });
}

// ── Category lines, in display order ────────────────────────────────────────

/// Revenue lines ordered by property, then category. Order only; nothing is summed.
///
/// The rule lives in `domain/finance` ([PnlLineOrder]) so the exports order lines exactly
/// as the screen does (Phase 7 Slice 3).
List<RevenueCategoryLine> pnlRevenueLinesInOrder(PnlResult result) =>
    PnlLineOrder.revenue(result);

/// Expense lines ordered by property, then category. Order only; nothing is summed.
List<ExpenseHierarchyLine> pnlExpenseLinesInOrder(PnlResult result) =>
    PnlLineOrder.expenses(result);

// ── Custom dates from a calendar picker ─────────────────────────────────────

/// The explicit P&L dates a date-range picker returned, or null when it was dismissed.
///
/// The calendar day the reader tapped **is** the P&L date: only its year, month and day
/// are read. Nothing is converted through a timezone, UTC or the device clock, and the two
/// ends are never swapped — a range that ends before it starts is passed on as it is and
/// refused by the resolver ([PnlInvalidRange]).
({BusinessDate from, BusinessDate to})? pnlCustomDatesFrom(
  DateTimeRange? picked,
) => picked == null
    ? null
    : (
        from: BusinessDate.of(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        to: BusinessDate.of(picked.end.year, picked.end.month, picked.end.day),
      );

/// A calendar day for a picker to open on. Year, month and day only.
DateTime pnlCalendarDay(BusinessDate date) =>
    DateTime(date.year, date.month, date.day);

// ── Display formatting ──────────────────────────────────────────────────────

// One place in the application turns a reporting date into words
// (`core/formatting/report_dates.dart`). These keep their names so every Phase 5 call
// site and assertion is untouched, and they delegate rather than holding a second month
// table (D-232's rule, applied to dates).

String pnlDateLabel(BusinessDate d) => reportDateLabel(d);

String pnlRangeLabel(ReportRange range) => reportRangeLabel(range);

String pnlInstantLabel(DateTime instant, String zone) =>
    reportInstantLabel(instant, zone);
