/// The P&L workbook carries the canonical figures, and nothing it worked out itself
/// (Phase 7 Slice 4; D-294, spec §21.3).
///
/// Parity at the file: every numeric cell read back out of the `.xlsx` is compared with
/// the canonical `PnlResult` it came from, in integer paise, by parsing the stored literal
/// with `Money.tryParse`. No floating point is used to compare, either.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/workbook/pnl_workbook.dart';
import 'package:krishna_mis/core/export/xlsx/xlsx_writer.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/export_fixtures.dart';
import '../../support/xlsx_reader.dart';

PnlExportDocument _doc(
  PnlResult result,
  ExportScope scope, {
  ReportingFreshness? freshness,
}) => switch (ExportDocuments.profitAndLoss(
  fxContext(
    fxPermit(ExportReport.profitAndLoss, scope),
    freshness: freshness,
    periodName: 'This month',
  ),
  result,
)) {
  ExportBuilt(:final document) => document,
  ExportNotBuilt(:final reason) => throw StateError('not built: $reason'),
};

StoredWorkbook _open(PnlExportDocument doc) =>
    StoredWorkbook(pnlWorkbook(doc).encode());

/// The row of [sheet] whose first cell reads [label].
List<StoredCell> _row(StoredWorkbook book, String sheet, String label) {
  final cells = book.cells(sheet);
  final match = cells.values.where(
    (c) => c.ref.startsWith('A') && c.text == label,
  );
  expect(match, hasLength(1), reason: 'one "$label" row on $sheet');
  final row = match.single.ref.substring(1);
  final inRow = cells.values
      .where((c) => RegExp('^[A-Z]+$row\$').hasMatch(c.ref))
      .toList();
  return inRow;
}

/// The numeric cells of a row, as exact Money.
List<Money> _money(List<StoredCell> row) => [
  for (final c in row)
    if (c.isNumber &&
        (c.style == XlsxStyle.money.index ||
            c.style == XlsxStyle.moneyBold.index))
      Money.tryParse(c.value!)!,
];

