/// What production resolves for reporting — read, not assumed.
///
/// Phase 5 Slice 4. This is the assertion D-077 exists to force: every attachment test
/// overrode `attachmentSourceProvider` and none read what production returned, so a
/// feature that did not exist passed a full green acceptance on two real devices.
///
/// The equivalent mistake here is quieter and worse. There are two adapters behind
/// `LocalReportingSource`, and they answer different questions:
///
///   * `CachedReportingSource` reads the **synchronised** cache — what the server says
///     the hotel earned and spent;
///   * `DriftReportingSource` reads this device's own contribution projections — what
///     *this installation* recorded.
///
/// Wiring the second to a P&L screen produces no error and no empty state. It produces a
/// correct sum of the wrong set of rows, on a manager's second phone, for ever (D-173).
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';

import '../support/test_session.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ProviderContainer container;

  /// Signed in, or not. `sessionProvider` refuses to construct itself without real
  /// gateways — inventing authority is exactly what it must not do — so every container
  /// here says which of the two it is.
  ProviderContainer containerFor(SessionState session) => ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sessionProvider.overrideWith(() => StubSession(session)),
    ],
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = containerFor(readySession());
  });
  tearDown(() {
    container.dispose();
    db.close();
  });

  test('the reporting source production resolves reads the cache', () async {
    final source = await container.read(localReportingSourceProvider.future);
    expect(
      source,
      isA<CachedReportingSource>(),
      reason:
          'the device own ledger is not a reporting source. It holds only what this '
          'installation recorded, which sums exactly and is not the hotel figure '
          '(D-173)',
    );
  });

  test('it is scoped to whoever is signed in', () async {
    final source =
        await container.read(localReportingSourceProvider.future)
            as CachedReportingSource;
    expect(
      source.ownerUserId,
      'test-owner',
      reason:
          'the cache is keyed per person, so the source has to name one. A source that '
          'read whatever rows were present would hand this person the previous one '
          'figures on a shared workstation (D-074)',
    );
  });

  test('it names nobody before sign-in, and so can read nothing', () async {
    final anonymous = containerFor(const SessionState.unauthenticated());
    addTearDown(anonymous.dispose);

    final source =
        await anonymous.read(localReportingSourceProvider.future)
            as CachedReportingSource;
    expect(
      source.ownerUserId,
      '',
      reason:
          'fail closed. The anonymous principal owns no cache rows by construction, so '
          'a screen that forgot to check the session still gets nothing rather than '
          'somebody else P&L (D-051 §8)',
    );
  });

  test('the reporting gateway defaults to null and is overridden in main()', () {
    expect(
      container.read(reportingGatewayProvider),
      isNull,
      reason: 'an offline-only build has nothing to synchronise from',
    );

    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main,
      contains('reportingGatewayProvider.overrideWithValue'),
      reason:
          'the null default is the D-077 trap: it is harmless-looking, it makes every '
          'test pass, and it is exactly what shipped to two real devices',
    );

    final bootstrap = File('lib/app/bootstrap.dart').readAsStringSync();
    expect(
      bootstrap,
      contains('ReportingGateway(client)'),
      reason:
          'and main() can only override it if bootstrap actually built one — a promise '
          'to wire it later is what was never kept',
    );
  });

  test('the synchroniser is null with no backend and no session', () {
    expect(
      container.read(reportingSyncProvider),
      isNull,
      reason:
          'no gateway means nothing to synchronise from. It is also rebuilt on every '
          'session change, so it can never hold the previous user id (D-074)',
    );

    final anonymous = containerFor(const SessionState.unauthenticated());
    addTearDown(anonymous.dispose);
    expect(
      anonymous.read(reportingSyncProvider),
      isNull,
      reason:
          'and a synchroniser with no signed-in person has no cache to write into',
    );

    final providers = File('lib/app/providers.dart').readAsStringSync();
    expect(
      providers,
      contains('ref.watch(sessionProvider)'),
      reason: 'the dependency that makes a user switch rebuild it',
    );
  });
}
