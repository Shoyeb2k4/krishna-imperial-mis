/// Sharing the P&L PDF on Android (Phase 7 Slice 8, D-293): offered only with view
/// authority and `reports.export`, made from the report on screen with no synchronisation,
/// earlier shared files cleaned from the private cache, and no storage permission.
///
/// The share sheet is replaced by a sharer that records what it was handed; everything up
/// to that point is the shipped code.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/features/export/export_providers.dart';
import 'package:krishna_mis/features/export/export_share.dart';
import 'package:krishna_mis/features/export/pnl_share_action.dart';
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

  late Directory cache;
  late Directory shareDir;
  setUp(() {
    cache = Directory.systemTemp.createTempSync('export-share-');
    shareDir = Directory('${cache.path}${Platform.pathSeparator}share')
      ..createSync();
  });
  tearDown(() => cache.deleteSync(recursive: true));

  File inShare(String name) =>
      File('${shareDir.path}${Platform.pathSeparator}$name');

  final shared = <({Uint8List bytes, String fileName})>[];
  setUp(shared.clear);

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required Principal who,
    required PnlView pnl,
    ExportSharer? sharer,
    Future<ExportPdfFonts> Function()? fonts,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _Session(_sessionOf(who))),
          reportingClockProvider.overrideWithValue(() => fxGeneratedAt),
          businessDayRulesProvider.overrideWith((ref) async => const {}),
          masterGraphProvider.overrideWith((ref) async => MasterGraph.empty()),
          pnlViewProvider.overrideWith((ref) async => pnl),
          exportPdfFontsProvider.overrideWith(
            (ref) => fonts == null ? Future.value(fxFonts) : fonts(),
          ),
          exportShareCacheRootProvider.overrideWith((ref) async => cache),
          exportSharerProvider.overrideWithValue(
            sharer ??
                ({required bytes, required fileName}) async {
                  shared.add((bytes: bytes, fileName: fileName));
                  return true;
                },
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: PnlShareAction())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(PnlShareAction)),
    );
  }

  final share = find.byKey(const Key('pnl-share-pdf'));

  Future<String> tapAndRead(WidgetTester tester) async {
    await tester.tap(share);
    for (var i = 0; i < 400; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.byKey(const Key('pnl-share-outcome')).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump();
    return (tester
                    .widget<SnackBar>(
                      find.byKey(const Key('pnl-share-outcome')),
                    )
                    .content
                as Text)
            .data ??
        '';
  }

  testWidgets('the P&L PDF goes to the share sheet, under its readable name', (
    tester,
  ) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(
        fxCcrSeptember(),
        viewer: fxOwner,
        freshness: fxFreshness(),
      ),
    );
    expect(share, findsOneWidget);
    expect(await tapAndRead(tester), 'Opened the share sheet.');
    expect(shared, hasLength(1));
    expect(
      shared.single.fileName,
      'KrishnaImperialMIS_ProfitAndLoss_Property_2026-09-01_2026-09-19.pdf',
    );
    expect(String.fromCharCodes(shared.single.bytes.sublist(0, 5)), '%PDF-');
  });

  testWidgets('sharing is an export: reports.export is required', (
    tester,
  ) async {
    final printOnly = fxPrincipal('user-print-only', [
      for (final g in fxCcrExporter.grants)
        if (g.capability != Capability.reportsExport) g,
    ]);
    await pump(
      tester,
      who: printOnly,
      pnl: fxPnlView(fxCcrSeptember(), viewer: printOnly),
    );
    expect(share, findsNothing);
  });

  testWidgets(
    'reading the P&L is not enough: the Manager bundle cannot share',
    (tester) async {
      await pump(
        tester,
        who: fxManager,
        pnl: fxPnlView(fxCcrSeptember(), viewer: fxManager),
      );
      expect(share, findsNothing);
    },
  );

  testWidgets('an incomplete report cannot be shared', (tester) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner, computed: false),
    );
    expect(share, findsNothing);
  });

  testWidgets('another person\'s report is never shared', (tester) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxManager),
    );
    expect(share, findsNothing);
  });

  testWidgets('offline: a complete report shares, and nothing synchronises', (
    tester,
  ) async {
    // No reporting synchroniser exists at all here — as with no connection.
    final container = await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner),
    );
    expect(await tapAndRead(tester), 'Opened the share sheet.');
    expect(container.read(pnlSyncProvider).phase, PnlSyncPhase.idle);
  });

  testWidgets('earlier shared exports are removed; nothing else is touched', (
    tester,
  ) async {
    inShare(
      'KrishnaImperialMIS_ProfitAndLoss_Old_2026-08-01_2026-08-31.pdf',
    ).writeAsStringSync('an earlier share');
    inShare('someone-elses.pdf').writeAsStringSync('not ours');
    inShare('KrishnaImperialMIS_notes.txt').writeAsStringSync('not a pdf');
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner),
    );
    // Opening the P&L already clears the earlier share.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      inShare(
        'KrishnaImperialMIS_ProfitAndLoss_Old_2026-08-01_2026-08-31.pdf',
      ).existsSync(),
      isFalse,
    );

    // And sharing again clears one left since.
    inShare(
      'KrishnaImperialMIS_ProfitAndLoss_Left_2026-08-01_2026-08-31.pdf',
    ).writeAsStringSync('left by a share');
    await tapAndRead(tester);
    expect(
      inShare(
        'KrishnaImperialMIS_ProfitAndLoss_Left_2026-08-01_2026-08-31.pdf',
      ).existsSync(),
      isFalse,
    );
    expect(inShare('someone-elses.pdf').readAsStringSync(), 'not ours');
    expect(inShare('KrishnaImperialMIS_notes.txt').existsSync(), isTrue);
  });

  testWidgets('a share sheet that cannot open is stated', (tester) async {
    await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner),
      sharer: ({required bytes, required fileName}) async =>
          throw StateError('no activity'),
    );
    expect(
      await tapAndRead(tester),
      'The share sheet could not be opened. Nothing was shared.',
    );
  });

  testWidgets('reports.export lost while the PDF is made shares nothing', (
    tester,
  ) async {
    final gate = Completer<ExportPdfFonts>();
    final container = await pump(
      tester,
      who: fxOwner,
      pnl: fxPnlView(fxCcrSeptember(), viewer: fxOwner),
      fonts: () => gate.future,
    );
    await tester.tap(share);
    await tester.pump();
    (container.read(sessionProvider.notifier) as _Session).become(
      _sessionOf(
        fxPrincipal(fxOwner.userId, [
          for (final g in fxOwner.grants)
            if (g.capability != Capability.reportsExport) g,
        ]),
      ),
    );
    await tester.pump();
    gate.complete(fxFonts);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(shared, isEmpty);
    expect(share, findsNothing);
  });

  test('the Android manifest declares no storage permission', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final permission in [
      'WRITE_EXTERNAL_STORAGE',
      'READ_EXTERNAL_STORAGE',
      'MANAGE_EXTERNAL_STORAGE',
      'READ_MEDIA_',
    ]) {
      expect(manifest, isNot(contains(permission)), reason: permission);
    }
  });

  test('cleanup is safe on a cache with no share folder', () {
    shareDir.deleteSync();
    expect(removeEarlierShares(cache), 0);
  });
}
