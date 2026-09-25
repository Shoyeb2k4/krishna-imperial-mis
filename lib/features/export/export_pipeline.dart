/// From an authorised canonical report to the bytes of one file (Phase 7 Slices 6–9;
/// D-299, `ARCHITECTURE.md` §51.1).
///
/// ```
///     the report the screen already holds  (PnlReportView / DashboardReady)
///       → is it this person's?             (the same identity the screen checks)
///       → ExportAuthority.decide           (view authority ∩ the action capability)
///       → is it computed?                  (an unavailable report stays unavailable)
///       → ExportDocuments.*                (the document model; copies, derives nothing)
///       → the PDF renderer or the workbook (lays out; derives nothing)
/// ```
///
/// **Nothing here reads storage, the network or a clock, and nothing here synchronises.**
/// The caller hands over the report its screen already read from the canonical cache, the
/// fonts, the labels and the device's generation time. A report that is not complete on
/// this device is refused with the screen's own reason; it is never fetched, and missing
/// data never becomes ₹0 (§51.6).
///
/// The same PDF bytes are what Windows saves, what Windows prints and what Android shares
/// (§51.5): there is one renderer per format, and no print or share layout.
library;

import 'dart:typed_data';

import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/export/pdf/pnl_pdf.dart';
import 'package:krishna_mis/core/export/workbook/pnl_workbook.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

/// The two file formats.
enum ExportFileFormat {
  pdf('pdf', 'PDF document'),
  xlsx('xlsx', 'Excel workbook');

  const ExportFileFormat(this.extension, this.label);

  /// Without the dot.
  final String extension;
  final String label;
}

/// Which formats a report is exported in on Windows (D-290). Android shares the P&L PDF
/// only (D-293), and decides that itself.
List<ExportFileFormat> exportFormatsFor(ExportReport report) => const [
  ExportFileFormat.pdf,
  ExportFileFormat.xlsx,
];

// ── The canonical report a surface already holds ────────────────────────────

/// The report to export, exactly as its screen read it.
sealed class ExportSource {
  const ExportSource({required this.periodName, required this.displayZone});

  /// How the reader chose the period — "This Month", "Month to date", "Custom".
  final String periodName;

  /// The zone instants are displayed in, as the screen displays them. Display only.
  final String displayZone;

  /// The properties the report covers.
  ExportScope get scope;

  /// Whether this report was assembled for [principal] — the same identity rule the
  /// screen uses before it shows anything (D-231, D-267).
  bool belongsTo(Principal principal);

  bool get isComputed;
}

/// The P&L the Profit & Loss screen holds.
final class PnlExportSource extends ExportSource {
  const PnlExportSource(
    this.view, {
    required super.periodName,
    required super.displayZone,
  });

  final PnlReportView view;

  @override
  ExportScope get scope => ExportScope(view.envelope.scope.businessUnitIds);

  @override
  bool belongsTo(Principal principal) => view.viewerUserId == principal.userId;

  @override
  bool get isComputed => view.envelope.isComputed;
}

/// The dashboard the Analytics sections hold.
final class DashboardExportSource extends ExportSource {
  const DashboardExportSource(
    this.ready, {
    required super.periodName,
    required super.displayZone,
  });

  final DashboardReady ready;

  @override
  ExportScope get scope => ExportScope(ready.view.scope.businessUnitIds);

  @override
  bool belongsTo(Principal principal) =>
      ready.authorityKey == PnlAuthority.readKey(principal);

  @override
  bool get isComputed => ready.view.isComputed;
}

// ── The answer ──────────────────────────────────────────────────────────────

/// Why no file was made.
enum ExportRenderRefusal {
  /// The report on hand was assembled for somebody else, or under authority that has
  /// since changed. Nothing from it is used.
  notThisPersonsReport,

  /// View authority or the action capability is missing for this scope.
  notAuthorised,

  /// The report is not complete on this device. It is not fetched to fill the gap.
  reportUnavailable,

  /// The document could not be built — for example, a consolidated result the domain
  /// could not split for a Business Comparison.
  documentNotBuilt,

  /// This report is not produced in this format.
  formatNotOffered,
}

sealed class ExportRender {
  const ExportRender();
}

final class ExportRendered extends ExportRender {
  const ExportRendered({
    required this.bytes,
    required this.fileName,
    required this.format,
    required this.permit,
  });

  final Uint8List bytes;

  /// `KrishnaImperialMIS_<Report>_<Scope>_<from>_<to>.<ext>` — readable, never an id.
  final String fileName;
  final ExportFileFormat format;

  /// What was permitted. The delivery layer decides again before it hands the bytes on.
  final ExportPermitted permit;
}

final class ExportRenderRefused extends ExportRender {
  const ExportRenderRefused(this.reason, {this.authority, this.build});

  final ExportRenderRefusal reason;

  /// The authority's reason, when [reason] is [ExportRenderRefusal.notAuthorised].
  final ExportRefusal? authority;

