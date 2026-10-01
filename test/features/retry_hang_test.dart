/// Phase 8 Slice 3 — a one-shot action never looks frozen while what it awaits retries.
///
/// What Riverpod 3.4.2 does, pinned here because every rule below depends on it: a failed
/// provider is retried up to ten times, 200 ms doubling to 6.4 s, and a `.future` awaited
/// meanwhile stays pending throughout — about 38 seconds. The retry re-runs a provider only
/// while something watches it, so a `.future` read once by an action on a provider nothing
/// watches never settles at all. An `Error` (as opposed to an `Exception`) is not retried.
///
/// Before this slice a refresh awaited two such providers before it said it was running:
/// with a screen watching, the status stayed idle for 38 to 76 seconds and then the refresh
/// threw; with nothing watching, it never settled. These tests hold the corrected
/// behaviour: the action is visibly running before it awaits anything, reads its inputs
/// once, publishes a plain failure at once, never stays running, publishes nothing for a
/// person or authority that has since changed, and is retried by the person — explicitly.
///
/// Time is the test's fake clock, advanced in 100 ms steps; "at once" means within one.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/master_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/export/export_providers.dart';
import 'package:krishna_mis/features/owner_settlement/presentation/owner_settlement_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_presentation.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:meta/meta.dart' show isTest;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/test_session.dart';

const _ccr = 'unit-ccr';

final class _LocalReadFailure implements Exception {
  const _LocalReadFailure();
}

/// The real repository over a real database, with a switch to make a read fail the way a
/// damaged local database does, a gate to hold a read open, and a count of reads.
class _Masters extends MasterRepository {
  _Masters(super.db);

  bool failGraph = false;
  bool failRules = false;
  Completer<void>? graphGate;
  int graphReads = 0;
  int ruleReads = 0;

  @override
  Future<MasterGraph> loadGraph() async {
    graphReads++;
    if (graphGate case final gate?) await gate.future;
    if (failGraph) throw const _LocalReadFailure();
    return super.loadGraph();
  }

  @override
  Future<Map<String, BusinessDayRule>> businessDayRules() async {
    ruleReads++;
    if (failRules) throw const _LocalReadFailure();
    return super.businessDayRules();
  }
}

SupabaseClient _client() => SupabaseClient(
  'http://localhost',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

/// Answers a synchronisation with nothing new, and counts what it was asked.
final class _Gateway extends ReportingGateway {
  _Gateway() : super(_client());

  int snapshots = 0;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
    List<int> financialYears = const [],
    ReportingPageCursor after = const ReportingPageCursor.start(),
    int pageDocuments = ReportingPageCursor.defaultPageDocuments,
  }) async {
    snapshots++;
    return RemoteOk({
      'snapshot_id': 'snapshot-$snapshots',
      'server_time': DateTime.utc(2026, 9, 19, 8).toIso8601String(),
      'units': [
        for (final unit in businessUnitIds)
          {'business_unit_id': unit, 'reporting_authorised': true},
      ],
      'revenue': <Map<String, dynamic>>[],
      'expense': <Map<String, dynamic>>[],
    });
  }

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> newerThan({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) async => RemoteOk({
    'server_time': DateTime.utc(2026, 9, 19, 8).toIso8601String(),
    'revenue_newer': false,
    'expense_newer': false,
  });
}

class _Session extends StubSession {
  _Session(super.initial);
  void become(SessionState next) => state = next;
}

AuthoritySnapshot _authority(
  String userId, {
  Iterable<Capability> capabilities = RoleTemplates.owner,
}) => AuthoritySnapshot(
  userId: userId,
  orgId: 'test-org',
  resolvedAt: DateTime.utc(2026, 9, 19),
  grants: [for (final c in capabilities) CapabilityGrant(c)],
);

/// Advances the fake clock until [done]; the time it took, or null after [limit].
Future<Duration?> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 120),
}) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed <= limit) {
    if (done()) return elapsed;
    await tester.pump(step);
    elapsed += step;
  }
  return null;
}

const _atOnce = Duration(milliseconds: 100);

/// Containers a test made, disposed inside the test body: a provider still waiting on a
/// retry timer would otherwise outlive the body, and the binding refuses pending timers.
final _live = <ProviderContainer>[];

ProviderContainer _track(ProviderContainer c) {
  _live.add(c);
  return c;
}

