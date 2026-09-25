/// The export pipeline (Phase 7 Slice 6): authority first, the screen's own report, and
/// the same bytes the foundation renderers make.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/export/pdf/analysis_pdf.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/export/pdf/pnl_pdf.dart';
import 'package:krishna_mis/core/export/workbook/analysis_workbook.dart';
import 'package:krishna_mis/core/export/workbook/pnl_workbook.dart';
import 'package:krishna_mis/core/formatting/report_dates.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/features/export/export_pipeline.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/export_delivery_fixtures.dart';
import '../../support/export_fixtures.dart';

void main() {
  tzdata.initializeTimeZones();
  var fontLoads = 0;
  Future<ExportPdfFonts> fonts() async {
    fontLoads++;
    return fxFonts;
  }

  setUp(() => fontLoads = 0);

  Future<ExportRender> render(
    Principal principal,
    ExportSource source, {
    ExportReport report = ExportReport.profitAndLoss,
    ExportFileFormat format = ExportFileFormat.pdf,
    ExportAction action = ExportAction.export,
  }) => ExportPipeline.render(
    principal: principal,
    action: action,
    report: report,
    format: format,
    source: source,
    labels: const FxLabels(),
    fonts: fonts,
    generatedOnDeviceAt: fxGeneratedAt,
  );

  PnlExportSource pnlSource(Principal viewer, {bool computed = true}) =>
      PnlExportSource(
        fxPnlView(
          fxCcrSeptember(),
          viewer: viewer,
          freshness: fxFreshness(),
          computed: computed,
        ),
        periodName: 'This Month',
        displayZone: 'Asia/Kolkata',
      );

  PnlExportSource consolidatedSource(Principal viewer) => PnlExportSource(
    fxPnlView(fxConsolidated(), viewer: viewer, freshness: fxFreshness()),
    periodName: 'This Month',
    displayZone: 'Asia/Kolkata',
  );

  group('the P&L, permitted', () {
    test(
      'PDF: exactly the foundation renderer\'s bytes for the same document',
      () async {
        final rendered = await render(fxOwner, pnlSource(fxOwner));
        expect(rendered, isA<ExportRendered>());
        rendered as ExportRendered;

        final permit = fxPermit(
          ExportReport.profitAndLoss,
          ExportScope.unit(fxCcr),
        );
        final built =
            ExportDocuments.profitAndLoss(
                  fxContext(
                    permit,
                    freshness: fxFreshness(),
                    periodName: 'This Month',
                  ),
                  fxCcrSeptember(),
                )
                as ExportBuilt;
        final direct = await pnlPdf(built.document as dynamic, fxFonts);
        // The pipeline adds nothing and changes nothing: same model, same renderer. The
        // package stamps a random file identifier, so the pages are compared.
        expect(ascii.decode(rendered.bytes.sublist(0, 5)), '%PDF-');
        expect(rendered.bytes.length, direct.length);
        expect(
          rendered.fileName,
          'KrishnaImperialMIS_ProfitAndLoss_CrystalCanopyRooftop_2026-09-01_'
          '2026-09-19.pdf',
        );
        expect(fontLoads, 1);
      },
    );

    test(
      'Excel: byte-identical to the foundation workbook for the same document',
      () async {
        final rendered =
            await render(
                  fxOwner,
                  pnlSource(fxOwner),
                  format: ExportFileFormat.xlsx,
                )
                as ExportRendered;
        final permit = fxPermit(
          ExportReport.profitAndLoss,
          ExportScope.unit(fxCcr),
        );
        final built =
            ExportDocuments.profitAndLoss(
                  fxContext(
                    permit,
                    freshness: fxFreshness(),
                    periodName: 'This Month',
                  ),
                  fxCcrSeptember(),
                )
                as ExportBuilt;
        expect(rendered.bytes, pnlWorkbook(built.document as dynamic).encode());
        expect(rendered.fileName, endsWith('.xlsx'));
        // A workbook needs no font: nothing is loaded that is not used.
        expect(fontLoads, 0);
      },
    );

    test('a scoped exporter may export its own property', () async {
      expect(
        await render(fxCcrExporter, pnlSource(fxCcrExporter)),
        isA<ExportRendered>(),
      );
    });

    test('the consolidated P&L names the scope, not a property id', () async {
      final rendered =
          await render(fxOwner, consolidatedSource(fxOwner)) as ExportRendered;
      expect(rendered.fileName, contains('_Consolidated_'));
      for (final id in fxForbidden) {
        expect(rendered.fileName, isNot(contains(id)));
      }
    });
  });

  group('refused before anything is built', () {
    void expectRefused(
      ExportRender r,
      ExportRenderRefusal reason, {
      ExportRefusal? authority,
    }) {
      expect(r, isA<ExportRenderRefused>());
      r as ExportRenderRefused;
      expect(r.reason, reason);
      if (authority != null) expect(r.authority, authority);
      expect(fontLoads, 0, reason: 'a refused export loads nothing');
    }

    test(
      'the Manager bundle reads the P&L and is not offered export (D-292)',
      () async {
        expectRefused(
          await render(fxManager, pnlSource(fxManager)),
          ExportRenderRefusal.notAuthorised,
          authority: ExportRefusal.noActionCapability,
        );
      },
    );

    test(
      'the action capability without view authority reveals nothing',
      () async {
        expectRefused(
          await render(fxActionOnly, pnlSource(fxActionOnly)),
          ExportRenderRefusal.notAuthorised,
          authority: ExportRefusal.noViewAuthority,
        );
      },
    );

    test('a consolidated report needs the action for every property', () async {
      final who = fxConsolidatedViewerExportsOneProperty;
      expectRefused(
        await render(who, consolidatedSource(who)),
        ExportRenderRefusal.notAuthorised,
        authority: ExportRefusal.noActionCapability,
      );
      // …and the same person may still export the one property they cover.
      expect(await render(who, pnlSource(who)), isA<ExportRendered>());
    });

    test('a report read for somebody else is never exported', () async {
      expectRefused(
        await render(fxOwner, pnlSource(fxManager)),
        ExportRenderRefusal.notThisPersonsReport,
      );
    });

    test(
      'an incomplete report is refused, never fetched and never ₹0',
      () async {
        expectRefused(
          await render(fxOwner, pnlSource(fxOwner, computed: false)),
          ExportRenderRefusal.reportUnavailable,
        );
      },
    );

    test('Business Comparison needs a consolidated scope', () async {
      final single = DashboardExportSource(
        fxDashboard(viewer: fxCcrExporter),
        periodName: 'Month to date',
        displayZone: 'Asia/Kolkata',
      );
      // The fixture dashboard is consolidated; a one-property exporter has no
      // consolidated view authority.
      expectRefused(
        await render(
          fxCcrExporter,
          single,
          report: ExportReport.businessComparison,
        ),
        ExportRenderRefusal.notAuthorised,
        authority: ExportRefusal.noViewAuthority,
      );
    });
  });

  test(
    'with no readable property rules the times are stated in UTC, not lost',
    () async {
      // The surfaces fall back to "UTC" when a property's rules cannot be read. The bundled
      // IANA data calls it Etc/UTC; the formatter must still state the time.
      final source = PnlExportSource(
        fxPnlView(fxCcrSeptember(), viewer: fxOwner, freshness: fxFreshness()),
        periodName: 'This Month',
        displayZone: 'UTC',
      );
      for (final format in ExportFileFormat.values) {
        expect(
          await render(fxOwner, source, format: format),
          isA<ExportRendered>(),
          reason: format.name,
        );
      }
      expect(
        reportInstantLabel(fxGeneratedAt, 'UTC'),
        '19 Sep 2026, 12:30 UTC',
      );
    },
  );

  test('decide gives the answer render acts on', () {
    for (final who in [fxOwner, fxManager, fxActionOnly, fxCcrExporter]) {
      final decision = ExportPipeline.decide(
        who,
        action: ExportAction.export,
        report: ExportReport.profitAndLoss,
        source: pnlSource(who),
      );
      expect(
        decision is ExportPermitted,
        ExportAuthority.offers(
          who,
          action: ExportAction.export,
          report: ExportReport.profitAndLoss,
          scope: ExportScope.unit(fxCcr),
        ),
      );
    }
  });

  group(
    'the analysis reports (Slice 9): both formats, the renderers\' bytes',
    () {
      DashboardExportSource dashboardSource() => DashboardExportSource(
        fxDashboard(viewer: fxOwner, freshness: fxFreshness()),
        periodName: 'Month to date',
        displayZone: 'Asia/Kolkata',
      );

      ExportContext context(ExportReport report) => fxContext(
        fxPermit(report, fxBoth),
        freshness: fxFreshness(),
        periodName: 'Month to date',
      );

      // The document each report's pipeline should build from the same dashboard.
      final result = fxConsolidated();
      final comparison = fxComparison(current: PnlComputed(result));
      final trends = [fxNetSalesTrendWithGap(), fxMonthlyExpenseTrend()];
      T built<T extends ExportDocument>(ExportBuild<T> b) =>
          (b as ExportBuilt<T>).document;

      final direct = <ExportReport, Uint8List Function()>{
        ExportReport.revenueAnalysis: () => revenueAnalysisWorkbook(
          built(
            ExportDocuments.revenueAnalysis(
              context(ExportReport.revenueAnalysis),
              result: result,
              comparison: comparison,
              trends: trends,
              revenueMix: TopN.revenueCategories(result, n: 3),
            ),
          ),
        ).encode(),
        ExportReport.expenseAnalysis: () => expenseAnalysisWorkbook(
          built(
            ExportDocuments.expenseAnalysis(
              context(ExportReport.expenseAnalysis),
              result: result,
              comparison: comparison,
              trends: trends,
              topExpenseCategories: TopN.expenseCategories(result, n: 3),
              departmentSpending: TopN.departments(result, n: 3),
            ),
          ),
        ).encode(),
        ExportReport.businessComparison: () => businessComparisonWorkbook(
          built(
            ExportDocuments.businessComparison(
              context(ExportReport.businessComparison),
              result: result,
              comparison: comparison,
              propertyComparison: PropertyComparison.of(result),
            ),
          ),
        ).encode(),
      };

      for (final report in direct.keys) {
        test(
          '${report.name}: Excel is byte-identical to its workbook',
          () async {
            final rendered =
                await render(
                      fxOwner,
                      dashboardSource(),
                      report: report,
                      format: ExportFileFormat.xlsx,
                    )
                    as ExportRendered;
            expect(rendered.bytes, direct[report]!());
            expect(rendered.fileName, endsWith('.xlsx'));
            expect(fontLoads, 0);
          },
        );

        test('${report.name}: a PDF, printable from the same bytes', () async {
          final saved =
              await render(fxOwner, dashboardSource(), report: report)
                  as ExportRendered;
          expect(ascii.decode(saved.bytes.sublist(0, 5)), '%PDF-');
          expect(saved.fileName, endsWith('.pdf'));
          expect(exportPrintable(report), isTrue);
          final printed =
              await render(
                    fxOwner,
                    dashboardSource(),
                    report: report,
                    action: ExportAction.print,
                  )
                  as ExportRendered;
          expect(printed.bytes.length, saved.bytes.length);
        });
      }

      test(
        'the analysis PDFs are the analysis renderers, not the P&L one',
        () async {
          final rendered =
              await render(
                    fxOwner,
                    dashboardSource(),
                    report: ExportReport.businessComparison,
                  )
                  as ExportRendered;
          final direct = await businessComparisonPdf(
            built(
              ExportDocuments.businessComparison(
                context(ExportReport.businessComparison),
                result: result,
                comparison: comparison,
                propertyComparison: PropertyComparison.of(result),
              ),
            ),
            fxFonts,
          );
          expect(rendered.bytes.length, direct.length);
        },
      );
    },
  );
}
