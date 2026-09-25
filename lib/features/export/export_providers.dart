/// The export and print actions, bound to the session (Phase 7 Slices 6–8).
///
/// ## What is exported is what the screen holds
///
/// An action takes the report its screen already read from the canonical cache — the
/// Profit & Loss view, or the dashboard the Analytics sections share — under the same
/// identity check the screen makes before it shows anything. It never starts a
/// synchronisation or a download, so it works offline whenever the report is complete on
/// this device, and a report that is not complete is refused with the screen's reason
/// (§51.6).
///
/// ## Authority is decided three times
///
/// Before the button is offered, before the document is built, and once more after any
/// dialog closes and before the bytes leave the app. Authority can change while a Save As
/// dialog is open; a file is never written, printed or shared on the strength of a
/// decision the person no longer qualifies for.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/export/export_file_save.dart';
import 'package:krishna_mis/features/export/export_pipeline.dart';
import 'package:krishna_mis/features/export/export_print.dart';
import 'package:krishna_mis/features/export/export_share.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_presentation.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:meta/meta.dart';

// ── Inputs ──────────────────────────────────────────────────────────────────

/// The bundled Noto Sans, read once from the application bundle (D-295). Never fetched.
final exportPdfFontsProvider = FutureProvider<ExportPdfFonts>((ref) async {
  final regular = await rootBundle.load(exportPdfRegularFontAsset);
  final bold = await rootBundle.load(exportPdfBoldFontAsset);
  return ExportPdfFonts.fromBytes(regular: regular, bold: bold);
});

/// Where a Windows export is saved. Overridden in tests.
final exportFileSaverProvider = Provider<ExportFileSaver>(
  (ref) => ExportFileSaver(pickLocation: fileSelectorSaveLocation),
);

/// Where a Windows print goes: the native dialog. Overridden in tests.
final exportPrinterProvider = Provider<ExportPrinter>(
  (ref) => printingLayoutPdf,
);

/// Names from the cached master graph, with the screen's own fallback words (D-035). A
/// master this device does not hold is described, never exported as its id.
final class MasterGraphExportLabels implements ExportLabels {
  const MasterGraphExportLabels(this.graph);

  final MasterGraph? graph;

  @override
  String businessUnit(String businessUnitId) =>
      graph?.businessUnit(businessUnitId)?.name ?? 'Property';

  @override
  String revenueCategory(String revenueCategoryId) =>
      graph?.revenueCategory(revenueCategoryId)?.name ??
      'Revenue category not on this device';

  @override
  String expenseCategory(String? categoryId) => categoryId == null
      ? 'Uncategorised'
      : graph?.expenseCategory(categoryId)?.name ??
            'Expense category not on this device';

  @override
  String department(String? departmentId) => departmentId == null
      ? 'Department'
      : graph?.department(departmentId)?.name ?? 'Department';

  @override
  String section(String? sectionId) => sectionId == null
      ? 'Section'
      : graph?.section(sectionId)?.name ?? 'Section';

  @override
  String scope(ExportScope scope) => scope.isConsolidated
      ? dashboardConsolidatedScopeLabel
      : businessUnit(scope.businessUnitIds.single);
}

// ── The report each output is made from ─────────────────────────────────────

/// The report [report] would be exported from, as [principal] may be shown it now — or
/// null while there is none, or while the screen's report is still being read.
///
/// A report re-reading keeps its previous value while it loads; that value may describe a
/// selection the reader has just changed, so it is not offered for export until the new
/// read lands.
ExportSource? exportSourceFor(Ref ref, ExportReport report) => exportSourceFrom(
  report: report,
  principal: ref.read(principalProvider),
  rules: ref.read(businessDayRulesProvider).value ?? const {},
  pnl: ref.read(pnlViewProvider),
  pnlPeriod: ref.read(pnlSelectionProvider).period,
  dashboard: ref.read(dashboardViewProvider),
);

