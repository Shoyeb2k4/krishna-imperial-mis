/// Structural guards for the Windows P&L surface (Phase 5 Slice 8).
///
/// Each is a property that has to hold for files nobody has written yet, so each is a scan
/// over the feature directory rather than a review of what exists today — and each scan is
/// first proven to catch a planted violation, because a guard that has never failed has
/// never been shown to look at anything (D-139, D-187, D-201).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _featureDir = 'lib/features/profit_and_loss';

List<File> _files() => Directory(_featureDir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Source with `//` comments removed, so a paragraph explaining that nothing does something
/// is not read as the thing being done.
String _code(String source) => source.replaceAll(RegExp(r'//[^\n]*'), '');

/// Source with single- and double-quoted strings blanked as well, for rules about code
/// rather than about wording.
String _codeOnly(String source) => _code(source)
    .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''")
    .replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), '""');

/// The P&L surface computes nothing: no paise, no money construction or arithmetic, no
/// calculator call, no margin rounding, no floating point, no storage and no role branch.
List<String> calculationViolations(String source) {
  final code = _codeOnly(source);
  // Imports live inside string literals, so they are matched before strings are blanked.
  final withStrings = _code(source);
  return [
    for (final (pattern, what) in [
      (RegExp(r'package:drift'), 'imports Drift'),
      (RegExp(r'package:supabase'), 'imports Supabase'),
    ])
      if (pattern.hasMatch(withStrings)) what,
    for (final (pattern, what) in [
      (RegExp(r'\.paise\b'), 'reads paise'),
      (RegExp(r'\bMoney\s*\.\s*(fromPaise|sum|tryParse)\b'), 'builds money'),
      (RegExp(r'\bMoney\s*\('), 'builds money'),
      (
        RegExp(
          r'\.(grossSales|gst|netSales|expenses|operatingProfit|amount|gross|tax|net)\s*[-+*]\s*[\w(]',
        ),
        'does arithmetic on a figure',
      ),
      (RegExp(r'\bPnl\s*\.\s*(compute|consolidate)\b'), 'calls the calculator'),
      (RegExp(r'\bpercentageScaled\b'), 'rounds a margin itself'),
      (RegExp(r'\bMarginRatio\s*\('), 'builds a margin'),
      (RegExp(r'\bdouble\b'), 'names double'),
      (RegExp(r'\btoDouble\b'), 'converts to double'),
      (RegExp(r'\bcustomSelect\b'), 'runs SQL'),
      (RegExp(r'\bDriftReportingSource\b'), 'reads the device ledger'),
      (RegExp(r'\bCachedReportingSource\s*\('), 'builds its own source'),
      (RegExp(r'\bReportingSync\s*\('), 'builds its own synchroniser'),
      (RegExp(r'\bRoleTemplates\b'), 'names a role bundle'),
      (RegExp(r'\broleCode\b'), 'branches on a role'),
    ])
      if (pattern.hasMatch(code)) what,
  ];
}

/// Slice 8's boundary: no drill-down, department or section breakdown, vendor detail,
/// transaction navigation, export, printing or chart.
List<String> boundaryViolations(String source) {
  final code = _code(source);
  return [
    for (final (pattern, what) in [
      (RegExp(r'\bdepartmentId\b'), 'department breakdown'),
      (RegExp(r'\bsectionId\b'), 'section breakdown'),
      (RegExp(r'\bvendorId\b'), 'vendor detail'),
      (RegExp(r'Navigator\s*\.\s*(push|of)'), 'transaction navigation'),
      (RegExp(r'context\s*\.\s*(go|push)\b'), 'transaction navigation'),
      (RegExp(r'\b(Export|Excel|PDF|Printing|Print)\b'), 'export or printing'),
      (RegExp(r'\b(Chart|LineChart|BarChart|fl_chart)\b'), 'a chart'),
      (RegExp(r'owner_settlement'), 'owner settlement'),
    ])
      if (pattern.hasMatch(code)) what,
  ];
}

