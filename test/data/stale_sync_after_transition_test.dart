/// D-231 — a synchronisation started for one session or authority must not land after it.
///
/// Phase 5 Slice 11. Every earlier slice proved the purge removes a person's canonical
/// cache at sign-out and on a confirmed capability loss. None proved what happens to a
/// synchronisation that was **already on the wire** when that happened: its answer arrives
/// after the purge, and the synchroniser still holds the old person's id.
///
/// The invariant under test, as the project lead ruled it:
///
/// > A sync started under a viewer/session/authority generation that is no longer current
/// > must not apply its result after a confirmed session transition or relevant confirmed
/// > authority revocation.
///
/// Everything here is real — the database file, the cache, the synchroniser, the purge and
/// the session controller. The only thing substituted is the server, and the only thing it
/// does that a real one does not is hold its answer until the test lets it go.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/session/session_controller.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/remote/auth_gateway.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/expense_fixtures.dart' show createTempDatabaseFile;
import '../support/pnl_fixture.dart';
import 'owner_settlement_sync_test.dart' show movementJson, snapshot;

const _a = 'user-a';
const _b = 'user-b';

/// The document the held answer carries. Distinctive text, so the database **file** can be
/// searched for it: a row that is unreadable to B but sitting on disk is still A's figure
/// on a shared machine.
const _inflightEntry = 're-INFLIGHT-A-D231';
const _inflightMovement = 'mv-INFLIGHT-A-D231';

final _fy = FinancialYear.of(BusinessDate.of(2026, 6, 15));

class _Auth implements SessionAuth {
  AuthenticatedUser? user;

  @override
  AuthenticatedUser? get currentUser => user;

  @override
  Future<SignInResult> signIn({
    required String email,
    required String password,
  }) async => SignInResult.ok(user!);

  @override
  Future<void> signOut() async => user = null;
}

class _Authority implements AuthoritySource {
  _Authority(this.answer);
  AuthorityRefresh answer;

  @override
  Future<AuthorityRefresh> refresh() async => answer;
}

/// What `ReferenceSync` does with a confirmed refresh, and nothing else: apply the purge
/// against the previous stored authority, then store the new one.
class _Reference implements ReferenceSynchroniser {
  _Reference(this.authority, this.purge, this.store);
  final _Authority authority;
  final ScopeCachePurge purge;
  final AuthorityStore store;

  @override
  Future<void> synchronise() async {
    final refresh = authority.answer;
    if (refresh is! AuthorityConfirmed) return;
    await purge.applyTo(
      refresh,
      previous: await store.loadFor(refresh.snapshot.userId),
    );
    await store.save(refresh.snapshot);
  }
}

/// An owner-snapshot source that can hold its answer.
class _HeldOwnerSource implements OwnerSnapshotSource {
  _HeldOwnerSource(this.answer);
  Map<String, dynamic> answer;
  Completer<void>? gate;
  final reached = StreamController<void>.broadcast();

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot() async {
    reached.add(null);
    if (gate case final waiting?) await waiting.future;
    return RemoteOk(answer);
  }
}

AuthoritySnapshot _authority(String user, List<CapabilityGrant> grants) =>
    AuthoritySnapshot(
      userId: user,
      orgId: 'test-org',
      resolvedAt: DateTime.utc(2026, 9, 19),
      grants: [const CapabilityGrant(Capability.mastersView), ...grants],
    );

