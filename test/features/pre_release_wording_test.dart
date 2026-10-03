/// Phase 9 Slice 3 — pre-release wording (D-343, D-348).
///
/// When a master, tax, supplier or sales-ledger read fails, the screen says what failed in
/// words a manager can act on, and **Try again reads again**. The exception — its class
/// name, its text, any path inside it — goes to the developer log and never to the screen.
///
/// Every test here runs with Riverpod's automatic retry switched off, so a recovery can
/// only come from the person pressing Try again. Without that, a background retry could
/// make a button that does nothing look as if it worked.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/app/routing/app_routes.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/vendor_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/features/masters/presentation/android_masters_view.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_chrome.dart';
import 'package:krishna_mis/features/masters/presentation/windows_masters_view.dart';
import 'package:krishna_mis/features/placeholder/placeholder_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_filters.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_ledger_page.dart';
import 'package:krishna_mis/features/tax/presentation/tax_rates_view.dart';
import 'package:krishna_mis/features/vendors/presentation/vendors_view.dart';

import '../support/test_session.dart';
import '../support/ui_harness.dart';

/// A failure carrying every kind of technical detail the screen must not show.
class _TechnicalFailure implements Exception {
  const _TechnicalFailure();

  @override
  String toString() =>
      'SqliteException(11): database disk image is malformed, '
      r'C:\Users\someone\AppData\Roaming\Krishna Imperial\krishna_mis.db'
      ' (masterGraphProvider)';
}

/// No exception text, class name, provider name, SQLite message or path is on screen.
void _expectNoRawError(WidgetTester tester) {
  final text = [
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      t.data ?? t.textSpan?.toPlainText() ?? '',
    for (final t in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    ))
      t.data ?? t.textSpan?.toPlainText() ?? '',
  ].join('\n');
  for (final forbidden in [
    '_TechnicalFailure',
    'SqliteException',
    'malformed',
    'Provider',
    r'C:\',
    'AppData',
    'krishna_mis.db',
    'Exception',
    'Instance of',
    '#0',
  ]) {
    expect(text, isNot(contains(forbidden)), reason: forbidden);
  }
}

