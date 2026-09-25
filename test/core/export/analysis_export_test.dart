/// The three analysis exports carry the canonical figures, in the screen's words, and
/// nothing they worked out themselves (Phase 7 Slice 9; D-290, spec §21.3).
///
/// Parity at the file:
/// * every numeric cell read back out of the `.xlsx` is compared with the document's
///   `Money`, in integer paise, through `Money.tryParse`;
/// * every PDF line is read back through each font's `/ToUnicode` map and compared with
///   `MoneyFormatter`'s rendering of the same figure — the string the screen shows.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/pdf/analysis_pdf.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/export/workbook/analysis_workbook.dart';
import 'package:krishna_mis/core/export/xlsx/xlsx_writer.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/export_fixtures.dart';
import '../../support/pdf_text.dart';
import '../../support/xlsx_reader.dart';

ByteData _asset(String path) =>
    ByteData.sublistView(File(path).readAsBytesSync());

final _fonts = ExportPdfFonts.fromBytes(
  regular: _asset(exportPdfRegularFontAsset),
  bold: _asset(exportPdfBoldFontAsset),
);

T _built<T extends ExportDocument>(ExportBuild<T> build) => switch (build) {
  ExportBuilt(:final document) => document,
  ExportNotBuilt(:final reason) => throw StateError('not built: $reason'),
};

String _m(Money m) => MoneyFormatter.standard.format(m);

RevenueAnalysisExportDocument _revenue({
  PnlComparison? comparison,
  List<TrendSeries>? trends,
  TopNOutcome<RevenueCategoryLine>? mix,
  bool mixGiven = false,
}) {
  final result = fxConsolidated();
  return _built(
    ExportDocuments.revenueAnalysis(
      fxContext(
        fxPermit(ExportReport.revenueAnalysis, fxBoth),
        freshness: fxFreshness(),
      ),
      result: result,
      comparison: comparison ?? fxComparison(),
      trends: trends ?? [fxNetSalesTrendWithGap()],
      revenueMix: mixGiven ? mix : TopN.revenueCategories(result, n: 2),
    ),
  );
}

ExpenseAnalysisExportDocument _expense({
  List<TrendSeries>? trends,
  TopNOutcome<ExpenseHierarchyLine>? categories,
  bool categoriesGiven = false,
}) {
  final result = fxConsolidated();
  return _built(
    ExportDocuments.expenseAnalysis(
      fxContext(
        fxPermit(ExportReport.expenseAnalysis, fxBoth),
        freshness: fxFreshness(),
      ),
      result: result,
      comparison: fxComparison(),
      trends: trends ?? [fxMonthlyExpenseTrend()],
      topExpenseCategories: categoriesGiven
          ? categories
          : TopN.expenseCategories(result, n: 1),
      departmentSpending: TopN.departments(result, n: 3),
    ),
  );
}

BusinessComparisonExportDocument _comparison({PnlResult? result}) {
  final r = result ?? fxConsolidated();
  return _built(
    ExportDocuments.businessComparison(
      fxContext(
        fxPermit(ExportReport.businessComparison, fxBoth),
        freshness: fxFreshness(),
      ),
      result: r,
      comparison: fxComparison(current: PnlComputed(r)),
      propertyComparison: PropertyComparison.of(r),
    ),
  );
}

/// The row of [sheet] whose first cell reads [label].
List<StoredCell> _row(StoredWorkbook book, String sheet, String label) {
  final cells = book.cells(sheet);
  final match = cells.values.where(
    (c) => c.ref.startsWith('A') && c.text == label,
  );
  expect(match, hasLength(1), reason: 'one "$label" row on $sheet');
  final row = match.single.ref.substring(1);
  return cells.values
      .where((c) => RegExp('^[A-Z]+$row\$').hasMatch(c.ref))
      .toList();
}

