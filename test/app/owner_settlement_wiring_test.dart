/// What production actually resolves for the owner settlement surface (OA-3, D-077).
///
/// `ownerLedgerGatewayProvider` defaults to null, which is correct for a build with no
/// backend. A null default that nothing overrides is exactly how D-077 shipped a picker
/// that did not exist, so this reads `main()`'s source, the bootstrap's own result, and
/// what the providers resolve for a real session — rather than a provider a test replaced.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/test_session.dart';

AuthoritySnapshot _authority(String userId, Iterable<CapabilityGrant> grants) =>
    AuthoritySnapshot(
      userId: userId,
      orgId: 'org-1',
      grants: grants,
      resolvedAt: DateTime.utc(2026, 9, 11),
    );

void main() {
  final main_ = File('lib/main.dart').readAsStringSync();
  final bootstrap = File('lib/app/bootstrap.dart').readAsStringSync();

  test('main() overrides the owner gateway from the bootstrap result', () {
    expect(
      main_,
      contains(
        'ownerLedgerGatewayProvider.overrideWithValue(boot.ownerLedgerGateway)',
      ),
    );
    expect(
      bootstrap,
      contains('gatewayForOwners = OwnerLedgerGateway(client);'),
    );
    expect(bootstrap, contains('ownerLedgerGateway: gatewayForOwners,'));
  });

  test('no shipped file overrides it with anything else', () {
    final overrides = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains(
              'ownerLedgerGatewayProvider.overrideWith',
            ))
          file.path,
    ];
    expect(overrides, hasLength(1));
    expect(overrides.single, endsWith('main.dart'));
  });

  group('what the providers resolve for a real session', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    ProviderContainer container(SessionState session) {
      final client = SupabaseClient('http://localhost', 'test-key');
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(() => StubSession(session)),
          ownerLedgerGatewayProvider.overrideWithValue(
            OwnerLedgerGateway(client),
          ),
          reportingGatewayProvider.overrideWithValue(ReportingGateway(client)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the Owner bundle gets a refresher bound to their own id', () {
      final c = container(
        SessionState.ready(
          authority: _authority('owner-user', [
            for (final cap in RoleTemplates.owner) CapabilityGrant(cap),
          ]),
          freshness: AuthorityFreshness.confirmed,
          email: 'owner@example.com',
        ),
      );
      final refresher = c.read(ownerSettlementRefresherProvider);
      expect(refresher, isNotNull);
      expect(refresher!.ownerSync.ownerUserId, 'owner-user');
      expect(
        c.read(ownerSettlementRepositoryProvider).ownerUserId,
        'owner-user',
      );
    });

    test(
      'the Accountant gets no refresher: nothing pulls the owners private position '
      'for a reader who may not see it',
      () {
        final c = container(
          SessionState.ready(
            authority: _authority('accountant-user', [
              for (final cap in RoleTemplates.accountant)
                CapabilityGrant(cap, businessUnitId: 'unit-ccr'),
            ]),
            freshness: AuthorityFreshness.confirmed,
            email: 'accountant@example.com',
          ),
        );
        expect(c.read(ownerSettlementRefresherProvider), isNull);
      },
    );

    test('with no session the repository names nobody who owns a row', () {
      final c = container(const SessionState.unauthenticated());
      expect(c.read(ownerSettlementRefresherProvider), isNull);
      expect(
        c.read(ownerSettlementRepositoryProvider).ownerUserId,
        Principal.anonymous.userId,
      );
    });
  });
}
