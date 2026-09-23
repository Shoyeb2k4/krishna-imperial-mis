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

/// The P&L boundary.
///
/// Slice 8 forbade any department, section or vendor detail and any navigation. Slice 10
/// narrows exactly that, and nothing else: the approved Department → Section → Category →
/// Documents hierarchy may name those identities, and the phone may push its own drill-down
/// pages. Router navigation to another destination, export, printing, charts and owner
/// settlement stay forbidden, and where a pushed route may go is pinned separately
/// ([navigationViolations]).
List<String> boundaryViolations(String source) {
  final code = _code(source);
  return [
    for (final (pattern, what) in [
      (RegExp(r'context\s*\.\s*(go|push)\b'), 'router navigation'),
      (RegExp(r'\bGoRouter\b|\bAppRoutes\s*\.'), 'router navigation'),
      (RegExp(r'\b(Export|Excel|PDF|Printing|Print)\b'), 'export or printing'),
      (RegExp(r'\b(Chart|LineChart|BarChart|fl_chart)\b'), 'a chart'),
      (RegExp(r'owner_settlement'), 'owner settlement'),
    ])
      if (pattern.hasMatch(code)) what,
  ];
}

/// The only pages the P&L may push are its own drill-down pages. Every
/// `MaterialPageRoute` builder must construct one of them, and no other feature's screen
/// may be imported — a report must not become a way into a transaction surface that can act.
const _pushablePages = {'MobilePnlDrillPage', 'MobilePnlDocumentPage'};

List<String> navigationViolations(String source) {
  final code = _code(source);
  final routes = RegExp(r'MaterialPageRoute').allMatches(code).length;
  final built = RegExp(
    r'MaterialPageRoute<[^>]*>\(\s*builder:\s*\([^)]*\)\s*=>\s*(?:const\s+)?(\w+)\(',
  ).allMatches(code).map((m) => m.group(1)!).toList();
  return [
    if (built.length != routes) 'a route this guard cannot read',
    for (final page in built)
      if (!_pushablePages.contains(page)) 'pushes $page',
    for (final (pattern, what) in [
      (
        RegExp(
          r'features/(expenses|revenue|transactions)/presentation/\w+_page\.dart',
        ),
        'imports a transaction screen',
      ),
      (
        RegExp(r'features/(expenses|revenue)/presentation/\w+_ledger'),
        'imports a ledger',
      ),
    ])
      if (pattern.hasMatch(source)) what,
  ];
}

/// Nothing on the report path can act on a document (Slice 10, Q2).
///
/// Not a hidden button: no action widget, controller, repository, sync worker, outbox, pull
/// or write method is imported or named, and no mutation control key exists. Applied to every
/// P&L file and to the two immutable document bodies.
List<String> mutationViolations(String source) {
  final withStrings = _code(source);
  final code = _codeOnly(source);
  return [
    for (final (pattern, what) in [
      (RegExp(r'revenue_actions\.dart'), 'imports revenue actions'),
      (RegExp(r'revenue_conflict\.dart'), 'imports the revenue conflict flow'),
      (RegExp(r'revenue_evidence\.dart'), 'imports the evidence control'),
      (RegExp(r'attachment_strip\.dart'), 'imports the attachment strip'),
      (RegExp(r'revenue_detail_panel\.dart'), 'imports the ledger sale panel'),
      (
        RegExp(r'expense_detail_panel\.dart'),
        'imports the ledger expense panel',
      ),
      (RegExp(r'revenue_providers\.dart'), 'imports revenue controllers'),
      (RegExp(r'expense_providers\.dart'), 'imports expense controllers'),
      (RegExp(r'edit_launcher\.dart'), 'imports the expense editor'),
      (RegExp(r'void_dialog\.dart'), 'imports the void dialog'),
      (RegExp(r'expense_edit_loader\.dart'), 'imports the edit loader'),
      (RegExp(r'_entry_page\.dart'), 'imports an entry form'),
      (RegExp(r'sync_state_chip\.dart'), 'imports the sync chip'),
      (
        RegExp(r'data/repositories/(expense|revenue)_repository'),
        'imports a transaction repository',
      ),
      (
        RegExp(
          r"Key\('(revenue-edit|revenue-void|edit-expense|void-expense|conflict-review-latest|revenue-conflict-review-latest)'\)",
        ),
        'a mutation control key',
      ),
    ])
      if (pattern.hasMatch(withStrings)) what,
    for (final (pattern, what) in [
      (
        RegExp(
          r'\b(RevenueActions|RevenueEvidence|AttachmentStrip|RevenueDetailPanel|ExpenseDetailPanel|SyncStateChip)\b',
        ),
        'composes an action surface',
      ),
      (
        RegExp(
          r'\b(reviewLatestRevenue|reviewLatestAfterConflict|openExpenseEditor|showVoidDialog)\b',
        ),
        'opens a mutation flow',
      ),
      (
        RegExp(
          r'\b(createLocally|updateLocally|voidLocally|attachLocally|applyServerDocument|pullOne|voidEntry|voidExpense|applyEdit)\b',
        ),
        'calls a write',
      ),
      (
        RegExp(
          r'\b(syncEngineProvider|outboxProvider|expensePullProvider|revenueEntryControllerProvider|expenseEntryControllerProvider|expenseVoidControllerProvider|attachmentUploadWorkerProvider)\b',
        ),
        'reaches a writer',
      ),
      (
        RegExp(r'\b(customStatement|customUpdate|customInsert)\b|\.into\('),
        'writes to a database',
      ),
    ])
      if (pattern.hasMatch(code)) what,
  ];
}