@isTest
void _test(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        for (final c in _live.reversed) {
          c.dispose();
        }
        _live.clear();
        await tester.pump();
      }
    });

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  Future<AppDatabase> seeded(WidgetTester tester) async {
    final db = (await tester.runAsync(() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES ('$_ccr', 'test-org', 'CCR', 'Crystal Canopy Rooftop', 'hotel', "
        "'Asia/Kolkata', '05:00', 1, 1, '2026-06-01T00:00:00.000Z')",
      );
      return db;
    }))!;
    addTearDown(() => tester.runAsync(db.close));
    return db;
  }

  ProviderContainer containerFor(
    AppDatabase db,
    _Masters masters, {
    _Session? session,
    _Gateway? gateway,
  }) {
    final c = _track(
      ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          masterRepositoryProvider.overrideWithValue(masters),
          sessionProvider.overrideWith(
            () =>
                session ?? _Session(readySession(authority: _authority('me'))),
          ),
          reportingClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 9, 19, 9),
          ),
          reportingGatewayProvider.overrideWithValue(gateway ?? _Gateway()),
          ownerLedgerGatewayProvider.overrideWithValue(
            OwnerLedgerGateway(_client()),
          ),
        ],
      ),
    );
    return c;
  }

  /// Starts [action] and records whether it threw.
  ({bool Function() done, Object? Function() error}) start(
    Future<void> action,
  ) {
    var done = false;
    Object? error;
    action.then<void>(
      (_) => done = true,
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    return (done: () => done, error: () => error);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('Riverpod 3.4.2, as this project relies on it', () {
    _test('an Exception is retried ten times, ~38 s, only while watched', (
      tester,
    ) async {
      var builds = 0;
      final failing = FutureProvider<int>((ref) async {
        builds++;
        throw const _LocalReadFailure();
      });

      final watched = _track(ProviderContainer());
      final sub = watched.listen(failing, (_, _) {});
      final w = start(watched.read(failing.future));
      final took = await _until(tester, w.done);
      expect(took, const Duration(milliseconds: 38200));
      expect(builds, 11);
      sub.close();

      builds = 0;
      final unwatched = _track(ProviderContainer());
      final u = start(unwatched.read(failing.future));
      expect(await _until(tester, u.done), isNull, reason: 'never settles');
      expect(builds, 1);
    });

    _test('an Error is not retried', (tester) async {
      var builds = 0;
      final failing = FutureProvider<int>((ref) async {
        builds++;
        throw StateError('broken');
      });
      final c = _track(ProviderContainer());
      final r = start(c.read(failing.future));
      expect(await _until(tester, r.done), lessThanOrEqualTo(_atOnce));
      expect(builds, 1);
    });

    _test('noAutomaticRetry answers at the first failure, watched or not', (
      tester,
    ) async {
      var builds = 0;
      final once = FutureProvider<int>((ref) async {
        builds++;
        throw const _LocalReadFailure();
      }, retry: noAutomaticRetry);
      final c = _track(ProviderContainer());
      final r = start(c.read(once.future));
      expect(await _until(tester, r.done), lessThanOrEqualTo(_atOnce));
      final sub = c.listen(once, (_, _) {});
      await _until(tester, () => false, limit: const Duration(seconds: 40));
      expect(builds, 1, reason: 'no background retry either');
      sub.close();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('a refresh is visibly running before it awaits anything', () {
    _test('P&L', (tester) async {
      final db = await seeded(tester);
      final masters = _Masters(db)..graphGate = Completer<void>();
      final c = containerFor(db, masters);
      expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.idle);
      final r = start(c.read(pnlSyncProvider.notifier).refresh());
      // No pump: the status is running in the same turn the tap started it.
      expect(c.read(pnlSyncProvider).isRunning, isTrue);
      expect(
        pnlSyncNotice(c.read(pnlSyncProvider))?.key,
        const Key('pnl-refreshing'),
      );
      // A second tap while it prepares does not start a second run.
      await c.read(pnlSyncProvider.notifier).refresh();
      masters.graphGate!.complete();
      await _until(tester, r.done);
      expect(masters.graphReads, 1);
    });

    _test('dashboard', (tester) async {
      final db = await seeded(tester);
      final masters = _Masters(db)..graphGate = Completer<void>();
      final c = containerFor(db, masters);
      final r = start(c.read(dashboardSyncProvider.notifier).refresh());
      expect(c.read(dashboardSyncProvider).isRunning, isTrue);
      await c.read(dashboardSyncProvider.notifier).refresh();
      masters.graphGate!.complete();
      await _until(tester, r.done);
      expect(masters.graphReads, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('an input that cannot be read fails the refresh at once', () {
    for (final watched in [false, true]) {
      final w = watched ? 'a screen watching' : 'nothing watching';

      _test('P&L, master hierarchy unreadable, $w', (tester) async {
        final db = await seeded(tester);
        final masters = _Masters(db)..failGraph = true;
        final c = containerFor(db, masters);
        if (watched) c.listen(pnlViewProvider, (_, _) {});
        await _until(tester, () => false, limit: const Duration(seconds: 1));
        final reads = masters.graphReads;
        final r = start(c.read(pnlSyncProvider.notifier).refresh());
        expect(await _until(tester, r.done), lessThanOrEqualTo(_atOnce));
        expect(
          r.error(),
          isNull,
          reason: 'the failure is a status, not a throw',
        );
        final status = c.read(pnlSyncProvider);
        expect(status.phase, PnlSyncPhase.failed);
        expect(status.localFailure, isTrue);
        expect(status.isRunning, isFalse);
        expect(
          masters.graphReads - reads,
          watched ? greaterThanOrEqualTo(1) : 1,
          reason: 'read once by the refresh itself',
        );
      });

      _test('P&L, business-day rules unreadable, $w', (tester) async {
        final db = await seeded(tester);
        final masters = _Masters(db)..failRules = true;
        final c = containerFor(db, masters);
        if (watched) c.listen(pnlViewProvider, (_, _) {});
        final r = start(c.read(pnlSyncProvider.notifier).refresh());
        expect(await _until(tester, r.done), lessThanOrEqualTo(_atOnce));
        expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.failed);
        expect(c.read(pnlSyncProvider).localFailure, isTrue);
      });

      _test('dashboard, master hierarchy unreadable, $w', (tester) async {
        final db = await seeded(tester);
        final masters = _Masters(db)..failGraph = true;
        final c = containerFor(db, masters);
        if (watched) c.listen(dashboardViewProvider, (_, _) {});
        final r = start(c.read(dashboardSyncProvider.notifier).refresh());
        expect(await _until(tester, r.done), lessThanOrEqualTo(_atOnce));
        expect(r.error(), isNull);
        expect(c.read(dashboardSyncProvider).phase, DashboardSyncPhase.failed);
        expect(c.read(dashboardSyncProvider).localFailure, isTrue);
      });

      _test('owner settlement, master hierarchy unreadable, $w', (
        tester,
      ) async {
        final db = await seeded(tester);
        final masters = _Masters(db)..failGraph = true;
        final c = containerFor(db, masters);
        if (watched) c.listen(ownerSettlementPreviewProvider, (_, _) {});
        final r = start(c.read(ownerSettlementSyncProvider.notifier).refresh());
        expect(await _until(tester, r.done), lessThanOrEqualTo(_atOnce));
        expect(r.error(), isNull);
        final status = c.read(ownerSettlementSyncProvider);
        expect(status.phase, OwnerSettlementSyncPhase.failed);
        expect(status.localFailure, isTrue);
      });
    }

    _test('a failure after the run started is never left running', (
      tester,
    ) async {
      final db = await seeded(tester);
      // The coverage table a refresh consults is gone: a damaged local database.
      await tester.runAsync(
        () => db.customStatement('DROP TABLE reporting_coverage_markers'),
      );
      final c = containerFor(db, _Masters(db));
      final r = start(c.read(pnlSyncProvider.notifier).refresh());
      expect(await _until(tester, r.done), lessThanOrEqualTo(_atOnce));
      expect(r.error(), isNull);
      expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.failed);
      expect(c.read(pnlSyncProvider).localFailure, isTrue);

      // And the next tap runs, rather than being ignored as "already running".
      final again = start(c.read(pnlSyncProvider.notifier).refresh());
      expect(c.read(pnlSyncProvider).isRunning, isTrue);
      await _until(tester, again.done);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the failure reads plainly, and the person retries it', () {
    _test('the wording names this device, offers retry, and no internals', (
      tester,
    ) async {
      final db = await seeded(tester);
      final masters = _Masters(db)..failGraph = true;
      final c = containerFor(db, masters);
      final r = start(c.read(pnlSyncProvider.notifier).refresh());
      await _until(tester, r.done);
      final notice = pnlSyncNotice(c.read(pnlSyncProvider))!;
      expect(notice.key, const Key('pnl-sync-local-failure-notice'));
      for (final text in [notice.text, pnlLocalFailureText]) {
        expect(text.toLowerCase(), contains('this device'));
        expect(text.toLowerCase(), contains('try again'));
        for (final internal in [
          'Exception',
          'Sqlite',
          'Provider',
          'Riverpod',
          'Supabase',
          '_LocalReadFailure',
        ]) {
          expect(text, isNot(contains(internal)));
        }
      }

      final d = start(c.read(dashboardSyncProvider.notifier).refresh());
      await _until(tester, d.done);
      final dashboard = dashboardNoticeFor(c.read(dashboardSyncProvider))!;
      expect(dashboard.key, const Key('dashboard-sync-local-failure-notice'));
      expect(dashboardLocalFailureText, isNot(contains('Exception')));
    });

    _test('a refresh after the input is readable again succeeds', (
      tester,
    ) async {
      final db = await seeded(tester);
      final masters = _Masters(db)..failGraph = true;
      final gateway = _Gateway();
      final c = containerFor(db, masters, gateway: gateway);
      final first = start(c.read(pnlSyncProvider.notifier).refresh());
      await _until(tester, first.done);
      expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.failed);
      expect(gateway.snapshots, 0, reason: 'nothing was asked of the server');

      masters.failGraph = false;
      final second = start(c.read(pnlSyncProvider.notifier).refresh());
      expect(c.read(pnlSyncProvider).isRunning, isTrue);
      await tester.runAsync(() async {
        while (!second.done()) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
      expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.succeeded);
      expect(c.read(pnlSyncProvider).localFailure, isFalse);
      expect(gateway.snapshots, greaterThan(0));
    });

    _test('Try again reaches the failed input, not just the report', (
      tester,
    ) async {
      final db = await seeded(tester);
      final masters = _Masters(db)..failRules = true;
      final c = containerFor(db, masters);
      c.listen(pnlViewProvider, (_, _) {});
      expect(
        await _until(tester, () => c.read(pnlViewProvider).hasError),
        lessThanOrEqualTo(_atOnce),
        reason: 'the report says it could not be read at once, not after 38 s',
      );

      masters.failRules = false;
      // The report alone, re-read: it meets the rules' stored failure again.
      c.invalidate(pnlViewProvider);
      await _until(tester, () => false, limit: const Duration(seconds: 1));
      expect(c.read(pnlViewProvider).value, isNull);

      // Try again as the surfaces do it.
      retryFailedReportInputs(c.exists, c.read, c.invalidate);
      c.invalidate(pnlViewProvider);
      await tester.runAsync(() async {
        for (var i = 0; i < 200 && !c.read(pnlViewProvider).hasValue; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      expect(c.read(pnlViewProvider).value, isA<PnlReportView>());
    });

    _test('an input never read is left unread by Try again', (tester) async {
      final db = await seeded(tester);
      final masters = _Masters(db);
      final c = containerFor(db, masters);
      retryFailedReportInputs(c.exists, c.read, c.invalidate);
      expect(masters.graphReads, 0);
      expect(masters.ruleReads, 0);
      expect(c.exists(localReportingSourceProvider), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('nothing is published for a person or authority that changed', () {
    _test('P&L: the person changes while the inputs are read', (tester) async {
      final db = await seeded(tester);
      final masters = _Masters(db)
        ..graphGate = Completer<void>()
        ..failGraph = true;
      final session = _Session(readySession(authority: _authority('alice')));
      final c = containerFor(db, masters, session: session);
      c.listen(pnlSyncProvider, (_, _) {});
      final r = start(c.read(pnlSyncProvider.notifier).refresh());
      expect(c.read(pnlSyncProvider).isRunning, isTrue);

      session.become(readySession(authority: _authority('bob')));
      await tester.pump();
      expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.idle);

      masters.graphGate!.complete();
      await _until(tester, r.done);
      expect(
        c.read(pnlSyncProvider).phase,
        PnlSyncPhase.idle,
        reason: "alice's failure is not bob's status",
      );
    });

    _test('P&L: a stale run that succeeds asks nothing for the next person', (
      tester,
    ) async {
      final db = await seeded(tester);
      final masters = _Masters(db)..graphGate = Completer<void>();
      final gateway = _Gateway();
      final session = _Session(readySession(authority: _authority('alice')));
      final c = containerFor(db, masters, session: session, gateway: gateway);
      c.listen(pnlSyncProvider, (_, _) {});
      final r = start(c.read(pnlSyncProvider.notifier).refresh());
      session.become(readySession(authority: _authority('bob')));
      await tester.pump();
      masters.graphGate!.complete();
      await tester.runAsync(() async {
        while (!r.done()) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      expect(gateway.snapshots, 0);
      expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.idle);
    });

    _test('dashboard: a capability change while the inputs are read', (
      tester,
    ) async {
      final db = await seeded(tester);
      final masters = _Masters(db)
        ..graphGate = Completer<void>()
        ..failGraph = true;
      final session = _Session(readySession(authority: _authority('alice')));
      final c = containerFor(db, masters, session: session);
      c.listen(dashboardSyncProvider, (_, _) {});
      final r = start(c.read(dashboardSyncProvider.notifier).refresh());
      expect(c.read(dashboardSyncProvider).isRunning, isTrue);

      // The same person, no longer holding unscoped reporting authority.
      session.become(
        readySession(
          authority: _authority(
            'alice',
            capabilities: RoleTemplates.owner.where(
              (c) => c != Capability.expenseViewAll,
            ),
          ),
        ),
      );
      await tester.pump();
      // Read now, so the rebuild for the new authority has happened before the old run
      // settles: a later read would otherwise overwrite a stale write and hide it.
      expect(c.read(dashboardSyncProvider).phase, DashboardSyncPhase.idle);
      masters.graphGate!.complete();
      await _until(tester, r.done);
      expect(c.read(dashboardSyncProvider).phase, DashboardSyncPhase.idle);
    });

    _test('owner settlement: the person changes while the inputs are read', (
      tester,
    ) async {
      final db = await seeded(tester);
      final masters = _Masters(db)
        ..graphGate = Completer<void>()
        ..failGraph = true;
      final session = _Session(readySession(authority: _authority('alice')));
      final c = containerFor(db, masters, session: session);
      c.listen(ownerSettlementSyncProvider, (_, _) {});
      final r = start(c.read(ownerSettlementSyncProvider.notifier).refresh());
      session.become(readySession(authority: _authority('bob')));
      await tester.pump();
      expect(
        c.read(ownerSettlementSyncProvider).phase,
        OwnerSettlementSyncPhase.idle,
      );
      masters.graphGate!.complete();
      await _until(tester, r.done);
      expect(
        c.read(ownerSettlementSyncProvider).phase,
        OwnerSettlementSyncPhase.idle,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group(
    'a report with nothing to fetch leaves the status exactly as it was',
    () {
      _test('the same object, so the D-248 diagnostic still tells them apart', (
        tester,
      ) async {
        final db = await seeded(tester);
        // Holds no reporting capability: nothing this person may read.
        final c = containerFor(
          db,
          _Masters(db),
          session: _Session(
            readySession(
              authority: _authority(
                'me',
                capabilities: const [Capability.mastersView],
              ),
            ),
          ),
        );
        final before = c.read(pnlSyncProvider);
        final r = start(c.read(pnlSyncProvider.notifier).refresh());
        await _until(tester, r.done);
        expect(identical(c.read(pnlSyncProvider), before), isTrue);
      });
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════
  group('providers that answer once', () {
    _test('the cache lock is not held while the report source fails', (
      tester,
    ) async {
      final db = await seeded(tester);
      await tester.runAsync(
        () => db.customStatement('DROP TABLE reporting_coverage_markers'),
      );
      final c = containerFor(db, _Masters(db));
      c.listen(pnlViewProvider, (_, _) {});
      await tester.pump();
      var released = false;
      unawaited(
        c.read(canonicalCacheLockProvider).run(() async {}).then((_) {
          released = true;
        }),
      );
      expect(
        await _until(tester, () => released),
        lessThanOrEqualTo(_atOnce),
        reason:
            'was 76 s: the source and the engine each retried under the lock',
      );
      expect(c.read(pnlViewProvider).hasError, isTrue);
    });

    _test('the export fonts answer at the first failure', (tester) async {
      var loads = 0;
      final c = _track(
        ProviderContainer(
          overrides: [
            exportPdfFontsProvider.overrideWith((ref) async {
              loads++;
              throw const _LocalReadFailure();
            }),
          ],
        ),
      );
      Object? failure;
      unawaited(
        c
            .read(exportPdfFontsProvider.future)
            .then<ExportPdfFonts?>(
              (f) => f,
              onError: (Object e) {
                failure = e;
                return null;
              },
            ),
      );
      expect(
        await _until(tester, () => failure != null),
        lessThanOrEqualTo(_atOnce),
      );
      expect(loads, 1);
    });

    test('each of them declares it', () {
      for (final provider in <FutureProvider<Object?>>[
        businessDayRulesProvider,
        pnlScopeOptionsProvider,
        localReportingSourceProvider,
        localReportingEngineProvider,
        reportingDrilldownSourceProvider,
        dashboardEngineProvider,
        exportPdfFontsProvider,
      ]) {
        expect(provider.retry, same(noAutomaticRetry), reason: '$provider');
      }
      // Kept on purpose: the entry forms and Masters screens recover on their own.
      expect(masterGraphProvider.retry, isNull);
    });
  });
}