  /// The builder's reason, when [reason] is [ExportRenderRefusal.documentNotBuilt].
  final ExportBuildRefusal? build;
}

// ── The pipeline ────────────────────────────────────────────────────────────

abstract final class ExportPipeline {
  /// The authority decision for [source], exactly as [render] takes it — so a surface can
  /// never offer an action the pipeline would then refuse.
  static ExportDecision decide(
    Principal principal, {
    required ExportAction action,
    required ExportReport report,
    required ExportSource source,
  }) => ExportAuthority.decide(
    principal,
    action: action,
    report: report,
    scope: source.scope,
  );

  /// The bytes of [report] in [format], or why there are none.
  ///
  /// [fonts] is called only when a PDF is actually made, after authority has been
  /// decided, so a refused export loads nothing.
  static Future<ExportRender> render({
    required Principal principal,
    required ExportAction action,
    required ExportReport report,
    required ExportFileFormat format,
    required ExportSource source,
    required ExportLabels labels,
    required Future<ExportPdfFonts> Function() fonts,
    required DateTime generatedOnDeviceAt,
  }) async {
    if (!source.belongsTo(principal)) {
      return const ExportRenderRefused(
        ExportRenderRefusal.notThisPersonsReport,
      );
    }
    // Authority first: nothing is built, loaded or written for a refused scope (§51.3).
    final decision = decide(
      principal,
      action: action,
      report: report,
      source: source,
    );
    final ExportPermitted permit;
    switch (decision) {
      case ExportRefused(:final reason):
        return ExportRenderRefused(
          ExportRenderRefusal.notAuthorised,
          authority: reason,
        );
      case final ExportPermitted p:
        permit = p;
    }
    if (!exportFormatsFor(report).contains(format)) {
      return const ExportRenderRefused(ExportRenderRefusal.formatNotOffered);
    }
    if (!source.isComputed) {
      return const ExportRenderRefused(ExportRenderRefusal.reportUnavailable);
    }

    final context = ExportContext(
      permit: permit,
      labels: labels,
      periodName: source.periodName,
      generatedOnDeviceAt: generatedOnDeviceAt,
      timeZoneId: source.displayZone,
      freshness: switch (source) {
        PnlExportSource(:final view) => view.envelope.freshness,
        DashboardExportSource(:final ready) => ready.freshness,
      },
    );

    final build = _build(context, report, source);
    switch (build) {
      case ExportNotBuilt(:final reason):
        return ExportRenderRefused(
          ExportRenderRefusal.documentNotBuilt,
          build: reason,
        );
      case ExportBuilt(:final document):
        final built = document;
        final bytes = await _bytes(built, format, fonts);
        if (bytes == null) {
          return const ExportRenderRefused(
            ExportRenderRefusal.formatNotOffered,
          );
        }
        return ExportRendered(
          bytes: bytes,
          fileName: exportFileName(built.header, extension: format.extension),
          format: format,
          permit: permit,
        );
    }
  }

  static ExportBuild<ExportDocument> _build(
    ExportContext context,
    ExportReport report,
    ExportSource source,
  ) {
    switch (source) {
      case PnlExportSource(:final view):
        if (report != ExportReport.profitAndLoss) {
          return const ExportNotBuilt(
            ExportBuildRefusal.permitForAnotherReport,
          );
        }
        return ExportDocuments.profitAndLoss(
          context,
          view.envelope.resultOrNull!,
        );
      case DashboardExportSource(:final ready):
        final view = ready.view;
        final result = view.resultOrNull!;
        return switch (report) {
          ExportReport.profitAndLoss => const ExportNotBuilt(
            ExportBuildRefusal.permitForAnotherReport,
          ),
          ExportReport.revenueAnalysis => ExportDocuments.revenueAnalysis(
            context,
            result: result,
            comparison: view.comparison,
            trends: view.trends,
            revenueMix: view.topRevenueCategories,
          ),
          ExportReport.expenseAnalysis => ExportDocuments.expenseAnalysis(
            context,
            result: result,
            comparison: view.comparison,
            trends: view.trends,
            topExpenseCategories: view.topExpenseCategories,
            departmentSpending: view.departmentSpending,
          ),
          ExportReport.businessComparison => ExportDocuments.businessComparison(
            context,
            result: result,
            comparison: view.comparison,
            propertyComparison: view.propertyComparison,
          ),
        };
    }
  }

  /// The bytes for [document] in [format], or null when no layout exists for it.
  static Future<Uint8List?> _bytes(
    ExportDocument document,
    ExportFileFormat format,
    Future<ExportPdfFonts> Function() fonts,
  ) async => switch ((document, format)) {
    (final PnlExportDocument d, ExportFileFormat.pdf) => pnlPdf(
      d,
      await fonts(),
    ),
    (final PnlExportDocument d, ExportFileFormat.xlsx) => pnlWorkbook(
      d,
    ).encode(),
    _ => null,
  };
}