/// [exportSourceFor] over values a surface already watches — one rule for what the
/// Export Centre shows and for what an action then uses.
ExportSource? exportSourceFrom({
  required ExportReport report,
  required Principal principal,
  required Map<String, BusinessDayRule> rules,
  required AsyncValue<PnlView> pnl,
  required PnlPeriodChoice pnlPeriod,
  required AsyncValue<DashboardState> dashboard,
}) {
  switch (report) {
    case ExportReport.profitAndLoss:
      if (pnl.isLoading) return null;
      final view = pnlViewShownTo(pnl, principal);
      if (view is! PnlReportView) return null;
      return PnlExportSource(
        view,
        periodName: pnlPeriodName(pnlPeriod),
        displayZone: pnlDisplayZone(rules, view),
      );
    case ExportReport.revenueAnalysis:
    case ExportReport.expenseAnalysis:
    case ExportReport.businessComparison:
      if (dashboard.isLoading) return null;
      final state = dashboardShownTo(dashboard, principal);
      if (state is! DashboardReady) return null;
      return DashboardExportSource(
        state,
        periodName: state.pair.kind.label,
        displayZone: dashboardDisplayZone(rules, state),
      );
  }
}

/// How the P&L period is named on an exported document.
String pnlPeriodName(PnlPeriodChoice period) => switch (period) {
  PnlPresetPeriod(:final preset) => preset.label,
  PnlCustomPeriod() => 'Custom',
};

// ── The action and its outcome ──────────────────────────────────────────────

enum ExportActionKind { save, print, share }

/// What happened to the last action.
@immutable
sealed class ExportActionResult {
  const ExportActionResult();
}

final class ExportActionSaved extends ExportActionResult {
  const ExportActionSaved(this.fileName);
  final String fileName;
}

/// Handed to the print dialog or the share sheet. What the person did there is theirs.
final class ExportActionHandedOver extends ExportActionResult {
  const ExportActionHandedOver(this.kind);
  final ExportActionKind kind;
}

/// The person cancelled. Nothing was written, printed or shared, and nothing is wrong.
final class ExportActionCancelled extends ExportActionResult {
  const ExportActionCancelled(this.kind);
  final ExportActionKind kind;
}

final class ExportActionRefused extends ExportActionResult {
  const ExportActionRefused(this.refusal);
  final ExportRenderRefused refusal;
}

/// Access changed while the action was under way; the file was discarded.
final class ExportActionAbandoned extends ExportActionResult {
  const ExportActionAbandoned();
}

final class ExportActionSaveFailed extends ExportActionResult {
  const ExportActionSaveFailed(this.failure);
  final ExportSaveFailure failure;
}

/// The print dialog or the share sheet could not be opened.
final class ExportActionHandOverFailed extends ExportActionResult {
  const ExportActionHandOverFailed(this.kind);
  final ExportActionKind kind;
}

/// Something failed that is not the person's to fix — the file was not made.
final class ExportActionError extends ExportActionResult {
  const ExportActionError();
}

@immutable
final class ExportActionStatus {
  const ExportActionStatus({this.running, this.last});

  /// The report an action is running for, if any.
  final ExportReport? running;

  /// The last outcome, and the report it was for.
  final ({ExportReport report, ExportActionResult result})? last;

  bool get isRunning => running != null;
}

final exportActionProvider =
    NotifierProvider<ExportActionController, ExportActionStatus>(
      ExportActionController.new,
    );

class ExportActionController extends Notifier<ExportActionStatus> {
  @override
  ExportActionStatus build() {
    // A new person, a new status: an outcome the previous person caused is not this
    // person's to read (D-074).
    ref.watch(sessionProvider.select((s) => s.principal.userId));
    return const ExportActionStatus();
  }

  /// Saves [report] as [format], where the person chooses (Windows).
  Future<void> save(ExportReport report, ExportFileFormat format) => _run(
    report,
    ExportAction.export,
    format,
    (rendered, stillPermitted) async {
      final outcome = await ref
          .read(exportFileSaverProvider)
          .save(
            bytes: rendered.bytes,
            suggestedName: rendered.fileName,
            format: rendered.format,
            beforeWrite: stillPermitted,
          );
      if (!stillPermitted()) return const ExportActionAbandoned();
      return switch (outcome) {
        ExportSaved(:final fileName) => ExportActionSaved(fileName),
        ExportSaveCancelled() => const ExportActionCancelled(
          ExportActionKind.save,
        ),
        ExportSaveFailed(:final failure) => ExportActionSaveFailed(failure),
      };
    },
  );