final _ownerSettlementGrants = [
  ...pnlD2(),
  const CapabilityGrant(Capability.ownerSettlementView),
  const CapabilityGrant(Capability.ownerLedgerView),
];

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late File file;
  late AppDatabase db;
  late ReportingCache cache;
  late AuthorityStore store;
  late ScopeCachePurge purge;
  late _Auth auth;
  late _Authority authority;
  late ProviderContainer container;
  late NotifierProvider<SessionNotifier, SessionState> session;
  late FakeReportingGateway gateway;

  setUp(() async {
    file = await createTempDatabaseFile();
    db = AppDatabase(NativeDatabase(file));
    cache = ReportingCache(db);
    store = AuthorityStore(db);
    purge = ScopeCachePurge(db);
    auth = _Auth();
    authority = _Authority(
      AuthorityRefresh.confirmed(_authority(_a, _ownerSettlementGrants)),
    );
    session = NotifierProvider<SessionNotifier, SessionState>(
      () => SessionController(
        SessionDependencies(
          auth: auth,
          authority: authority,
          store: store,
          purge: purge,
          referenceSync: _Reference(authority, purge, store),
        ),
      ),
    );
    container = ProviderContainer();
    container.read(session);
    gateway = FakeReportingGateway()
      ..revenue.add(pnlSale(pnlCcr, '2026-06-10', gross: 1050000, tax: 50000))
      ..expense.add(pnlCost(pnlCcr, '2026-06-11', 400000));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  Future<void> signInAs(String user, List<CapabilityGrant> grants) async {
    auth.user = AuthenticatedUser(id: user, email: '$user@example.test');
    authority.answer = AuthorityRefresh.confirmed(_authority(user, grants));
    await container
        .read(session.notifier)
        .signIn(email: '$user@example.test', password: 'x');
    expect(container.read(session), isA<SessionReady>());
  }

  ReportingSync syncFor(String user) => ReportingSync(
    cache: cache,
    gateway: gateway,
    ownerUserId: user,
    orgId: 'test-org',
  );

  /// Starts a run whose server answer is held, and returns once the run is waiting on it —
  /// so the transition below provably happens while the result is on the wire.
  Future<Future<ReportingSyncReport>> startHeldRun(String user) async {
    gateway.revenue.add({
      ...pnlSale(pnlCcr, '2026-06-20', gross: 2100000, tax: 100000),
      'revenue_entry_id': _inflightEntry,
    });
    gateway.gate = Completer<void>();
    final asked = gateway.askedUnits.length;
    final run = syncFor(
      user,
    ).synchronise(businessUnitIds: {pnlCcr, pnlHki}, years: [_fy]);
    while (gateway.askedUnits.length == asked) {
      await Future<void>.delayed(Duration.zero);
    }
    return run;
  }

  Future<int> rowsOwnedBy(String user) async {
    var total = 0;
    for (final table in const [
      'reporting_revenue_contributions',
      'reporting_expense_contributions',
      'reporting_coverage_markers',
    ]) {
      final row = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM $table WHERE owner_user_id = ?',
            variables: [Variable<String>(user)],
          )
          .getSingle();
      total += row.data['c'] as int;
    }
    return total;
  }

  Future<bool> fileMentions(String text) async {
    // Checkpoint first so a write sitting in the WAL is on the main file as well; then
    // search every file SQLite might have put it in.
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final needle = utf8.encode(text);
    for (final path in [
      file.path,
      '${file.path}-wal',
      '${file.path}-journal',
    ]) {
      final f = File(path);
      if (!f.existsSync()) continue;
      final bytes = f.readAsBytesSync();
      for (var i = 0; i + needle.length <= bytes.length; i++) {
        var match = true;
        for (var j = 0; j < needle.length; j++) {
          if (bytes[i + j] != needle[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
    }
    return false;
  }

  Future<PnlOutcome> reportAs(String user, List<CapabilityGrant> grants) async {
    final engine = LocalReportingEngine(
      CachedReportingSource(
        cache: cache,
        principal: Principal(userId: user, grants: grants),
        coverage: await MarkerCoverage.load(cache, user),
      ),
    );
    return (await engine.report(
      ReportRequest(
        period: const MonthPeriod(2026, 6),
        scope: ReportingScope.unit(pnlCcr),
      ),
    )).outcome;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('sign-out while a reporting sync is on the wire', () {
    test('the held answer lands nothing for A, and B inherits nothing', () async {
      await signInAs(_a, _ownerSettlementGrants);
      final first = await syncFor(
        _a,
      ).synchronise(businessUnitIds: {pnlCcr, pnlHki}, years: [_fy]);
      expect(first.isComplete, isTrue);
      expect(await rowsOwnedBy(_a), greaterThan(0));

      final held = await startHeldRun(_a);

      await container.read(session.notifier).signOut();
      expect(container.read(session), isA<Unauthenticated>());
      expect(
        await rowsOwnedBy(_a),
        0,
        reason: 'sign-out purged A before the held answer arrived',
      );

      gateway.gate!.complete();
      final late = await held;

      // A — rows; B — markers and snapshot evidence.
      expect(
        await rowsOwnedBy(_a),
        0,
        reason:
            'a sync started for A applied its result after A signed out and the '
            'purge had run: A\'s contributions and coverage markers are back on a '
            'shared device (D-231)',
      );
      expect(await cache.markersFor(_a), isEmpty);
      expect(
        late.isComplete,
        isFalse,
        reason: 'a run that wrote nothing must not report itself as landed',
      );

      // D — the file itself.
      expect(
        await fileMentions(_inflightEntry),
        isFalse,
        reason:
            'the held sale was written to disk after sign-out, readable by anyone '
            'with the file even where no query would return it to B',
      );

      // C — what B can read, before and after B's own sync.
      await signInAs(_b, pnlD2(pnlCcr));
      expect(await cache.markersFor(_b), isEmpty);
      expect(await reportAs(_b, pnlD2(pnlCcr)), isA<PnlRefused>());
      expect(await rowsOwnedBy(_a), 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('a confirmed capability loss while a reporting sync is on the wire', () {
    for (final lost in const [
      Capability.reportsView,
      Capability.revenueView,
      Capability.expenseViewAll,
    ]) {
      test('losing ${lost.code} lands nothing afterwards', () async {
        await signInAs(_a, pnlD2());
        await syncFor(
          _a,
        ).synchronise(businessUnitIds: {pnlCcr, pnlHki}, years: [_fy]);
        expect(await rowsOwnedBy(_a), greaterThan(0));

        final held = await startHeldRun(_a);

        authority.answer = AuthorityRefresh.confirmed(
          _authority(_a, [
            for (final g in pnlD2())
              if (g.capability != lost) g,
          ]),
        );
        await container.read(session.notifier).refreshAuthority();
        expect(container.read(session), isA<SessionReady>());
        expect(
          await rowsOwnedBy(_a),
          0,
          reason: 'the confirmed loss purged the reporting cache first',
        );

        gateway.gate!.complete();
        await held;

        expect(
          await rowsOwnedBy(_a),
          0,
          reason:
              'a sync started under the old authority re-applied the purged '
              'reporting cache after ${lost.code} was confirmed lost (D-231)',
        );
        expect(await fileMentions(_inflightEntry), isFalse);
      });
    }

    test(
      'a network failure is not a revocation: the held run still lands',
      () async {
        await signInAs(_a, pnlD2());
        final held = await startHeldRun(_a);

        authority.answer = const AuthorityRefresh.unavailable(
          AuthorityUnavailableReason.offline,
        );
        await container.read(session.notifier).refreshAuthority();

        gateway.gate!.complete();
        final report = await held;
        expect(
          report.isComplete,
          isTrue,
          reason:
              'an authority refresh that could not reach the server changed nothing, '
              'so the run it did not interrupt must still apply',
        );
        expect(await rowsOwnedBy(_a), greaterThan(0));
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the owner-settlement sync on the wire', () {
    late _HeldOwnerSource source;

    Future<int> ownerRowsFor(String user) async {
      var total = 0;
      for (final table in const [
        'canonical_owner_movements',
        'canonical_owners',
        'canonical_ownership_shares',
        'owner_settlement_coverage',
      ]) {
        final row = await db
            .customSelect(
              'SELECT COUNT(*) AS c FROM $table WHERE owner_user_id = ?',
              variables: [Variable<String>(user)],
            )
            .getSingle();
        total += row.data['c'] as int;
      }
      return total;
    }

    OwnerSettlementSync ownerSyncFor(String user) =>
        OwnerSettlementSync(database: db, gateway: source, ownerUserId: user);

    Future<Future<OwnerSettlementSyncResult>> startHeldOwnerRun() async {
      source.answer = snapshot(
        movements: [movementJson(id: _inflightMovement)],
        snapshotId: 'snapshot-held',
      );
      source.gate = Completer<void>();
      final reached = source.reached.stream.first;
      final run = ownerSyncFor(_a).synchronise();
      await reached;
      return run;
    }

    setUp(() {
      source = _HeldOwnerSource(snapshot(snapshotId: 'snapshot-1'));
    });

    test('sign-out: the held owner history lands nothing', () async {
      await signInAs(_a, _ownerSettlementGrants);
      expect(
        await ownerSyncFor(_a).synchronise(),
        isA<OwnerSettlementSynchronised>(),
      );
      expect(await ownerRowsFor(_a), greaterThan(0));

      final held = await startHeldOwnerRun();
      await container.read(session.notifier).signOut();
      expect(await ownerRowsFor(_a), 0);

      source.gate!.complete();
      final result = await held;

      expect(
        await ownerRowsFor(_a),
        0,
        reason:
            'an owner-settlement sync started for A re-applied the owners, ratio and '
            'movements after A signed out (D-231)',
      );
      expect(result, isNot(isA<OwnerSettlementSynchronised>()));
      expect(await fileMentions(_inflightMovement), isFalse);

      await signInAs(_b, pnlD2(pnlCcr));
      expect(
        await OwnerSettlementRepository(
          db,
          principal: Principal(userId: _b, grants: _ownerSettlementGrants),
        ).coverage(),
        isNull,
      );
    });

    test(
      'losing owner_settlement.view: the held owner history lands nothing',
      () async {
        await signInAs(_a, _ownerSettlementGrants);
        await ownerSyncFor(_a).synchronise();
        expect(await ownerRowsFor(_a), greaterThan(0));

        final held = await startHeldOwnerRun();
        authority.answer = AuthorityRefresh.confirmed(
          _authority(_a, [
            for (final g in _ownerSettlementGrants)
              if (g.capability != Capability.ownerSettlementView) g,
          ]),
        );
        await container.read(session.notifier).refreshAuthority();
        expect(await ownerRowsFor(_a), 0);

        source.gate!.complete();
        await held;

        expect(
          await ownerRowsFor(_a),
          0,
          reason:
              'the owner cache purged for a confirmed loss of owner_settlement.view '
              'came back from a sync started before it (D-231)',
        );
      },
    );
  });
}
