/// What production resolves for opening a document from a report (Phase 5 Slice 10, D-077).
///
/// A null default left standing while every test supplies its own replacement is how a
/// feature ships without existing. So this reads what `main()` and the acceptance harness
/// actually wire, and what the providers resolve from it.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

import '../support/test_session.dart';

void main() {
  test('main() and the acceptance harness both supply the expense gateway', () {
    const override =
        'expenseGatewayProvider.overrideWithValue(boot.expenseGateway)';
    expect(File('lib/main.dart').readAsStringSync(), contains(override));
    expect(
      File('integration_test/device_acceptance_test.dart').readAsStringSync(),
      contains(override),
    );
    final bootstrap = File('lib/app/bootstrap.dart').readAsStringSync();
    expect(bootstrap, contains('gatewayForExpenses = expenseGateway;'));
    expect(bootstrap, contains('expenseGateway: gatewayForExpenses,'));
  });

  group('the providers', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    SupabaseClient client() => SupabaseClient(
      'http://localhost',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

    test('resolve a reader from the two production gateways', () {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(() => StubSession(readySession())),
          expenseGatewayProvider.overrideWithValue(ExpenseGateway(client())),
          revenueGatewayProvider.overrideWithValue(RevenueGateway(client())),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(reportDocumentReaderProvider), isNotNull);
    });

    test(
      'resolve no reader with no backend, which the surface reports as not downloaded',
      () {
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sessionProvider.overrideWith(() => StubSession(readySession())),
          ],
        );
        addTearDown(container.dispose);
        expect(container.read(reportDocumentReaderProvider), isNull);
      },
    );

    test('resolve the drill-down source for the person signed in', () async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(() => StubSession(readySession())),
        ],
      );
      addTearDown(container.dispose);
      final source = await container.read(
        reportingDrilldownSourceProvider.future,
      );
      expect(source.principal.userId, 'test-owner');
    });
  });
}