List<Money> _money(List<StoredCell> row) => [
  for (final c in row)
    if (c.isNumber &&
        (c.style == XlsxStyle.money.index ||
            c.style == XlsxStyle.moneyBold.index))
      Money.tryParse(c.value!)!,
];

List<String> _texts(List<StoredCell> row) => [
  for (final c in row)
    if (c.text != null) c.text!,
];

Future<PdfText> _read(Future<Uint8List> bytes) async =>
    PdfText.read(await bytes);

/// A PDF with the package's random file identifier removed, so two renderings of one
/// document can be compared byte for byte.
String _withoutId(Uint8List bytes) => latin1
    .decode(bytes)
    .replaceAll(RegExp(r'/ID\s*\[<[0-9a-f]+><[0-9a-f]+>\]'), '');

void main() {
  tzdata.initializeTimeZones();

  group('Revenue Analysis workbook', () {
    final doc = _revenue();
    final book = StoredWorkbook(revenueAnalysisWorkbook(doc).encode());

    test('has a Summary, a Trend and a Revenue mix sheet', () {
      expect(book.sheetNames, ['Summary', 'Trend', 'Revenue mix']);
    });

    test('each figure is canonical, beside the domain comparison', () {
      for (final (label, figure) in [
        (exportGrossSalesLabel, doc.grossSales),
        (exportGstLabel, doc.gst),
        (exportNetSalesLabel, doc.netSales),
      ]) {
        final c = figure.comparison as MoneyComparisonAvailable;
        final row = _row(book, 'Summary', label);
        // This period, the previous period, and the domain's own movement — to the paisa.
        expect(_money(row), [figure.current, c.previous, c.change]);
        expect(_texts(row), contains(c.percentChange.displayTwoDecimals));
      }
    });

    test('the comparison period and the header statements are stated', () {
      final rows = book.rows('Summary').map((r) => r.join(' | ')).toList();
      expect(rows, contains('Scope | Both properties (consolidated)'));
      expect(rows, contains('Period | Month to date'));
      expect(rows.any((r) => r.startsWith('Compared from | ')), isTrue);
      expect(rows.any((r) => r.startsWith('Compared to | ')), isTrue);
      expect(rows.any((r) => r.contains('Synchronised as of ')), isTrue);
      expect(rows.any((r) => r.contains('Generated on this device')), isTrue);
    });

    test('an unavailable comparison is words, never a zero cell', () {
      final book = StoredWorkbook(
        revenueAnalysisWorkbook(
          _revenue(
            comparison: fxComparison(
              previous: const PnlRefused(PnlRefusal.bothSidesUnavailable),
            ),
          ),
        ).encode(),
      );
      final row = _row(book, 'Summary', exportNetSalesLabel);
      expect(_money(row), [fxConsolidated().netSales]);
      expect(_texts(row).where((t) => t == exportNotAvailable), hasLength(3));
      expect(
        _texts(row),
        contains(exportNoComparisonLine(ComparisonSide.previous)),
      );
    });

    test('a trend gap is "Not available", a real ₹0 is still a number', () {
      final trend = doc.netSalesTrend!;
      final rows = book.rows('Trend');
      expect(rows.first, [
        exportPeriodColumnLabel,
        'From',
        'To',
        exportTrendTitle(trend),
        exportNoteLabel,
      ]);
      final gap = rows[2];
      expect(gap, contains(exportNotAvailable));
      expect(gap, contains(exportTrendGapNote));
      // The money cells are exactly the established points, in order — the gap has none.
      final amounts = [
        for (final c in book.cells('Trend').values)
          if (c.isNumber && c.style == XlsxStyle.money.index)
            Money.tryParse(c.value!)!,
      ];
      expect(amounts, [
        for (final p in trend.points)
          if (p is TrendValue) p.amount,
      ]);
      expect(amounts.last, Money.zero);
      expect(book.sheetXml('Trend'), contains('<autoFilter ref="A1:E4"/>'));
    });

    test('the mix is the domain ranking, its exact Others and its total', () {
      final grouped = doc.revenueMix! as ExportRankingGrouped;
      final rows = book.rows('Revenue mix');
      expect(rows.first, [exportCategoryColumnLabel, exportNetSalesLabel]);
      expect(rows.sublist(1, 3).map((r) => r.first), [
        for (final r in grouped.rows) r.label,
      ]);
      expect(_money(_row(book, 'Revenue mix', grouped.rows.first.label)), [
        grouped.rows.first.amount,
      ]);
      expect(
        _money(
          _row(book, 'Revenue mix', exportOthersLabel(grouped.othersCount)),
        ),
        [grouped.others],
      );
      expect(_money(_row(book, 'Revenue mix', exportTotalLabel)), [
        fxConsolidated().netSales,
      ]);
      expect(
        book.sheetXml('Revenue mix'),
        contains('<autoFilter ref="A1:B3"/>'),
      );
    });

    test('a ranking that does not reconcile prints no line and says why', () {
      final book = StoredWorkbook(
        revenueAnalysisWorkbook(
          _revenue(
            mix: const TopNRefused(TopNRefusal.doesNotReconcile),
            mixGiven: true,
          ),
        ).encode(),
      );
      expect(book.rows('Revenue mix').expand((r) => r), [
        exportRevenueMixHeading,
        exportRankingRefusedLine(TopNRefusal.doesNotReconcile),
      ]);
      expect(
        book.cells('Revenue mix').values.where((c) => c.isNumber),
        isEmpty,
      );
    });

    test('no period trend: the sentence, and no table', () {
      final book = StoredWorkbook(
        revenueAnalysisWorkbook(_revenue(trends: const [])).encode(),
      );
      expect(book.rows('Trend'), [
        [exportNoNetSalesTrendLine(fxPair.kind)],
      ]);
    });
  });

  group('Expense & Department Analysis workbook', () {
    final doc = _expense();
    final book = StoredWorkbook(expenseAnalysisWorkbook(doc).encode());

    test('has a Summary, a Trend and two ranking sheets', () {
      expect(book.sheetNames, [
        'Summary',
        'Trend',
        'Top categories',
        'Departments',
      ]);
    });

    test('Operating Expenses is canonical, beside its comparison', () {
      final c = doc.expenses.comparison as MoneyComparisonAvailable;
      expect(_money(_row(book, 'Summary', exportOperatingExpensesLabel)), [
        doc.expenses.current,
        c.previous,
        c.change,
      ]);
    });

    test('the monthly trend is every point, to the paisa', () {
      final amounts = [
        for (final c in book.cells('Trend').values)
          if (c.isNumber && c.style == XlsxStyle.money.index)
            Money.tryParse(c.value!)!,
      ];
      expect(amounts, [
        for (final p in doc.monthlyExpenseTrend!.points)
          (p as TrendValue).amount,
      ]);
      // A clipped month says it is partial.
      expect(
        book.rows('Trend').where((r) => r.contains(exportPartialPeriodNote)),
        isNotEmpty,
      );
    });

    test('rankings: domain lines, exact Others, the headline total', () {
      final cats = doc.topExpenseCategories! as ExportRankingGrouped;
      expect(_money(_row(book, 'Top categories', exportTotalLabel)), [
        fxConsolidated().expenses,
      ]);
      expect(
        _money(
          _row(book, 'Top categories', exportOthersLabel(cats.othersCount)),
        ),
        [cats.others],
      );
      final depts = doc.departmentSpending! as ExportRankingGrouped;
      expect(book.rows('Departments').first, [
        exportDepartmentColumnLabel,
        exportAmountLabel,
      ]);
      expect(_money(_row(book, 'Departments', exportTotalLabel)), [
        depts.total,
      ]);
    });

    test('no monthly trend: the screen sentence, not a table', () {
      final book = StoredWorkbook(
        expenseAnalysisWorkbook(_expense(trends: const [])).encode(),
      );
      expect(book.rows('Trend'), [
        [exportNoExpenseTrendLine(fxPair.kind)],
      ]);
    });
  });

  group('Business Comparison workbook', () {
    final doc = _comparison();
    final book = StoredWorkbook(businessComparisonWorkbook(doc).encode());

    test('one sheet, the properties in fixed order, then both together', () {
      expect(book.sheetNames, ['Comparison']);
      final heading = book
          .rows('Comparison')
          .firstWhere(
            (r) => r.isNotEmpty && r.first == exportFigureColumnLabel,
          );
      expect(heading, [
        exportFigureColumnLabel,
        'Crystal Canopy Rooftop',
        'Hotel Krishna Imperial',
        'Both properties (consolidated)',
      ]);
    });

    test('every figure is the domain split, and the last column the total', () {
      expect(
        _money(_row(book, 'Comparison', exportNetSalesLabel)),
        doc.columns.map((c) => c.netSales),
      );
      expect(
        _money(_row(book, 'Comparison', exportOperatingExpensesLabel)),
        doc.columns.map((c) => c.expenses),
      );
      expect(
        _money(_row(book, 'Comparison', exportOperatingProfitOrLossLabel)),
        doc.columns.map((c) => c.operatingProfit),
      );
      expect(doc.columns.last.netSales, fxConsolidated().netSales);
    });

    test('results in words; margins are the screen value as percentages', () {
      expect(
        _texts(_row(book, 'Comparison', exportResultLabel)).skip(1),
        doc.columns.map((c) => exportResultWord(c.operatingProfit)),
      );
      final margins = _row(
        book,
        'Comparison',
        exportMarginLabel,
      ).where((c) => c.isNumber).toList();
      expect(margins, hasLength(doc.columns.length));
      for (final m in margins) {
        expect(m.style, XlsxStyle.percentBold.index);
      }
      expect(
        book.rows('Comparison').expand((r) => r),
        contains(exportComparisonOrderNote),
      );
    });
  });

  group('every analysis workbook', () {
    final books = {
      'revenue': revenueAnalysisWorkbook(_revenue()).encode(),
      'expense': expenseAnalysisWorkbook(_expense()).encode(),
      'comparison': businessComparisonWorkbook(_comparison()).encode(),
    };
    for (final MapEntry(key: name, value: bytes) in books.entries) {
      test('$name: no formula, no raw paise, no internal id', () {
        final book = StoredWorkbook(bytes);
        expect(book.allText, isNot(contains('<f>')));
        expect(book.allText, isNot(contains('<f ')));
        expect(book.allText.toLowerCase(), isNot(contains('paise')));
        for (final forbidden in fxForbidden) {
          expect(book.allText, isNot(contains(forbidden)), reason: forbidden);
        }
      });
    }

    test('the same document always gives the same bytes', () {
      final doc = _expense();
      expect(
        expenseAnalysisWorkbook(doc).encode(),
        expenseAnalysisWorkbook(doc).encode(),
      );
    });
  });

  group('Revenue Analysis PDF', () {
    test(
      'each figure, the previous, the movement and the percentage',
      () async {
        final doc = _revenue();
        final pdf = await _read(
          revenueAnalysisPdf(doc, _fonts, compress: false),
        );
        for (final (label, figure) in [
          (exportGrossSalesLabel, doc.grossSales),
          (exportNetSalesLabel, doc.netSales),
        ]) {
          final c = figure.comparison as MoneyComparisonAvailable;
          expect(
            pdf.lines,
            contains(
              '$label ${_m(figure.current)} ${_m(c.previous)} '
              '${MoneyFormatter.movement.format(c.change)} '
              '${c.percentChange.displayTwoDecimals}',
            ),
          );
        }
        expect(pdf.text, contains(exportComparedWithLine(doc.pair)));
      },
    );

    test('an unavailable comparison says so, and prints no ₹0', () async {
      final doc = _revenue(
        comparison: fxComparison(
          previous: const PnlRefused(PnlRefusal.bothSidesUnavailable),
        ),
      );
      final pdf = await _read(revenueAnalysisPdf(doc, _fonts, compress: false));
      expect(
        pdf.lines,
        contains(
          '$exportNetSalesLabel ${_m(doc.netSales.current)} '
          '$exportNotAvailable $exportNotAvailable $exportNotAvailable',
        ),
      );
      expect(
        pdf.text.replaceAll('\n', ' '),
        contains(exportNoComparisonLine(ComparisonSide.previous)),
      );
      // No comparison figure stands in as zero (the trend's real ₹0 is elsewhere).
      for (final label in [
        exportGrossSalesLabel,
        exportGstLabel,
        exportNetSalesLabel,
      ]) {
        expect(
          pdf.lines.where(
            (l) => l.startsWith('$label ') && l.contains('₹0.00'),
          ),
          isEmpty,
        );
      }
    });

    test('a trend gap is stated, never drawn as zero', () async {
      final pdf = await _read(
        revenueAnalysisPdf(_revenue(), _fonts, compress: false),
      );
      final gapLine = pdf.lines.singleWhere((l) => l.startsWith('2 Sep '));
      expect(gapLine, endsWith(exportNotAvailable));
      expect(gapLine, isNot(contains('₹')));
      // The real zero on 3 Sep is printed as the figure it is.
      expect(pdf.lines, contains('3 Sep ₹0.00'));
    });

    test('the mix: domain lines, exact Others, the headline total', () async {
      final doc = _revenue();
      final grouped = doc.revenueMix! as ExportRankingGrouped;
      final pdf = await _read(revenueAnalysisPdf(doc, _fonts, compress: false));
      expect(
        pdf.lines,
        contains(
          '${exportOthersLabel(grouped.othersCount)} ${_m(grouped.others!)}',
        ),
      );
      expect(pdf.lines, contains('$exportTotalLabel ${_m(grouped.total)}'));
    });
  });

  group('Expense & Department Analysis PDF', () {
    test('expenses, the monthly trend and both rankings', () async {
      final doc = _expense();
      final pdf = await _read(expenseAnalysisPdf(doc, _fonts, compress: false));
      final c = doc.expenses.comparison as MoneyComparisonAvailable;
      expect(
        pdf.lines,
        contains(
          '$exportOperatingExpensesLabel ${_m(doc.expenses.current)} '
          '${_m(c.previous)} ${MoneyFormatter.movement.format(c.change)} '
          '${c.percentChange.displayTwoDecimals}',
        ),
      );
      expect(pdf.text, contains(exportTopExpenseCategoriesHeading));
      expect(pdf.text, contains(exportDepartmentSpendingHeading));
      final depts = doc.departmentSpending! as ExportRankingGrouped;
      expect(
        pdf.lines.where((l) => l == '$exportTotalLabel ${_m(depts.total)}'),
        hasLength(2),
      );
    });

    test('a refused ranking prints no line and says why', () async {
      final pdf = await _read(
        expenseAnalysisPdf(
          _expense(
            categories: const TopNRefused(TopNRefusal.doesNotReconcile),
            categoriesGiven: true,
          ),
          _fonts,
          compress: false,
        ),
      );
      expect(
        pdf.text.replaceAll('\n', ' '),
        contains(exportRankingRefusedLine(TopNRefusal.doesNotReconcile)),
      );
    });
  });

  group('Business Comparison PDF', () {
    test(
      'properties in fixed order, then both together; results in words',
      () async {
        final doc = _comparison();
        final pdf = await _read(
          businessComparisonPdf(doc, _fonts, compress: false),
        );
        expect(
          pdf.lines,
          contains(
            '$exportNetSalesLabel '
            '${doc.columns.map((c) => _m(c.netSales)).join(' ')}',
          ),
        );
        expect(
          pdf.lines,
          contains(
            '$exportResultLabel '
            '${doc.columns.map((c) => exportResultWord(c.operatingProfit)).join(' ')}',
          ),
        );
        expect(
          pdf.lines,
          contains(
            '$exportMarginLabel '
            '${doc.columns.map((c) => c.margin.displayTwoDecimals).join(' ')}',
          ),
        );
        expect(
          pdf.text.replaceAll('\n', ' '),
          contains(exportComparisonOrderNote),
        );
      },
    );

    test('a loss stays negative and is called a loss', () async {
      final loss = fxResult(
        range: fxSeptember,
        revenue: fxConsolidatedRevenue(),
        expenses: [
          fxExpense(fxCcr, 'kirana', 900000000),
          fxExpense(fxHki, 'diesel', 100000),
        ],
      );
      final doc = _comparison(result: loss);
      final pdf = await _read(
        businessComparisonPdf(doc, _fonts, compress: false),
      );
      expect(doc.columns.last.operatingProfit.isNegative, isTrue);
      expect(
        pdf.lines.singleWhere((l) => l.startsWith('$exportResultLabel ')),
        endsWith('Loss'),
      );
      expect(pdf.text, contains(_m(doc.columns.last.operatingProfit)));
    });
  });

  group('every analysis PDF', () {
    final renders = <String, Future<Uint8List> Function({bool compress})>{
      'revenue': ({bool compress = true}) =>
          revenueAnalysisPdf(_revenue(), _fonts, compress: compress),
      'expense': ({bool compress = true}) =>
          expenseAnalysisPdf(_expense(), _fonts, compress: compress),
      'comparison': ({bool compress = true}) =>
          businessComparisonPdf(_comparison(), _fonts, compress: compress),
    };
    for (final MapEntry(key: name, value: render) in renders.entries) {
      test(
        '$name: page furniture, three freshness statements, no ids',
        () async {
          final pdf = PdfText.read(await render(compress: false));
          final first = pdf.pages.first.text;
          expect(first, contains('Page 1 of ${pdf.pages.length}'));
          expect(first, contains('Synchronised as of '));
          expect(first, contains('Generated on this device at '));
          expect(
            first,
            contains(exportBasisShort(ExportDateBasis.pnlDateAccrual)),
          );
          for (final compress in [true, false]) {
            final raw = latin1.decode(await render(compress: compress));
            for (final absent in [
              '/Info',
              '/Author',
              '/Producer',
              '/CreationDate',
            ]) {
              expect(raw, isNot(contains(absent)), reason: absent);
            }
            for (final forbidden in fxForbidden) {
              expect(raw, isNot(contains(forbidden)), reason: forbidden);
            }
          }
        },
      );

      test(
        '$name: nothing smaller than the footer size; deterministic',
        () async {
          final raw = latin1.decode(await render(compress: false));
          final sizes = RegExp(
            r'/F\d+ ([\d.]+) Tf',
          ).allMatches(raw).map((m) => m.group(1)).toSet();
          expect(sizes.difference({'7.5', '9', '11', '12', '18'}), isEmpty);
          expect(
            _withoutId(await render(compress: false)),
            _withoutId(await render(compress: false)),
          );
        },
      );
    }
  });

  test('file names are readable and carry no id', () {
    expect(
      exportFileName(_revenue().header, extension: 'pdf'),
      'KrishnaImperialMIS_RevenueAnalysis_Consolidated_2026-09-01_2026-09-19.pdf',
    );
    expect(
      exportFileName(_expense().header, extension: 'xlsx'),
      'KrishnaImperialMIS_ExpenseAndDepartmentAnalysis_Consolidated_'
      '2026-09-01_2026-09-19.xlsx',
    );
    expect(
      exportFileName(_comparison().header, extension: 'pdf'),
      'KrishnaImperialMIS_BusinessComparison_Consolidated_'
      '2026-09-01_2026-09-19.pdf',
    );
  });
}
