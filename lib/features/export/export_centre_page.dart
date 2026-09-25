/// The Windows Reports destination: the Export Centre (Phase 7 Slice 6; D-297).
///
/// It lists the four exportable reports (D-290) and, for each, what would be exported —
/// the scope, the period and how current the figures are — and only the actions the person
/// may take for that scope ([ExportAuthority], D-291). No role name is read.
///
/// ## Not a second P&L, not a second Analytics
///
/// It holds no report state of its own and shows no figure. Each output is exported from
/// the report its own screen already holds, with that screen's scope and period; to change
/// them, the person opens the report in Analytics. A report that is not complete on this
/// device is described in the screen's own words and offers no action.
///
/// ## Nothing here synchronises
///
/// The Export Centre never starts a refresh or a download. An export is made from what
/// the device holds, so it works offline, and a missing report stays missing (§51.6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_routes.dart';
import 'package:krishna_mis/core/design/components/section_header.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_navigation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/export/export_file_save.dart';
import 'package:krishna_mis/features/export/export_pipeline.dart';
import 'package:krishna_mis/features/export/export_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_presentation.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

class ExportCentrePage extends ConsumerWidget {
  const ExportCentrePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final principal = ref.watch(principalProvider);
    final rules = ref.watch(businessDayRulesProvider).value ?? const {};
    final pnl = ref.watch(pnlViewProvider);
    final pnlPeriod = ref.watch(pnlSelectionProvider.select((s) => s.period));
    final dashboard = ref.watch(dashboardViewProvider);
    final status = ref.watch(exportActionProvider);

    ExportSource? source(ExportReport report) => exportSourceFrom(
      report: report,
      principal: principal,
      rules: rules,
      pnl: pnl,
      pnlPeriod: pnlPeriod,
      dashboard: dashboard,
    );

    final labels = MasterGraphExportLabels(
      ref.watch(masterGraphProvider).value,
    );
    // The same qualifying scopes the P&L and the dashboard offer. A person with none sees
    // the neutral line and no report, property or action (D-259).
    final options = pnlScopeOptionsShownTo(
      ref.watch(pnlScopeOptionsProvider),
      principal,
    );
    final anyReadable = options == null || !options.isEmpty;