  /// Prints [report] through the native Windows print dialog, from the same PDF bytes
  /// Save PDF writes (§51.5).
  Future<void> print(ExportReport report) => _run(
    report,
    ExportAction.print,
    ExportFileFormat.pdf,
    (rendered, stillPermitted) async {
      try {
        final sent = await ref.read(exportPrinterProvider)(
          bytes: rendered.bytes,
          jobName: _withoutExtension(rendered.fileName),
        );
        return sent
            ? const ExportActionHandedOver(ExportActionKind.print)
            : const ExportActionCancelled(ExportActionKind.print);
      } on Object {
        return const ExportActionHandOverFailed(ExportActionKind.print);
      }
    },
  );

  /// Shares the P&L PDF through the Android share sheet (D-293). The same bytes Save PDF
  /// writes on Windows; `reports.export` is the capability, as for any export.
  Future<void> share(
    ExportReport report,
  ) => _run(report, ExportAction.export, ExportFileFormat.pdf, (
    rendered,
    stillPermitted,
  ) async {
    try {
      // Earlier shares leave their files in the private cache; they go now, before this
      // one is written beside them.
      removeEarlierShares(await ref.read(exportShareCacheRootProvider.future));
    } on Object {
      // A cache that cannot be listed does not stop the share.
    }
    if (!stillPermitted()) return const ExportActionAbandoned();
    try {
      final opened = await ref.read(exportSharerProvider)(
        bytes: rendered.bytes,
        fileName: rendered.fileName,
      );
      return opened
          ? const ExportActionHandedOver(ExportActionKind.share)
          : const ExportActionHandOverFailed(ExportActionKind.share);
    } on Object {
      return const ExportActionHandOverFailed(ExportActionKind.share);
    }
  });

  /// Renders, then hands the bytes to [deliver] while the action is still permitted.
  Future<void> _run(
    ExportReport report,
    ExportAction action,
    ExportFileFormat format,
    Future<ExportActionResult> Function(
      ExportRendered rendered,
      bool Function() stillPermitted,
    )
    deliver,
  ) async {
    if (state.isRunning) return;
    final principal = ref.read(principalProvider);
    final source = exportSourceFor(ref, report);
    if (source == null) return;

    // The same person, the same reading authority, and the action still permitted for the
    // same scope — decided again against whoever is signed in now.
    bool stillPermitted() {
      if (!ref.mounted) return false;
      final now = ref.read(principalProvider);
      return now.userId == principal.userId &&
          PnlAuthority.readKey(now) == PnlAuthority.readKey(principal) &&
          ExportAuthority.offers(
            now,
            action: action,
            report: report,
            scope: source.scope,
          );
    }

    state = ExportActionStatus(running: report, last: state.last);
    ExportActionResult result;
    try {
      final graph = ref.read(masterGraphProvider).value;
      final rendered = await ExportPipeline.render(
        principal: principal,
        action: action,
        report: report,
        format: format,
        source: source,
        labels: MasterGraphExportLabels(graph),
        fonts: () => ref.read(exportPdfFontsProvider.future),
        generatedOnDeviceAt: ref.read(reportingClockProvider)(),
      );
      result = switch (rendered) {
        final ExportRenderRefused refused => ExportActionRefused(refused),
        ExportRendered() when !stillPermitted() =>
          const ExportActionAbandoned(),
        final ExportRendered r => await deliver(r, stillPermitted),
      };
    } on Object {
      // Never a half-truth: the file was not made, and the report is untouched.
      result = const ExportActionError();
    }
    if (!ref.mounted) return;
    // A different person by now: their status is not this outcome.
    if (ref.read(principalProvider).userId != principal.userId) return;
    state = ExportActionStatus(last: (report: report, result: result));
  }
}

String _withoutExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? fileName : fileName.substring(0, dot);
}
