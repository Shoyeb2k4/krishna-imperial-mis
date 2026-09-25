/// The Windows Export Centre (Phase 7 Slice 6, D-297): only the actions authority allows,
/// the screen's own report and wording, and no synchronisation.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/export/export_centre_page.dart';
import 'package:krishna_mis/features/export/export_file_save.dart';
import 'package:krishna_mis/features/export/export_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/export_delivery_fixtures.dart';
import '../../support/export_fixtures.dart';
import '../../support/test_session.dart';

class _Session extends StubSession {
  _Session(super.initial);
  void become(SessionState next) => state = next;
}

SessionState _sessionOf(Principal who) => readySession(
  authority: AuthoritySnapshot(
    userId: who.userId,
    orgId: 'test-org',
    resolvedAt: DateTime.utc(2026, 9, 19),
    grants: who.grants,
  ),
);

void main() {
  tzdata.initializeTimeZones();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('export-centre-'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required Principal who,
    PnlView? pnl,
    DashboardState? dashboard,
    bool consolidatedAllowed = true,
    bool readsAnything = true,
    Future<String?> Function()? pick,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1366, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _Session(_sessionOf(who))),
          reportingClockProvider.overrideWithValue(() => fxGeneratedAt),
          businessDayRulesProvider.overrideWith((ref) async => const {}),
          masterGraphProvider.overrideWith((ref) async => MasterGraph.empty()),
          pnlScopeOptionsProvider.overrideWith(
            (ref) async => PnlScopeOptions(
              units: readsAnything
                  ? const [PnlUnitOption(id: fxCcr, name: 'Crystal Canopy')]
                  : const [],
              consolidatedAllowed: consolidatedAllowed && readsAnything,
              viewerUserId: who.userId,
            ),
          ),
          pnlViewProvider.overrideWith(
            (ref) async => pnl ?? const PnlNotAuthorised(),
          ),
          dashboardViewProvider.overrideWith(
            (ref) async => dashboard ?? DashboardNotAuthorised('nobody'),
          ),
          exportPdfFontsProvider.overrideWith((ref) async => fxFonts),
          exportFileSaverProvider.overrideWithValue(
            ExportFileSaver(
              pickLocation: ({required suggestedName, required format}) async =>
                  pick == null
                  ? '${dir.path}${Platform.pathSeparator}$suggestedName'
                  : await pick(),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ExportCentrePage())),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ExportCentrePage)),
    );
  }

  Finder key(String k) => find.byKey(Key(k));

  /// Real file I/O completes on the real event loop, and its continuations run in the
  /// test's zone only when it pumps — so the two are interleaved until the outcome shows
  /// (D-152: wait for the condition, never for a number of frames).
  Future<void> tapAndFinish(WidgetTester tester, String k) async {
    await tester.tap(key(k));
    final report = k.split('-')[1];
    for (var i = 0; i < 400; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (key('export-$report-outcome').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(key('export-$report-outcome'), findsOneWidget);
  }

  testWidgets('the Owner is offered every save for every report', (
    tester,
  ) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(
        fxConsolidated(),
        viewer: fxOwner,
        freshness: fxFreshness(),
      ),
      dashboard: fxDashboard(viewer: fxOwner, freshness: fxFreshness()),
    );
    for (final report in [
      'profitAndLoss',
      'revenueAnalysis',
      'expenseAnalysis',
      'businessComparison',
    ]) {
      expect(key('export-$report'), findsOneWidget);
      expect(key('export-$report-pdf'), findsOneWidget);
      expect(key('export-$report-xlsx'), findsOneWidget);
    }
    // No figure is shown here: the Export Centre is not a second P&L (D-297).
    expect(find.textContaining('₹'), findsNothing);
    expect(key('export-profitAndLoss-covers'), findsOneWidget);
    expect(
      tester.widget<Text>(key('export-profitAndLoss-freshness')).data,
      startsWith('Synchronised as of'),
    );
  });

  testWidgets('a Manager reads the P&L and is offered no export (D-292)', (
    tester,
  ) async {
    await pump(
      tester,
      who: fxManager,
      consolidatedAllowed: false,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxManager),
    );
    expect(key('export-profitAndLoss-pdf'), findsNothing);
    expect(key('export-profitAndLoss-xlsx'), findsNothing);
    expect(
      tester.widget<Text>(key('export-profitAndLoss-not-offered')).data,
      'Your account can read this report but not export it.',
    );
  });

  testWidgets('somebody who reads no report sees no report and no action', (
    tester,
  ) async {
    await pump(tester, who: fxActionOnly, readsAnything: false);
    expect(key('export-centre-not-authorised'), findsOneWidget);
    expect(key('export-profitAndLoss'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('an incomplete report says why, and offers nothing', (
    tester,
  ) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner, computed: false),
    );
    expect(key('export-profitAndLoss-unavailable'), findsOneWidget);
    expect(key('export-profitAndLoss-pdf'), findsNothing);
    expect(find.textContaining('₹0'), findsNothing);
  });

  testWidgets('a report read for somebody else is not offered', (tester) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxManager),
    );
    expect(key('export-profitAndLoss-pdf'), findsNothing);
    expect(key('export-profitAndLoss-covers'), findsNothing);
  });

  testWidgets('opening the Export Centre synchronises nothing', (tester) async {
    final container = await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner, computed: false),
      dashboard: fxDashboard(viewer: fxOwner),
    );
    expect(container.read(pnlSyncProvider).phase, PnlSyncPhase.idle);
    expect(
      container.read(dashboardSyncProvider).phase,
      DashboardSyncPhase.idle,
    );
  });

  testWidgets('Save Excel writes the workbook where the person chose', (
    tester,
  ) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner),
    );
    await tapAndFinish(tester, 'export-profitAndLoss-xlsx');

    const name =
        'KrishnaImperialMIS_ProfitAndLoss_Property_2026-09-01_2026-09-19.xlsx';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync().sublist(0, 2), [0x50, 0x4B]); // "PK": a ZIP.
    expect(
      tester.widget<Text>(key('export-profitAndLoss-outcome')).data,
      'Saved $name.',
    );
  });

  testWidgets('Save PDF writes a PDF', (tester) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner),
    );
    await tapAndFinish(tester, 'export-profitAndLoss-pdf');
    final files = dir.listSync().whereType<File>().toList();
    expect(files.single.path, endsWith('.pdf'));
    expect(
      String.fromCharCodes(files.single.readAsBytesSync().sublist(0, 5)),
      '%PDF-',
    );
  });

  testWidgets('cancelling Save As writes nothing and says so plainly', (
    tester,
  ) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner),
      pick: () async => null,
    );
    await tapAndFinish(tester, 'export-profitAndLoss-pdf');
    expect(dir.listSync(), isEmpty);
    expect(
      tester.widget<Text>(key('export-profitAndLoss-outcome')).data,
      'Cancelled. Nothing was saved.',
    );
  });

  testWidgets('losing reports.export while Save As is open writes nothing', (
    tester,
  ) async {
    late ProviderContainer container;
    final withoutExport = fxPrincipal(fxOwner.userId, [
      for (final g in fxOwner.grants)
        if (g.capability != Capability.reportsExport) g,
    ]);
    container = await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner),
      pick: () async {
        (container.read(sessionProvider.notifier) as _Session).become(
          _sessionOf(withoutExport),
        );
        return '${dir.path}${Platform.pathSeparator}september.pdf';
      },
    );
    await tapAndFinish(tester, 'export-profitAndLoss-pdf');
    expect(dir.listSync(), isEmpty);
    expect(
      tester.widget<Text>(key('export-profitAndLoss-outcome')).data,
      startsWith('Your access changed'),
    );
    // And the action is gone from the card.
    expect(key('export-profitAndLoss-pdf'), findsNothing);
  });

  testWidgets(
    'Business Comparison without consolidated access offers nothing',
    (tester) async {
      await pump(
        tester,
        who: fxCcrExporter,
        consolidatedAllowed: false,
        dashboard: fxDashboard(viewer: fxCcrExporter),
      );
      expect(key('export-businessComparison-pdf'), findsNothing);
      expect(key('export-businessComparison-xlsx'), findsNothing);
    },
  );
}