const _documentBodies = [
  'lib/features/revenue/presentation/widgets/revenue_document_body.dart',
  'lib/features/expenses/presentation/widgets/expense_document_body.dart',
];

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
        "context.go('/transactions');",
        "context.push('/expenses');",
        "GoRouter.of(context).go(AppRoutes.transactions);",
        "FilledButton(child: Text('Export'))",
        "LineChart(data)",
        "import 'package:krishna_mis/features/owner_settlement/x.dart';",
      ]) {
        expect(boundaryViolations(planted), isNotEmpty, reason: planted);
      }
      // What Slice 10 approved is not a violation: the hierarchy's identities.
      expect(
        boundaryViolations("line.departmentId; line.sectionId; line.vendorId;"),
        isEmpty,
      );
    });

    test('each navigation violation is detected in a planted snippet', () {
      for (final planted in [
        "Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExpenseLedgerPage(shellKind: k)));",
        "Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevenueDetailPage(entryId: id)));",
        "import 'package:krishna_mis/features/expenses/presentation/expense_entry_page.dart';",
        "import 'package:krishna_mis/features/revenue/presentation/revenue_ledger_page.dart';",
        "MaterialPageRoute(builder: pageFor)",
      ]) {
        expect(navigationViolations(planted), isNotEmpty, reason: planted);
      }
      expect(
        navigationViolations(
          "Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MobilePnlDrillPage(location: l)));\n"
          "Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MobilePnlDocumentPage(request: r)));",
        ),
        isEmpty,
      );
    });

    test('each mutation violation is detected in a planted snippet', () {
      // The positive control Slice 10 requires: a drill-down that gained any action surface
      // is caught, whether by import, by widget, by call, by provider or by key.
      for (final planted in [
        "import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_actions.dart';",
        "import 'package:krishna_mis/features/expenses/presentation/widgets/expense_detail_panel.dart';",
        "import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';",
        "import 'package:krishna_mis/data/repositories/revenue_repository.dart';",
        "RevenueActions(entry: entry)",
        "RevenueEvidence(entry: entry)",
        "ExpenseDetailPanel(expenseId: id)",
        "SyncStateChip(state)",
        "reviewLatestRevenue(context, ref, entry);",
        "showVoidDialog(context, ref, expense);",
        "await pull.pullOne(id);",
        "await repository.applyServerDocument(header: h, components: c, orgId: o);",
        "ref.read(revenueEntryControllerProvider).voidEntry(entryId: id);",
        "ref.read(syncEngineProvider)?.pushOnce();",
        "OutlinedButton(key: const Key('revenue-void'), onPressed: f, child: t)",
        "FilledButton(key: const Key('edit-expense'), onPressed: f, child: t)",
        "await db.customStatement('INSERT INTO expenses VALUES (?)');",
      ]) {
        expect(mutationViolations(planted), isNotEmpty, reason: planted);
      }
      expect(
        mutationViolations(
          "// no RevenueActions, no pullOne and no voidEntry here\n"
          "RevenueDocumentBody(entry: e, graph: g)",
        ),
        isEmpty,
      );
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

      test('${file.path} stays inside the P&L boundary', () {
        expect(boundaryViolations(file.readAsStringSync()), isEmpty);
      });

      test('${file.path} pushes only the P&L drill-down pages', () {
        expect(navigationViolations(file.readAsStringSync()), isEmpty);
      });

      test('${file.path} can reach no action, write or mutation control', () {
        expect(mutationViolations(file.readAsStringSync()), isEmpty);
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

  group('the read-only drill-down (Slice 10)', () {
    for (final path in _documentBodies) {
      test('$path is an immutable body: no action surface at all', () {
        expect(mutationViolations(File(path).readAsStringSync()), isEmpty);
      });
    }

    test(
      'the drill-down renders documents only through the immutable bodies',
      () {
        final view = _code(
          File(
            '$_featureDir/presentation/pnl_drilldown_view.dart',
          ).readAsStringSync(),
        );
        expect(view, contains('RevenueDocumentBody('));
        expect(view, contains('ExpenseDocumentBody('));
        // And composes nothing into the slots a ledger uses for its controls.
        for (final slot in [
          'status:',
          'attention:',
          'evidence:',
          'banners:',
          'actions:',
        ]) {
          expect(view, isNot(contains(slot)), reason: 'composes $slot');
        }
      },
    );

    test('the ledgers still compose their own actions around the same bodies', () {
      // The complement: the guard above would pass just as happily if the actions had been
      // deleted from the product rather than kept off the report path.
      final revenue = _code(
        File(
          'lib/features/revenue/presentation/widgets/revenue_detail_panel.dart',
        ).readAsStringSync(),
      );
      expect(revenue, contains('RevenueDocumentBody('));
      expect(revenue, contains('RevenueActions('));
      expect(revenue, contains('RevenueEvidence('));
      final expense = _code(
        File(
          'lib/features/expenses/presentation/widgets/expense_detail_panel.dart',
        ).readAsStringSync(),
      );
      expect(expense, contains('ExpenseDocumentBody('));
      expect(expense, contains("Key('edit-expense')"));
      expect(expense, contains("Key('void-expense')"));
    });

    test(
      'every level is shown only behind the domain reconciliation checks',
      () {
        final providers = _code(
          File(
            '$_featureDir/presentation/pnl_drilldown_providers.dart',
          ).readAsStringSync(),
        );
        expect(
          RegExp(r'expenseChildrenReconcile\(').allMatches(providers).length,
          greaterThanOrEqualTo(2),
        );
        expect(providers, contains('revenueChildrenReconcile('));
        expect(providers, contains('PnlDrillRefusal.unreconciled'));
      },
    );

    test(
      'a document is opened only from a row the current bucket produced',
      () {
        final providers = _code(
          File(
            '$_featureDir/presentation/pnl_drilldown_providers.dart',
          ).readAsStringSync(),
        );
        expect(providers, contains('documents.contains(line)'));
        // No request type carries a bare id a person could type.
        expect(
          RegExp(
            r'class Pnl\w*DocumentRequest[^{]*\{[^}]*final String',
          ).hasMatch(providers),
          isFalse,
        );
      },
    );
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
      // Since Phase 6 Slice 8 the desktop Analytics branch is the Analytics workspace,
      // which embeds this same page as its Profit & Loss section — asserted there, in
      // the analytics surface guard, so the P&L is still the Phase 5 page and not a copy.
      expect(
        desktop,
        contains('AnalyticsPage(shellKind: AppShellKind.desktop)'),
      );
      expect(
        File(
          'lib/features/analytics/presentation/analytics_page.dart',
        ).readAsStringSync(),
        contains('ProfitAndLossPage(shellKind: widget.shellKind)'),
      );
      expect(desktop, isNot(contains('MobileProfitAndLossPage')));
    },
  );
}
