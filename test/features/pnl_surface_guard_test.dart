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

/// Android takes no typed date (Phase 5 Slice 9): Custom is the calendar picker, calendar
/// only, and a tapped day is never converted through a zone, UTC or the device clock.
List<String> typedDateEntryViolations(String source) {
  final code = _code(source);
  return [
    for (final (pattern, what) in [
      (RegExp(r'\bTextField\b'), 'a text field'),
      (RegExp(r'\bTextFormField\b'), 'a text form field'),
      (RegExp(r'\bBusinessDate\s*\.\s*tryParse\b'), 'parses typed dates'),
      (
        RegExp(r'DatePickerEntryMode\s*\.\s*(input|inputOnly|calendar)\b'),
        'allows typed date entry',
      ),
      (RegExp(r'\.\s*toUtc\s*\('), 'converts a date through UTC'),
      (RegExp(r'\.\s*toLocal\s*\('), 'converts a date through the device zone'),
      (RegExp(r'\bDateTime\s*\.\s*now\b'), 'reads the device clock'),
    ])
      if (pattern.hasMatch(code)) what,
  ];
}

/// A surface shows a report, and the scopes it offers, only to the person they were
/// computed for (D-074). Reading either provider's value directly would show the previous
/// person's while the next person's loads.
List<String> sessionIsolationViolations(String source) {
  final code = _code(source);
  return [
    for (final (pattern, what) in [
      (
        RegExp(
          r'pnlViewProvider\s*\)\s*\.\s*(value|valueOrNull|requireValue)\b',
        ),
        'shows a report without checking whose it is',
      ),
      (
        RegExp(
          r'pnlScopeOptionsProvider\s*\)\s*\.\s*(value|valueOrNull|requireValue)\b',
        ),
        'offers scopes without checking whose they are',
      ),
    ])
      if (pattern.hasMatch(code)) what,
  ];
}

const _pages = [
  '$_featureDir/presentation/profit_and_loss_page.dart',
  '$_featureDir/presentation/mobile_profit_and_loss_page.dart',
];
const _mobilePage =
    '$_featureDir/presentation/mobile_profit_and_loss_page.dart';