Principal _owner() => Principal(
  userId: 'test-owner',
  grants: [for (final c in RoleTemplates.owner) CapabilityGrant(c)],
);

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 6, 15, 9);

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedMasterData(db, now: now);
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget view, {
    required Size size,
    required List<Override> overrides,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    final principal = _owner();
    await tester.pumpWidget(
      ProviderScope(
        // Only an explicit Try again may recover (see the library comment).
        retry: (_, _) => null,
        overrides: [
          databaseProvider.overrideWithValue(db),
          outboxProvider.overrideWithValue(OutboxRepository(db)),
          principalProvider.overrideWithValue(principal),
          sessionProvider.overrideWith(
            () => StubSession(
              readySession(
                authority: AuthoritySnapshot(
                  userId: principal.userId,
                  orgId: seedOrgId,
                  grants: principal.grants,
                  resolvedAt: now,
                ),
              ),
            ),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          theme: size.width > 900 ? AppTheme.desktop : AppTheme.mobile,
          home: Scaffold(body: view),
        ),
      ),
    );
    await settle(tester);
  }

  /// A master graph read that fails on the first attempt and succeeds afterwards.
  Override failingGraph(List<int> reads) =>
      masterGraphProvider.overrideWith((ref) {
        reads.add(reads.length);
        if (reads.length == 1) {
          return Future<MasterGraph>.error(const _TechnicalFailure());
        }
        return MasterGraph.empty();
      });

  Future<void> retry(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await settle(tester);
  }

  group('Masters', () {
    for (final (name, view, size) in [
      ('Windows', const WindowsMastersView(), const Size(1366, 768)),
      ('Android', const AndroidMastersView(), const Size(360, 740)),
    ]) {
      uiTest(
        '$name: a failed read says so in words, and Try again reads again',
        (tester) async {
          final reads = <int>[];
          await pump(
            tester,
            view,
            size: size,
            overrides: [failingGraph(reads)],
          );

          expect(find.text(masterStructureUnreadable), findsOneWidget);
          _expectNoRawError(tester);
          expect(reads, hasLength(1));
          expect(tester.takeException(), isNull, reason: 'it fits, unclipped');

          await retry(tester, const Key('master-read-retry'));

          expect(
            reads,
            hasLength(2),
            reason: 'Try again read the structure again',
          );
          expect(find.text(masterStructureUnreadable), findsNothing);
        },
      );
    }
  });

  group('Tax rates', () {
    for (final (name, desktop, size) in [
      ('Windows', true, const Size(1366, 768)),
      ('Android', false, const Size(360, 740)),
    ]) {
      uiTest('$name: a failed rule read shows plain words, and retries', (
        tester,
      ) async {
        final reads = <int>[];
        await pump(
          tester,
          TaxRatesView(isDesktop: desktop),
          size: size,
          overrides: [
            masterGraphProvider.overrideWith((ref) => MasterGraph.empty()),
            taxRulesProvider.overrideWith((ref) {
              reads.add(reads.length);
              if (reads.length == 1) {
                return Future<Map<String, TaxRuleSet>>.error(
                  const _TechnicalFailure(),
                );
              }
              return const <String, TaxRuleSet>{};
            }),
          ],
        );

        expect(find.text(taxConfigurationUnreadable), findsOneWidget);
        _expectNoRawError(tester);
        expect(tester.takeException(), isNull);

        await retry(tester, const Key('master-read-retry'));

        expect(reads, hasLength(2), reason: 'Try again read the rules again');
        expect(find.text(taxConfigurationUnreadable), findsNothing);
      });
    }

    uiTest('a failed hierarchy read on the tax screen also retries', (
      tester,
    ) async {
      final reads = <int>[];
      await pump(
        tester,
        const TaxRatesView(isDesktop: true),
        size: const Size(1366, 768),
        overrides: [
          failingGraph(reads),
          taxRulesProvider.overrideWith((ref) => const <String, TaxRuleSet>{}),
        ],
      );
      expect(find.text(taxConfigurationUnreadable), findsOneWidget);
      _expectNoRawError(tester);

      await retry(tester, const Key('master-read-retry'));

      expect(reads, hasLength(2));
      expect(find.text(taxConfigurationUnreadable), findsNothing);
    });
  });

  group('Vendors', () {
    for (final (name, desktop, size) in [
      ('Windows', true, const Size(1366, 768)),
      ('Android', false, const Size(360, 740)),
    ]) {
      uiTest('$name: a failed supplier read shows plain words, and retries', (
        tester,
      ) async {
        final reads = <bool>[];
        await pump(
          tester,
          VendorsView(isDesktop: desktop),
          size: size,
          overrides: [
            vendorListProvider.overrideWith((ref, showArchived) {
              reads.add(showArchived);
              if (reads.length == 1) {
                return Future<List<Vendor>>.error(const _TechnicalFailure());
              }
              return <
                Vendor
              >[]; // growable: the view sorts the list it is given
            }),
          ],
        );

        expect(find.text(suppliersUnreadable), findsOneWidget);
        _expectNoRawError(tester);
        expect(tester.takeException(), isNull);

        await retry(tester, const Key('master-read-retry'));

        expect(
          reads,
          hasLength(2),
          reason: 'Try again read the suppliers again',
        );
        expect(
          reads.toSet(),
          {false},
          reason: 'the retry kept the archived filter the screen was using',
        );
        expect(find.text(suppliersUnreadable), findsNothing);
      });
    }
  });

  group('Revenue ledger', () {
    for (final (name, kind, size) in [
      ('Windows', AppShellKind.desktop, const Size(1366, 768)),
      ('Android', AppShellKind.mobile, const Size(360, 740)),
    ]) {
      uiTest('$name: a failed ledger read shows plain words, and retries', (
        tester,
      ) async {
        final reads = <int>[];
        await pump(
          tester,
          RevenueLedgerPage(shellKind: kind),
          size: size,
          overrides: [
            filteredRevenueProvider.overrideWith((ref) {
              reads.add(reads.length);
              if (reads.length == 1) {
                return Stream<List<RevenueLedgerRow>>.error(
                  const _TechnicalFailure(),
                );
              }
              return Stream.value(const <RevenueLedgerRow>[]);
            }),
          ],
        );

        expect(find.text('The sales ledger could not be read'), findsOneWidget);
        expect(find.text(revenueLedgerUnreadable), findsOneWidget);
        _expectNoRawError(tester);
        expect(tester.takeException(), isNull);

        await retry(tester, const Key('revenue-ledger-retry'));

        expect(reads, hasLength(2), reason: 'Try again read the ledger again');
        expect(find.byKey(const Key('revenue-ledger-error')), findsNothing);
      });
    }
  });

  group('Administration', () {
    testWidgets('the desktop destination carries the approved V1 wording', (
      tester,
    ) async {
      final router = AppRouter.create(
        shellKind: AppShellKind.desktop,
        initialLocation: AppRoutes.administration,
      );
      addTearDown(router.dispose);
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

      expect(find.byType(PlaceholderPage), findsOneWidget);
      expect(
        find.text(
          'Users, roles, period close and audit review are handled by the '
          'project administrator in this version.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Phase'), findsNothing);
      expect(find.text('Not built yet'), findsNothing);
      expect(find.textContaining('will be built'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
