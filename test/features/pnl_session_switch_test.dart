/// A P&L on screen belongs to the person it was computed for (D-074, Phase 5 Slice 9).
///
/// `pnlViewProvider` watches the session, so a new person triggers a re-read. A re-read keeps
/// the previous value while it is loading — which is right for a synchronisation landing, and
/// wrong for a person changing: the previous person's figures would stay on screen, to the
/// next person, for as long as the next person's first read waits. That read queues behind
/// the reporting cache lock, so a synchronisation still running when the switch happens holds
/// the previous person's consolidated P&L on screen for its whole duration.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/profit_and_loss_page.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/pnl_fixture.dart';
import '../support/ui_harness.dart';

const _owner = 'user-owner';
const _scoped = 'user-ccr';

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late FakeReportingGateway gateway;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeReportingGateway();
    await seedPnlMasters(db);
  });
  tearDown(() => db.close());

  Future<SwitchableSession> pump(WidgetTester tester, Widget page) async {
    final session = SwitchableSession(pnlSession(userId: _owner));
    await tester.binding.setSurfaceSize(const Size(1366, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(() => session),
          reportingClockProvider.overrideWithValue(() => pnlInstant),
          reportingGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  int? grossOnScreen(WidgetTester tester) {
    final found = find.byKey(const Key('pnl-gross'));
    if (found.evaluate().isEmpty) return null;
    return tester.widget<MoneyText>(found).amount.paise;
  }

  for (final (surface, page) in [
    (
      'Windows',
      const ProfitAndLossPage(shellKind: AppShellKind.desktop) as Widget,
    ),
    ('Android', const MobileProfitAndLossPage() as Widget),
  ]) {
    uiTest(
      '$surface: the previous person\'s figures are not shown to the next person '
      'while a synchronisation holds the cache',
      (tester) async {
        gateway
          ..revenue.add(pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000))
          ..revenue.add(
            pnlSale(
              pnlHki,
              '2026-09-10',
              gross: 999000,
              tax: 0,
              category: 'banquet',
            ),
          );
        final session = await pump(tester, page);
        expect(grossOnScreen(tester), 1104000, reason: 'owner consolidated');

        // A synchronisation is running, holding the cache lock, when the person changes.
        gateway.gate = Completer<void>();
        await tester.tap(find.byKey(const Key('pnl-refresh')));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        session.switchTo(pnlSession(userId: _scoped, grants: pnlD2(pnlCcr)));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(
          grossOnScreen(tester),
          isNot(1104000),
          reason:
              'the owner\'s consolidated gross must not reach the next person',
        );
        expect(find.byKey(const Key('pnl-scope-consolidated')), findsNothing);
        expect(find.byKey(const Key('pnl-scope-$pnlHki')), findsNothing);

        gateway.gate!.complete();
        await tester.pumpAndSettle();
        expect(grossOnScreen(tester), isNot(1104000));
      },
    );
  }
}