void main() {
  test('there are files to check in the first place', () {
    expect(_files(), hasLength(greaterThanOrEqualTo(2)));
  });

  group('the guards catch what they claim to catch', () {
    test('each calculation violation is detected in a planted snippet', () {
      for (final planted in [
        "final p = result.netSales.paise - result.expenses.paise;",
        "final m = Money.fromPaise(1);",
        "final t = result.grossSales - result.gst;",
        "final r = Pnl.compute(period: p, revenue: r, expenses: e);",
        "final s = margin.percentageScaled(2);",
        "double share = 0;",
        "import 'package:drift/drift.dart';",
        "final c = CachedReportingSource(cache: c);",
        "if (RoleTemplates.owner.contains(x)) {}",
      ]) {
        expect(calculationViolations(planted), isNotEmpty, reason: planted);
      }
    });

    test('a comment or a sentence about the rule is not a violation', () {
      expect(
        calculationViolations(
          "// nothing here reads .paise or calls Pnl.compute\n"
          "final label = 'Operating Profit — Net Sales less Expenses';",
        ),
        isEmpty,
      );
    });

    test('each boundary violation is detected in a planted snippet', () {
      for (final planted in [
        "Text(line.departmentId!)",
        "Navigator.push(context, route);",
        "context.go('/transactions');",
        "FilledButton(child: Text('Export'))",
        "LineChart(data)",
      ]) {
        expect(boundaryViolations(planted), isNotEmpty, reason: planted);
      }
    });
  });

  group('the Windows P&L surface', () {
    for (final file in _files()) {
      test('${file.path} calculates nothing', () {
        expect(calculationViolations(file.readAsStringSync()), isEmpty);
      });

      test('${file.path} stays inside the Slice 8 boundary', () {
        expect(boundaryViolations(file.readAsStringSync()), isEmpty);
      });

      test('${file.path} assumes no property calendar', () {
        final code = _code(file.readAsStringSync());
        expect(code, isNot(contains('Asia/Kolkata')));
        expect(code, isNot(contains('current_date')));
        expect(code, isNot(contains('currentBusinessDateProvider')));
      });
    }

    test('only the clock provider reads the device clock', () {
      final page = _code(
        File(
          '$_featureDir/presentation/profit_and_loss_page.dart',
        ).readAsStringSync(),
      );
      expect(page, isNot(contains('DateTime.now')));
      final providers = _code(
        File('$_featureDir/presentation/pnl_providers.dart').readAsStringSync(),
      );
      expect(RegExp(r'DateTime\.now').allMatches(providers), hasLength(1));
    });

    test(
      'the page reads figures only through the providers, never a repository',
      () {
        final page = _code(
          File(
            '$_featureDir/presentation/profit_and_loss_page.dart',
          ).readAsStringSync(),
        );
        expect(page, isNot(contains('package:krishna_mis/data/repositories')));
        expect(page, isNot(contains('package:krishna_mis/data/reporting')));
        expect(page, isNot(contains('package:krishna_mis/data/sync')));
        expect(page, contains('pnlViewProvider'));
      },
    );

    test(
      'category lines are shown only behind the domain reconciliation check',
      () {
        final page = _code(
          File(
            '$_featureDir/presentation/profit_and_loss_page.dart',
          ).readAsStringSync(),
        );
        expect(page, contains('breakdownReconciles'));
      },
    );
  });

  test('Android keeps its Reports placeholder — the phone P&L is Slice 9', () {
    final router = File('lib/app/routing/app_router.dart').readAsStringSync();
    final mobile = router.substring(
      router.indexOf('_mobileRouter('),
      router.indexOf('_desktopRouter('),
    );
    expect(mobile, isNot(contains('ProfitAndLossPage')));
    final desktop = router.substring(router.indexOf('_desktopRouter('));
    expect(
      desktop,
      contains('ProfitAndLossPage(shellKind: AppShellKind.desktop)'),
    );
  });
}