void main() {
  test('there are files to check in the first place', () {
    expect(_files(), hasLength(greaterThanOrEqualTo(4)));
    for (final page in _pages) {
      expect(File(page).existsSync(), isTrue, reason: page);
    }
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

    test(
      'each typed-date-entry violation is detected in a planted snippet',
      () {
        for (final planted in [
          "TextField(key: const Key('pnl-custom-from'))",
          "TextFormField(controller: c)",
          "final d = BusinessDate.tryParse(text);",
          "initialEntryMode: DatePickerEntryMode.input,",
          "initialEntryMode: DatePickerEntryMode.calendar,",
          "final day = picked.start.toUtc();",
          "final day = picked.start.toLocal();",
          "final today = DateTime.now();",
        ]) {
          expect(
            typedDateEntryViolations(planted),
            isNotEmpty,
            reason: planted,
          );
        }
        expect(
          typedDateEntryViolations(
            "initialEntryMode: DatePickerEntryMode.calendarOnly,\n"
            "// no TextField here, and nothing calls DateTime.now",
          ),
          isEmpty,
        );
      },
    );

    test(
      'each session-isolation violation is detected in a planted snippet',
      () {
        for (final planted in [
          "if (ref.watch(pnlViewProvider).value case final v?) {}",
          "final o = ref.watch(pnlScopeOptionsProvider).value;",
          "final v = ref.watch(pnlViewProvider).requireValue;",
        ]) {
          expect(
            sessionIsolationViolations(planted),
            isNotEmpty,
            reason: planted,
          );
        }
        expect(
          sessionIsolationViolations(
            "final v = pnlViewShownTo(ref.watch(pnlViewProvider), principal);",
          ),
          isEmpty,
        );
      },
    );
  });

  group('the P&L surfaces', () {
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
      for (final path in [
        ..._pages,
        '$_featureDir/presentation/pnl_presentation.dart',
      ]) {
        expect(
          _code(File(path).readAsStringSync()),
          isNot(contains('DateTime.now')),
          reason: path,
        );
      }
      final providers = _code(
        File('$_featureDir/presentation/pnl_providers.dart').readAsStringSync(),
      );
      expect(RegExp(r'DateTime\.now').allMatches(providers), hasLength(1));
    });

    for (final path in [
      ..._pages,
      '$_featureDir/presentation/pnl_presentation.dart',
    ]) {
      test(
        '$path reads figures only through the providers, never a repository',
        () {
          final code = _code(File(path).readAsStringSync());
          expect(
            code,
            isNot(contains('package:krishna_mis/data/repositories')),
          );
          expect(code, isNot(contains('package:krishna_mis/data/reporting')));
          expect(code, isNot(contains('package:krishna_mis/data/sync')));
        },
      );
    }

    for (final path in _pages) {
      test('$path reads the report through the providers', () {
        expect(
          _code(File(path).readAsStringSync()),
          contains('pnlViewProvider'),
        );
      });

      test(
        '$path shows category lines only behind the domain reconciliation check',
        () {
          expect(
            _code(File(path).readAsStringSync()),
            contains('breakdownReconciles'),
          );
        },
      );

      test('$path shows a report only to the person it was computed for', () {
        final code = _code(File(path).readAsStringSync());
        expect(sessionIsolationViolations(code), isEmpty);
        expect(code, contains('pnlViewShownTo('));
        expect(code, contains('pnlScopeOptionsShownTo('));
      });
    }
  });

  group('the Android P&L surface (Slice 9)', () {
    test('takes no typed date and converts no picked day', () {
      expect(
        typedDateEntryViolations(File(_mobilePage).readAsStringSync()),
        isEmpty,
      );
    });

    test('chooses Custom dates on the calendar picker, calendar only', () {
      final code = _code(File(_mobilePage).readAsStringSync());
      expect(code, contains('showDateRangePicker('));
      expect(code, contains('DatePickerEntryMode.calendarOnly'));
      expect(code, contains('pnlCustomDatesFrom('));
    });

    test('opens the scope sheet and the picker over the whole screen', () {
      // Over the root navigator, so no choice and no Apply sits behind the bottom bar or
      // the docked [ + ] action.
      final code = _code(File(_mobilePage).readAsStringSync());
      expect(
        RegExp(r'useRootNavigator:\s*true').allMatches(code),
        hasLength(2),
      );
    });

    test('refreshes through the same synchroniser as Windows', () {
      final code = _code(File(_mobilePage).readAsStringSync());
      expect(code, contains('RefreshIndicator('));
      expect(code, contains('pnlSyncProvider'));
      expect(code, isNot(contains('ReportingSync')));
    });
  });

  test(
    'Android Reports opens directly to the phone P&L; Windows keeps it under Analytics',
    () {
      // Anchored on the method declarations. The first `_mobileRouter(` in the file is the
      // call inside `create()`, and the Slice 8 version of this guard sliced from there — a
      // one-line "mobile router" that could contain nothing, so its assertion could never
      // fail. Each anchor is now required to be found before anything is asserted about
      // what lies between them.
      final router = File('lib/app/routing/app_router.dart').readAsStringSync();
      final mobileStart = router.indexOf('static GoRouter _mobileRouter(');
      final desktopStart = router.indexOf('static GoRouter _desktopRouter(');
      expect(mobileStart, isNonNegative);
      expect(desktopStart, greaterThan(mobileStart));
      final mobile = router.substring(mobileStart, desktopStart);
      final reportsStart = mobile.indexOf('AppRoutes.reports');
      final moreStart = mobile.indexOf('AppRoutes.more');
      expect(reportsStart, isNonNegative);
      expect(moreStart, greaterThan(reportsStart));
      final reports = mobile.substring(reportsStart, moreStart);
      expect(reports, contains('const MobileProfitAndLossPage()'));
      expect(reports, isNot(contains('PlaceholderPage')));
      expect(mobile, isNot(contains('ProfitAndLossPage(shellKind')));

      final desktop = router.substring(desktopStart);
      expect(
        desktop,
        contains('ProfitAndLossPage(shellKind: AppShellKind.desktop)'),
      );
      expect(desktop, isNot(contains('MobileProfitAndLossPage')));
    },
  );
}