void main() {
  // The group bodies below build workbooks while the suite is declared.
  tzdata.initializeTimeZones();

  group('one property', () {
    final result = fxCcrSeptember();
    final doc = _doc(result, ExportScope.unit(fxCcr), freshness: fxFreshness());
    final book = _open(doc);

    test('has a Summary, a Revenue and an Expenses sheet', () {
      expect(book.sheetNames, ['Summary', 'Revenue', 'Expenses']);
    });

    test('the headline cells are the canonical figures, to the paisa', () {
      expect(_money(_row(book, 'Summary', exportGrossSalesLabel)), [
        result.grossSales,
      ]);
      expect(_money(_row(book, 'Summary', exportGstLabel)), [result.gst]);
      expect(_money(_row(book, 'Summary', exportNetSalesLabel)), [
        result.netSales,
      ]);
      expect(_money(_row(book, 'Summary', exportExpensesLabel)), [
        result.expenses,
      ]);
      expect(
        _money(
          _row(book, 'Summary', exportOperatingLabel(result.operatingProfit)),
        ),
        [result.operatingProfit],
      );
    });

    test('the result is stated in words beside the figure', () {
      final row = _row(book, 'Summary', 'Result');
      expect(row.map((c) => c.text), ['Result', 'Profit']);
    });

    test('the margin is the screen value, as a percentage cell', () {
      final cell = _row(book, 'Summary', exportMarginLabel)[1];
      final margin = result.margin as MarginRatio;
      expect(cell.value, margin.displayedFractionLiteral);
      expect(cell.style, XlsxStyle.percentBold.index);
    });

    test('the header states scope, period, dates, basis and freshness', () {
      final rows = book.rows('Summary');
      String? after(String label) =>
          rows.firstWhere((r) => r.isNotEmpty && r.first == label)[1];
      expect(after('Scope'), 'Crystal Canopy Rooftop');
      expect(after('Period'), 'This month');
      expect(after('Basis'), exportBasisLine(doc.header.dateBasis));
      expect(after('Includes'), exportInclusionLine);
      expect(
        after('Freshness'),
        startsWith('Synchronised as of 19 Sep 2026, 11:30'),
      );
      final cells = book.cells('Summary');
      final from = cells.values.firstWhere(
        (c) => c.isNumber && c.style == XlsxStyle.date.index,
      );
      expect(from.value, '46266', reason: '1 Sep 2026 as a date serial');
      final text = rows.expand((r) => r).join('\n');
      expect(text, contains('Generated on this device at 19 Sep 2026, 18:00'));
      expect(text, contains('(device clock)'));
      expect(text, isNot(contains('newer changes')));
    });

    test('revenue lines carry each category, and No GST where it applies', () {
      final rows = book.rows('Revenue');
      expect(rows.first, [
        'Revenue category',
        'Treatment',
        'Gross',
        'GST',
        'Net',
      ]);
      final lines = doc.scopeStatement.revenueLines!;
      expect(rows, hasLength(lines.length + 2));
      for (final (i, line) in lines.indexed) {
        final r = rows[i + 1];
        expect(r[0], line.categoryLabel);
        expect(r[1], line.noGst ? exportNoGstLabel : '');
        expect(Money.tryParse(r[2]), line.gross);
        expect(Money.tryParse(r[3]), line.gst);
        expect(Money.tryParse(r[4]), line.net);
      }
    });

    test('the Total row is the headline figure, not a sum of the rows', () {
      final total = _money(_row(book, 'Revenue', 'Total'));
      expect(total, [result.grossSales, result.gst, result.netSales]);
      expect(_money(_row(book, 'Expenses', 'Total')), [result.expenses]);
    });

    test('line tables freeze their heading and carry a filter', () {
      expect(book.sheetXml('Revenue'), contains('state="frozen"'));
      expect(book.sheetXml('Revenue'), contains('<autoFilter ref="A1:E3"/>'));
      expect(book.sheetXml('Expenses'), contains('<autoFilter ref="A1:D3"/>'));
    });

    test('no formula anywhere', () {
      expect(book.allText, isNot(contains('<f>')));
    });
  });

  group('both properties', () {
    final result = fxConsolidated();
    final split = PropertyComparison.of(result) as PropertyComparisonReady;
    final doc = _doc(
      result,
      fxBoth,
      freshness: fxFreshness(serverHasNewer: true),
    );
    final book = _open(doc);

    test('one column per property, then the consolidated total', () {
      final header = book
          .rows('Summary')
          .firstWhere(
            (r) => r.contains('Both properties (consolidated)') && r.length > 2,
          );
      expect(header.skip(1), [
        'Crystal Canopy Rooftop',
        'Hotel Krishna Imperial',
        'Both properties (consolidated)',
      ]);
    });

    test('each column is the domain split, and the last is the total', () {
      final expected = [
        for (final p in split.properties) p.result.operatingProfit,
        result.operatingProfit,
      ];
      expect(
        _money(_row(book, 'Summary', 'Operating Profit / Loss')),
        expected,
      );
      expect(_money(_row(book, 'Summary', exportNetSalesLabel)), [
        for (final p in split.properties) p.result.netSales,
        result.netSales,
      ]);
    });

    test('a loss stays negative and is called a loss', () {
      final hki = split.properties.last.result;
      expect(hki.operatingProfit.isNegative, isTrue);
      final words = _row(book, 'Summary', 'Result').map((c) => c.text).toList();
      expect(words[2], 'Loss');
    });

    test(
      'the server-newer statement appears only because it was confirmed',
      () {
        final text = book.rows('Summary').expand((r) => r).join('\n');
        expect(text, contains('The server has newer changes'));
      },
    );

    test('line sheets name the property on every line', () {
      final rows = book.rows('Revenue');
      expect(rows.first.first, 'Property');
      final lines = doc.scopeStatement.revenueLines!;
      for (final (i, line) in lines.indexed) {
        expect(rows[i + 1].first, line.propertyLabel);
      }
      expect(
        rows.where((r) => r.contains(exportNoGstLabel)),
        hasLength(1),
        reason: 'Banquet is untaxed',
      );
      expect(book.rows('Expenses').first.first, 'Property');
    });

    test('no internal id reaches any byte of the workbook', () {
      for (final forbidden in fxForbidden) {
        expect(book.allText, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('refusals stay refusals', () {
    test('no freshness evidence: no time is claimed', () {
      final book = _open(_doc(fxCcrSeptember(), ExportScope.unit(fxCcr)));
      final text = book.rows('Summary').expand((r) => r).join('\n');
      expect(text, contains('No synchronisation time is stated'));
      expect(text, isNot(contains('Synchronised as of')));
      expect(text, contains('Generated on this device'));
    });

    test('a breakdown that does not reconcile is not shown, and says so', () {
      final lines = fxConsolidatedRevenue();
      final result = fxResult(
        range: fxSeptember,
        revenue: lines,
        expenses: fxConsolidatedExpenses(),
        revenueSide:
            lines.fold(RevenueTotals.zero, (sum, l) => sum + l.totals) +
            RevenueTotals(
              gross: fxP(1),
              tax: fxP(0),
              net: fxP(1),
              contributions: 0,
            ),
      );
      final book = _open(_doc(result, fxBoth));
      expect(book.rows('Revenue'), [
        [exportBreakdownNotShownLine],
      ]);
      expect(book.rows('Expenses'), [
        [exportBreakdownNotShownLine],
      ]);
      final text = book.rows('Summary').expand((r) => r).join('\n');
      expect(text, contains(exportSplitNotShownLine));
      expect(_money(_row(book, 'Summary', exportGrossSalesLabel)), [
        result.grossSales,
      ]);
    });

    test('zero net sales: the margin is the words N/A, never 0%', () {
      final result = fxResult(
        range: fxSeptember,
        businessUnitId: fxCcr,
        revenue: const [],
        expenses: [fxExpense(fxCcr, 'water', 120000)],
      );
      expect(result.margin, isA<MarginNotApplicable>());
      final book = _open(_doc(result, ExportScope.unit(fxCcr)));
      final cell = _row(book, 'Summary', exportMarginLabel)[1];
      expect(cell.text, exportNotApplicable);
      expect(cell.isNumber, isFalse);
      expect(
        _row(book, 'Summary', 'Operating Loss').map((c) => c.text).first,
        'Operating Loss',
      );
    });

    test('a period with no trade says so, and a real ₹0 is still a number', () {
      final result = fxResult(
        range: fxSeptember,
        businessUnitId: fxCcr,
        revenue: const [],
        expenses: const [],
      );
      final book = _open(_doc(result, ExportScope.unit(fxCcr)));
      final text = book.rows('Summary').expand((r) => r).join('\n');
      expect(text, contains(exportNoTradeLine));
      expect(_money(_row(book, 'Summary', exportNetSalesLabel)), [Money.zero]);
      expect(_row(book, 'Summary', 'Result')[1].text, 'Break-even');
    });
  });

  group('the file name', () {
    test('is readable, names the scope and the exact dates, and no id', () {
      final unit = _doc(fxCcrSeptember(), ExportScope.unit(fxCcr));
      expect(
        exportFileName(unit.header, extension: 'xlsx'),
        'KrishnaImperialMIS_ProfitAndLoss_CrystalCanopyRooftop_'
        '2026-09-01_2026-09-19.xlsx',
      );
      final both = _doc(fxConsolidated(), fxBoth);
      expect(
        exportFileName(both.header, extension: 'pdf'),
        'KrishnaImperialMIS_ProfitAndLoss_Consolidated_2026-09-01_2026-09-19.pdf',
      );
    });
  });

  test('the same document always gives the same workbook bytes', () {
    final doc = _doc(fxConsolidated(), fxBoth, freshness: fxFreshness());
    expect(pnlWorkbook(doc).encode(), pnlWorkbook(doc).encode());
  });
}