    return ListView(
      key: const Key('export-centre'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SectionHeader(
          title: 'Reports',
          subtitle:
              'Save a report as PDF or Excel, exactly as its screen shows it. The scope '
              'and period are the ones chosen in Analytics.',
        ),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Exports use the figures already on this device. Nothing is synchronised to '
          'make one, so a report that is not complete here cannot be exported until it '
          'is.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!anyReadable)
          const _Notice(
            key: Key('export-centre-not-authorised'),
            icon: Icons.lock_outline,
            title: 'Reports are not available for your access.',
            message:
                'Exporting a report needs the access to read it first. No report is '
                'listed here.',
          )
        else
          for (final report in ExportReport.values)
            _ReportCard(
              report: report,
              source: source(report),
              principal: principal,
              rules: rules,
              labels: labels,
              pnl: pnl,
              dashboard: dashboard,
              status: status,
            ),
      ],
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({
    required this.report,
    required this.source,
    required this.principal,
    required this.rules,
    required this.labels,
    required this.pnl,
    required this.dashboard,
    required this.status,
  });

  final ExportReport report;
  final ExportSource? source;
  final Principal principal;
  final Map<String, BusinessDayRule> rules;
  final MasterGraphExportLabels labels;
  final AsyncValue<PnlView> pnl;
  final AsyncValue<DashboardState> dashboard;
  final ExportActionStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = this.source;
    final name = report.name;
    final running = status.running == report;
    final last = status.last?.report == report ? status.last!.result : null;

    final (String? covers, String? freshness, _Notice? notice) = _describe(ref);
    ExportDecision? decide(ExportAction action) => source == null
        ? null
        : ExportPipeline.decide(
            principal,
            action: action,
            report: report,
            source: source,
          );
    final decision = decide(ExportAction.export);
    final computed = source != null && source.isComputed;
    final offered = computed && decision is ExportPermitted;
    // Print is its own capability (D-291): offered only with reports.print, and only for
    // a report whose PDF exists.
    final printOffered =
        computed &&
        exportPrintable(report) &&
        decide(ExportAction.print) is ExportPermitted;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: DecoratedBox(
        key: Key('export-$name'),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.allMedium,
          border: Border.all(color: AppColors.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      exportReportTitle(report),
                      style: AppTypography.subheading,
                    ),
                  ),
                  TextButton(
                    key: Key('export-$name-open'),
                    onPressed: () => _openInAnalytics(context, ref),
                    child: const Text('Open in Analytics'),
                  ),
                ],
              ),
              if (covers != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  covers,
                  key: Key('export-$name-covers'),
                  style: AppTypography.body,
                ),
              ],
              if (freshness != null)
                Text(
                  freshness,
                  key: Key('export-$name-freshness'),
                  style: AppTypography.bodyMuted,
                ),
              if (notice != null) ...[
                const SizedBox(height: AppSpacing.sm),
                notice,
              ],
              if (computed && !offered && !printOffered)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _refusalLine((decision! as ExportRefused).reason),
                    key: Key('export-$name-not-offered'),
                    style: AppTypography.bodyMuted,
                  ),
                ),
              if (offered || printOffered) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (offered)
                      for (final format in exportFormatsFor(report))
                        OutlinedButton.icon(
                          key: Key('export-$name-${format.extension}'),
                          onPressed: status.isRunning
                              ? null
                              : () => ref
                                    .read(exportActionProvider.notifier)
                                    .save(report, format),
                          icon: Icon(
                            format == ExportFileFormat.pdf
                                ? Icons.picture_as_pdf_outlined
                                : Icons.table_chart_outlined,
                            size: 18,
                          ),
                          label: Text(
                            format == ExportFileFormat.pdf
                                ? 'Save PDF'
                                : 'Save Excel',
                          ),
                        ),
                    if (printOffered)
                      OutlinedButton.icon(
                        key: Key('export-$name-print'),
                        onPressed: status.isRunning
                            ? null
                            : () => ref
                                  .read(exportActionProvider.notifier)
                                  .print(report),
                        icon: const Icon(Icons.print_outlined, size: 18),
                        label: const Text('Print'),
                      ),
                  ],
                ),
              ],
              if (running)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Preparing the file…',
                    key: Key('export-$name-running'),
                    style: AppTypography.bodyMuted,
                  ),
                ),
              if (last != null && !running)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    exportActionMessage(last),
                    key: Key('export-$name-outcome'),
                    style: AppTypography.body,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// What would be exported, how current it is, or why there is nothing to export.
  (String?, String?, _Notice?) _describe(WidgetRef ref) {
    final source = this.source;
    switch (source) {
      case PnlExportSource(:final view):
        final message = pnlStateMessage(
          view,
          ref.watch(pnlSyncProvider),
          canAsk: false,
        );
        return (
          _coversLine(source, view.range),
          message == null ? pnlFreshnessLine(view, rules).text : null,
          message == null
              ? null
              : _Notice(
                  key: Key('export-${report.name}-unavailable'),
                  icon: message.icon,
                  title: message.title,
                  message: message.message,
                ),
        );
      case DashboardExportSource(:final ready):
        final presentation = dashboardPresentation(
          state: dashboard,
          sync: ref.watch(dashboardSyncProvider),
          principal: principal,
        );
        final message = dashboardMessageFor(
          presentation,
          ref.watch(dashboardSyncProvider),
          canAsk: false,
        );
        return (
          _coversLine(source, ready.pair.current),
          message == null ? dashboardFreshnessLine(ready, rules).text : null,
          message == null
              ? null
              : _Notice(
                  key: Key('export-${report.name}-unavailable'),
                  icon: message.icon,
                  title: message.title,
                  message: message.message,
                ),
        );
      case null:
        return (null, null, _unresolvedNotice(ref));
    }
  }

  String _coversLine(ExportSource source, ReportRange range) {
    final scope = labels.scope(source.scope);
    return '$scope · ${source.periodName} · ${exportRangeLabel(range)}';
  }

  /// The screen's own sentence when its report is not a report at all — an unauthorised
  /// scope, a period that does not resolve — or a quiet line while it is being read.
  _Notice? _unresolvedNotice(WidgetRef ref) {
    final key = Key('export-${report.name}-unavailable');
    if (report == ExportReport.profitAndLoss) {
      final view = pnlViewShownTo(pnl, principal);
      if (view == null) return null;
      final message = pnlStateMessage(
        view,
        ref.watch(pnlSyncProvider),
        canAsk: false,
      );
      return message == null
          ? null
          : _Notice(
              key: key,
              icon: message.icon,
              title: message.title,
              message: message.message,
            );
    }
    final message = dashboardMessageFor(
      dashboardPresentation(
        state: dashboard,
        sync: ref.watch(dashboardSyncProvider),
        principal: principal,
      ),
      ref.watch(dashboardSyncProvider),
      canAsk: false,
    );
    return message == null
        ? null
        : _Notice(
            key: key,
            icon: message.icon,
            title: message.title,
            message: message.message,
          );
  }

  void _openInAnalytics(BuildContext context, WidgetRef ref) {
    ref.read(analyticsSectionProvider.notifier).select(switch (report) {
      ExportReport.profitAndLoss => AnalyticsSection.profitAndLoss,
      ExportReport.revenueAnalysis => AnalyticsSection.revenue,
      ExportReport.expenseAnalysis => AnalyticsSection.expenses,
      ExportReport.businessComparison => AnalyticsSection.businessComparison,
    });
    context.go(AppRoutes.analytics);
  }
}

