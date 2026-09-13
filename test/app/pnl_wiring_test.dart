/// What production resolves for the Windows P&L — read, not assumed (Phase 5 Slice 8).
///
/// The failure D-077 names: a surface every test overrides, whose production wiring nobody
/// reads. Here that would be a P&L that reads this device's own ledger rather than the
/// synchronised canonical cache, or a refresh that never reaches the server because the
/// synchroniser it uses is not the one `main()` wires. Both would pass every widget test.
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/app/routing/app_routes.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/profit_and_loss_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/test_session.dart';

String _code(String path) =>
    File(path).readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test(
    'the P&L reads through the canonical engine and the wired synchroniser',
    () {
      final providers = _code(
        'lib/features/profit_and_loss/presentation/pnl_providers.dart',
      );
      expect(providers, contains('localReportingEngineProvider'));
      expect(providers, contains('reportingSyncProvider'));
      expect(providers, contains('localReportingSourceProvider'));
    },
  );

  test(
    'production resolves the cached canonical source behind the P&L engine',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(() => StubSession(readySession())),
        ],
      );
      addTearDown(container.dispose);

      final engine = await container.read(localReportingEngineProvider.future);
      expect(engine.source, isA<CachedReportingSource>());
      // No backend configured in this container, so no synchroniser: the surface reports
      // "unavailable" rather than inventing one.
      expect(container.read(reportingSyncProvider), isNull);
      expect(
        container.read(pnlReportingLockProvider),
        isA<ReportingCacheLock>(),
      );
    },
  );

  test('main() wires the reporting gateway the P&L synchroniser needs', () {
    final main = _code('lib/main.dart');
    expect(main, contains('reportingGatewayProvider.overrideWithValue'));
  });

  testWidgets(
    'the desktop Analytics destination is the P&L page, not a placeholder',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final router = AppRouter.create(
        shellKind: AppShellKind.desktop,
        initialLocation: AppRoutes.analytics,
      );
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sessionProvider.overrideWith(() => StubSession(readySession())),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ProfitAndLossPage), findsOneWidget);
      expect(find.text('Not built yet'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