String _refusalLine(ExportRefusal reason) => switch (reason) {
  ExportRefusal.requiresConsolidatedScope =>
    'Business Comparison compares both properties. Choose both properties in '
        'Analytics to export it.',
  ExportRefusal.noViewAuthority || ExportRefusal.noProperties =>
    'This report is not available to your account for this scope.',
  ExportRefusal.noActionCapability =>
    'Your account can read this report but not export it.',
};

/// What the last action came to, in plain words.
String exportActionMessage(ExportActionResult result) => switch (result) {
  ExportActionSaved(:final fileName) => 'Saved $fileName.',
  ExportActionHandedOver(kind: ExportActionKind.print) =>
    'Sent to the Windows print dialog.',
  ExportActionHandedOver() => 'Opened the share sheet.',
  ExportActionCancelled(kind: ExportActionKind.print) =>
    'Printing cancelled. Nothing was printed.',
  ExportActionCancelled(kind: ExportActionKind.share) =>
    'Sharing cancelled. Nothing was shared.',
  ExportActionCancelled() => 'Cancelled. Nothing was saved.',
  ExportActionAbandoned() =>
    'Your access changed while the file was being prepared. Nothing was saved.',
  ExportActionError() => 'The file could not be made. Nothing was saved.',
  ExportActionHandOverFailed(kind: ExportActionKind.print) =>
    'The print dialog could not be opened. Nothing was printed.',
  ExportActionHandOverFailed() =>
    'The share sheet could not be opened. Nothing was shared.',
  ExportActionSaveFailed(:final failure) => switch (failure) {
    ExportSaveFailure.dialogUnavailable =>
      'The Save As dialog could not be opened. Nothing was saved.',
    ExportSaveFailure.nameTaken =>
      'A file with that name already exists and was not replaced. Save again and '
          'choose another name.',
    ExportSaveFailure.permissionDenied =>
      'Windows did not allow saving there. Choose another folder.',
    ExportSaveFailure.fileInUse =>
      'That file is open in another program. Close it, then save again.',
    ExportSaveFailure.writeFailed =>
      'The file could not be written. Nothing was saved under that name.',
  },
  ExportActionRefused(:final refusal) => switch (refusal.reason) {
    ExportRenderRefusal.notThisPersonsReport =>
      'The report on screen was read for an earlier session. Open it again, then '
          'export.',
    ExportRenderRefusal.notAuthorised => _refusalLine(
      refusal.authority ?? ExportRefusal.noViewAuthority,
    ),
    ExportRenderRefusal.reportUnavailable =>
      'This report is not complete on this device, so nothing was exported.',
    ExportRenderRefusal.documentNotBuilt =>
      'This report could not be laid out exactly for export. Refresh it in '
          'Analytics, then export again.',
    ExportRenderRefusal.formatNotOffered =>
      'This report is not available in that format.',
  },
};

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.allMedium,
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.subheading),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: AppTypography.bodyMuted),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
