/// The Phase 2 client↔server acceptance, executed against the real `krishna-mis-dev`
/// project through the actual gateway layer.
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` run stays hermetic and offline. Nothing here prints a password,
/// a token or the API key.
///
/// The D-048 revocation flow needs an administrative act in the middle — the Owner taking
/// a property away from the Manager — which this Manager session by definition cannot
/// perform on itself. So the run is split into phases against one persistent local
/// database, and the revocation happens between them:
///
///   phase-a  sign in, sync, cache Crystal Canopy, queue a privileged mutation
///   …        (Owner revokes the Crystal Canopy scope)
///   phase-b  sync again, purge, attempt the queued mutation, expect a refusal
///   …        (Owner restores the scope)
///   phase-c  sync again, confirm the data returns with no duplicates
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/authority_gateway.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/data/remote/vendor_tax_period_gateways.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/data/sync/revenue_mutation_endpoint.dart';
import 'package:krishna_mis/data/sync/sync_engine.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/data/sync/reference_sync.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';
const _phaseVar = 'KRISHNA_TEST_PHASE';
const _dbVar = 'KRISHNA_TEST_DB';

String _seedId(String path) =>
    const Uuid().v5('d9d3f0a6-4c2b-5f7e-9a10-6b1e2c8f4a70', path);

void main() {
  final identitiesPath = Platform.environment[_identitiesVar];
  if (identitiesPath == null || !File(identitiesPath).existsSync()) {
    // Not a failure: the live suite is opt-in, and a developer without the development
    // project should still get a green `flutter test`.
    return;
  }

  final config =
      jsonDecode(File(r'config/dev.json').readAsStringSync())
          as Map<String, dynamic>;
  final identities =
      jsonDecode(File(identitiesPath).readAsStringSync())
          as Map<String, dynamic>;
  final phase = Platform.environment[_phaseVar] ?? 'all';
  final dbPath = Platform.environment[_dbVar] ?? 'build/live_test.sqlite';

  // A real UUID, because the server stores mutation ids as `uuid`. Fixed rather than
  // random so the three phases refer to the same queued intent.
  const liveMutationId = '3f2a91c4-5d6e-4b8a-9c1f-0a7e5d3b6c28';
  final ccr = _seedId('bu:CCR');
  final hki = _seedId('bu:HKI');
  final kirana = _seedId('cat:CCR/FB/FOOD_PROD/KIRANA');

  late SupabaseClient client;
  late AppDatabase db;
  late AuthorityGateway authority;
  late MasterGateway masters;
  late ReferenceSync sync;
  late OutboxRepository outbox;

  Future<void> signInAs(String email) async {
    final entry = identities[email] as Map<String, dynamic>;
    await client.auth.signInWithPassword(
      email: email,
      password: entry['password'] as String,
    );
  }

  setUpAll(() async {
    client = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
    File(dbPath).parent.createSync(recursive: true);
    db = AppDatabase(NativeDatabase(File(dbPath)));
    authority = AuthorityGateway(client);
    masters = MasterGateway(client);
    outbox = OutboxRepository(db);
    sync = ReferenceSync(
      db: db,
      authorityGateway: authority,
      masterGateway: masters,
    );
  });

  tearDownAll(() async {
    await client.auth.signOut();
    await db.close();
    await client.dispose();
  });

  group('phase-a · authorised, cached, queued', skip: phase != 'phase-a', () {
    test('the Manager signs in and the server states their scope', () async {
      await signInAs('ccr.manager@example.com');
      final refresh = await authority.refresh();

      expect(refresh, isA<AuthorityConfirmed>());
      final snapshot = (refresh as AuthorityConfirmed).snapshot;
      expect(snapshot.scopedUnits, {ccr});
      expect(snapshot.holdsOrgWideGrant, isFalse);
      expect(snapshot.resolvedAt.isUtc, isTrue);
    });

    test('the pull returns Crystal Canopy alone, because RLS decided so', () async {
      await signInAs('ccr.manager@example.com');
      final pull = await masters.pullAll();

      expect(pull.isOk, isTrue);
      final snapshot = pull.valueOrNull!;
      expect(snapshot.unitIds, {ccr});
      expect(snapshot.departments, hasLength(4));
      // Was `isEmpty` under D-043, and correct while nothing was configured. Phase 4
      // Slice 4 installed the four verified rules (D-096), so "empty" stopped being the
      // truth — and this suite was carried forward rather than re-run, which is how a
      // stale assertion survived a checkpoint. Restated as the stronger claim it should
      // always have been: the manager receives their own property's rules and no other
      // property's, decided by RLS rather than by the client asking narrowly.
      final categories = {
        for (final r in snapshot.taxRules)
          if (r['archived_at'] == null) r['revenue_category_id'] as String,
      };
      expect(
        categories,
        isNotEmpty,
        reason: 'the verified baseline is configured (D-096)',
      );
      final crystalCanopyCategories = {
        for (final c in snapshot.revenueCategories)
          if (c['business_unit_id'] == ccr) c['id'] as String,
      };
      expect(
        categories.difference(crystalCanopyCategories),
        isEmpty,
        reason:
            'a Crystal Canopy manager must not receive Hotel Krishna tax rules — a rate '
            'is configuration about a property they cannot see',
      );
    });

    test('synchronising writes it into the local read model', () async {
      await signInAs('ccr.manager@example.com');
      final report = await sync.synchronise();

      expect(report.authorityConfirmed, isTrue);
      expect(report.rowsWritten, greaterThan(0));
      expect(report.freshness, AuthorityFreshness.confirmed);

      final units = await db.select(db.businessUnits).get();
      expect(units.map((u) => u.id), [ccr]);
      final departments = await db.select(db.departments).get();
      expect(departments, hasLength(4));
    });

    test(
      'a privileged mutation is queued and is not claimed as accepted',
      () async {
        await outbox.enqueue(
          PendingMutation(
            mutationId: liveMutationId,
            entityType: 'expense_category',
            entityId: kirana,
            op: MutationOp.update,
            payload: const {'name': 'Queued While Authorised'},
            baseRowVersion: 1,
            createdAt: DateTime.now().toUtc(),
          ),
          now: DateTime.now().toUtc(),
        );

        final status = await outbox.statusOf(liveMutationId);
        expect(status, OutboxStatus.pending);
        expect(
          status!.userVisibleState,
          SyncState.pendingSync,
          reason:
              'queued is not synced, and must never be shown as though it were',
        );
      },
    );
  });

  group('phase-b · scope revoked while offline', skip: phase != 'phase-b', () {
    test('the refresh confirms the scope is gone', () async {
      await signInAs('ccr.manager@example.com');
      final refresh = await authority.refresh();

      expect(refresh, isA<AuthorityConfirmed>());
      expect((refresh as AuthorityConfirmed).snapshot.scopedUnits, isEmpty);
    });

    test('synchronising purges Crystal Canopy and keeps the queue', () async {
      await signInAs('ccr.manager@example.com');
      final report = await sync.synchronise();

      expect(report.authorityConfirmed, isTrue);
      expect(report.purge?.didPurge, isTrue);
      expect(report.purge?.revokedUnits, {ccr});

      expect(await db.select(db.businessUnits).get(), isEmpty);
      expect(await db.select(db.departments).get(), isEmpty);
      expect(await db.select(db.expenseCategories).get(), isEmpty);

      final queued = await db.select(db.syncOutbox).get();
      expect(queued, hasLength(1));
      expect(queued.single.mutationId, liveMutationId);
    });

    test(
      'the queued mutation is refused by the server on current authority',
      () async {
        await signInAs('ccr.manager@example.com');
        final outcome = await masters.rename(
          entityType: 'expense_category',
          entityId: kirana,
          newName: 'Queued While Authorised',
          baseRowVersion: 1,
          mutationId: liveMutationId,
        );

        expect(
          outcome.isRefused,
          isTrue,
          reason: 'authority at delivery time wins',
        );
        final refusal = outcome.refusalOrNull!;
        expect(refusal.kind.isAuthorityRefusal, isTrue);
        expect(refusal.kind.isAutomaticallyRetryable, isFalse);
      },
    );

    test(
      'the client records it as Rejected, not Conflict, and keeps it',
      () async {
        await outbox.updateStatus(
          liveMutationId,
          status: OutboxStatus.rejected,
          lastError: 'You do not have permission to do this.',
        );

        final status = await outbox.statusOf(liveMutationId);
        expect(status, OutboxStatus.rejected);
        expect(status!.userVisibleState, SyncState.rejected);
        expect(status.isAutomaticallyRetryable, isFalse);
        expect(SyncState.rejected.isOnServer, isFalse);

        final rows = await db.select(db.syncOutbox).get();
        expect(rows, hasLength(1), reason: 'the attempt stays inspectable');
        expect(rows.single.payload, contains('Queued While Authorised'));
      },
    );

    test(
      'the vendor list survives, because a supplier is company data (D-049)',
      () async {
        await signInAs('ccr.manager@example.com');
        final pull = await masters.pullAll();
        expect(pull.isOk, isTrue);
        // Vendors remain readable organisation-wide even with no unit scope at all.
        expect(pull.valueOrNull!.unitIds, isEmpty);
      },
    );
  });

  group('phase-c · scope restored', skip: phase != 'phase-c', () {
    test('the data returns, with no duplicates', () async {
      await signInAs('ccr.manager@example.com');
      final report = await sync.synchronise();

      expect(report.authorityConfirmed, isTrue);
      expect(report.purge?.didPurge, isFalse);

      final units = await db.select(db.businessUnits).get();
      expect(units, hasLength(1));
      expect(units.single.id, ccr);

      final departments = await db.select(db.departments).get();
      expect(departments, hasLength(4), reason: 'restored once, not twice');
      expect(departments.map((d) => d.id).toSet(), hasLength(4));
    });

    test('the previously rejected attempt is not resurrected', () async {
      final status = await outbox.statusOf(liveMutationId);
      expect(
        status,
        OutboxStatus.rejected,
        reason:
            'authority returning does not re-assert an intent the server refused',
      );
    });
  });

  group(
    'multi-scope · both properties cached',
    skip: phase != 'multi-scope-a',
    () {
      test('both properties are cached while both are granted', () async {
        await signInAs('ccr.manager@example.com');
        final report = await sync.synchronise();

        expect(report.authorityConfirmed, isTrue);
        final units = await db.select(db.businessUnits).get();
        expect(units.map((u) => u.id).toSet(), {ccr, hki});

        final departments = await db.select(db.departments).get();
        expect(
          departments,
          hasLength(10),
          reason: '4 Crystal Canopy + 6 Hotel Krishna',
        );
      });
    },
  );

  group(
    'multi-scope · one property revoked',
    skip: phase != 'multi-scope-b',
    () {
      test('losing Crystal Canopy leaves Hotel Krishna untouched', () async {
        await signInAs('ccr.manager@example.com');
        final report = await sync.synchronise();

        expect(report.purge?.didPurge, isTrue);
        expect(report.purge?.revokedUnits, {ccr});

        final units = await db.select(db.businessUnits).get();
        expect(units.map((u) => u.id), [
          hki,
        ], reason: 'only the revoked unit goes');

        final departments = await db.select(db.departments).get();
        expect(departments, hasLength(6));
        expect(departments.every((d) => d.businessUnitId == hki), isTrue);

        final revenue = await db.select(db.revenueCategories).get();
        expect(revenue.map((r) => r.code).toSet(), {'ROOM', 'BANQUET'});
      });

      test(
        'organisation-global data and the queue are both retained',
        () async {
          final methods = await db.select(db.paymentMethods).get();
          expect(
            methods,
            hasLength(5),
            reason: 'payment methods belong to the company',
          );

          final queued = await db.select(db.syncOutbox).get();
          expect(
            queued,
            hasLength(1),
            reason: 'the outbox is never touched by a purge',
          );
        },
      );
    },
  );

  group('conflict and idempotency, live', skip: phase != 'conflict', () {
    test('the same mutation id replays rather than reapplying', () async {
      await signInAs('ccr.manager@example.com');
      final mutationId = const Uuid().v4();

      final first = await masters.rename(
        entityType: 'department',
        entityId: _seedId('dept:CCR/FB'),
        newName: 'F&B / Kitchen',
        baseRowVersion: 1,
        mutationId: mutationId,
      );
      final second = await masters.rename(
        entityType: 'department',
        entityId: _seedId('dept:CCR/FB'),
        newName: 'F&B / Kitchen',
        baseRowVersion: 1,
        mutationId: mutationId,
      );

      // A Manager holds no masters.manage, so both are refused identically — which is
      // itself the point: the refusal is stable and the second delivery changes nothing.
      expect(first.isRefused, second.isRefused);
      if (first.isOk) {
        expect(second.valueOrNull!['status'], 'replayed');
        expect(
          second.valueOrNull!['row_version'],
          first.valueOrNull!['row_version'],
        );
      }
    });

    test(
      'a refusal carries a code the client can act on, not raw SQL',
      () async {
        await signInAs('data.entry@example.com');
        final outcome = await masters.archive(
          entityType: 'section',
          entityId: _seedId('sec:CCR/FB/FOOD_PROD'),
          baseRowVersion: 1,
        );

        expect(outcome.isRefused, isTrue);
        final refusal = outcome.refusalOrNull!;
        expect(refusal.kind, RefusalKind.missingCapability);
        expect(refusal.message, 'You do not have permission to do this.');
        expect(
          refusal.message,
          isNot(contains('SQLSTATE')),
          reason: 'a manager never sees a Postgres error',
        );
      },
    );

    test('period state is readable and reports the truth', () async {
      await signInAs('ccr.manager@example.com');
      final gateway = PeriodGateway(client);
      final state = await gateway.state(
        periodKey: '2026-06',
        businessUnitId: ccr,
      );
      expect(state.isOk, isTrue);
      expect(state.valueOrNull, anyOf('open', 'closed'));
    });

    test('a Manager cannot close a period', () async {
      await signInAs('ccr.manager@example.com');
      final gateway = PeriodGateway(client);
      final outcome = await gateway.close(
        periodKey: '2026-07',
        businessUnitId: hki,
      );
      expect(outcome.isRefused, isTrue);
      expect(outcome.refusalOrNull!.kind, RefusalKind.missingCapability);
    });
  });

  // Every migration the server has applied must exist as a file in this repository.
  //
  // It did not. `my_authority()` — the single call the whole authorisation model depends
  // on — was applied to the development project and never committed, so for a day the
  // repository could not have produced a working staging or production environment. The
  // repository is the source of project state (CLAUDE.md §1), and "the server has
  // something we do not" is exactly the kind of drift that is invisible until a deploy.
  // ── Revenue configuration synchronisation, against the real project (Slice 6) ──
  //
  // Three phases on one persistent database, because the interesting claim is not that a
  // request succeeded — it is that the device is still correct after the network goes
  // away and the process restarts.
  group(
    'revenue-sync · the verified baseline reaches this device',
    skip: phase != 'revenue-sync',
    () {
      test('the four verified rules arrive, complete and parseable', () async {
        await signInAs('giridhar@hki.com');
        final report = await sync.synchronise();

        expect(report.authorityConfirmed, isTrue);
        expect(
          report.rejectedSnapshotReason,
          isNull,
          reason:
              'the real server configuration must satisfy the domain invariants',
        );

        final rules = await db.select(db.revenueTaxRates).get();
        final live = rules.where((r) => r.archivedAt == null).toList();

        // Filtered on `archived_at`, deliberately: live tests archive what they create
        // and no client holds DELETE on financial configuration, so the development
        // project legitimately accumulates archived rows (D-107).
        expect(live, hasLength(4));

        final categories = {
          for (final c in await db.select(db.revenueCategories).get())
            c.id: c.code,
        };
        final byCategory = {
          for (final r in live) categories[r.revenueCategoryId]: r,
        };

        for (final expected in const [
          ('RESTAURANT', 500, 'inclusive'),
          ('NANDBHOG', 500, 'inclusive'),
          ('ROOM', 500, 'inclusive'),
          ('BANQUET', 0, 'none'),
        ]) {
          final rule = byCategory[expected.$1];
          expect(rule, isNotNull, reason: expected.$1);
          expect(rule!.rateBasisPoints, expected.$2, reason: expected.$1);
          expect(rule.treatment, expected.$3, reason: expected.$1);
          expect(rule.effectiveFrom, '2026-04-01', reason: expected.$1);
          expect(
            rule.inputBasis,
            'inclusive_total',
            reason: '${expected.$1} — the column that never used to be synced',
          );
          expect(rule.valueBandId, isNull, reason: 'no band is configured yet');
          expect(rule.supplySubtypeId, isNull);
          expect(rule.premisesStatusCode, isNull);
        }
      });

      test(
        'the optional datasets arrive empty, and that is a synchronised answer',
        () async {
          // Acceptance facts for the current baseline, not runtime assumptions: the code
          // must treat any count as valid, and it is this table's job to say what the
          // count happens to be today.
          expect(await db.select(db.revenueValueBands).get(), isEmpty);
          expect(await db.select(db.revenueSupplySubtypes).get(), isEmpty);
          expect(await db.select(db.businessUnitTaxStatuses).get(), isEmpty);

          final snapshots = await db.select(db.revenueConfigSnapshots).get();
          expect(snapshots, isNotEmpty);
          for (final snapshot in snapshots) {
            expect(snapshot.status, 'complete');
            expect(
              RevenueConfigDataset.decode(snapshot.datasets),
              RevenueConfigDataset.all,
              reason: 'all four datasets, or the claim is not completeness',
            );
          }
        },
      );
    },
  );

  group(
    'revenue-sync-offline · resolution with the transport gone',
    skip: phase != 'revenue-sync-offline',
    () {
      test(
        'all four categories resolve from the cache, exactly in paise',
        () async {
          // No sign-in and no sync: this phase reads what the previous one left on disk,
          // which is the whole point. If the cached configuration did not survive, nothing
          // below can pass.
          final repository = RevenueTaxRepository(db);
          final categories = {
            for (final c in await db.select(db.revenueCategories).get())
              c.code: (id: c.id, unit: c.businessUnitId),
          };
          expect(
            categories.keys,
            containsAll(['RESTAURANT', 'ROOM', 'BANQUET']),
          );

          final owner = await db
              .select(db.revenueConfigSnapshots)
              .get()
              .then((rows) => rows.first.userId);

          for (final expected in const [
            ('RESTAURANT', 10000000, 476190, 9523810),
            ('NANDBHOG', 10000000, 476190, 9523810),
            ('ROOM', 6500000, 309524, 6190476),
            ('BANQUET', 4034300, 0, 4034300),
          ]) {
            final category = categories[expected.$1]!;
            final outcome = await repository.resolve(
              RevenueTaxFacts(
                revenueCategoryId: category.id,
                businessDate: BusinessDate.of(2026, 6, 15),
              ),
              userId: owner,
              businessUnitId: category.unit,
            );

            expect(outcome, isA<RevenueTaxResolved>(), reason: expected.$1);
            final computed = (outcome as RevenueTaxResolved).rule.compute(
              Money.fromPaise(expected.$2),
            );
            expect(computed.gross.paise, expected.$2, reason: expected.$1);
            expect(computed.tax.paise, expected.$3, reason: expected.$1);
            expect(computed.net.paise, expected.$4, reason: expected.$1);
            expect(computed.reconciles, isTrue, reason: expected.$1);
          }
        },
      );

      test('and no revenue was created doing it', () async {
        // Slice 6 synchronises configuration. It does not record revenue, and asserting
        // that is cheaper than discovering later that something did.
        expect(await db.select(db.revenueEntries).get(), isEmpty);
        expect(await db.select(db.revenueComponents).get(), isEmpty);
      });
    },
  );

  // ── Revenue create, through the real repository and worker (Slice 7) ──────────
  //
  // The same repository and the same outbox the future entry screen will call. Nothing
  // here reaches into the RPC directly except where a test is specifically about the
  // server's own answer: if this passes, the code path a person will use works, which is
  // the assertion D-077 exists to insist on.
  group(
    'revenue-create · the four verified categories, end to end',
    skip: phase != 'revenue-create',
    () {
      late RevenueRepository revenue;
      late OutboxRepository outboxRepo;
      late SyncEngine engine;
      late String actorId;
      late AuthoritySnapshot snapshot;

      /// Every document this phase creates carries a marker, which is the one identifier
      /// that survives a process boundary (D-071) and everything the test does to the
      /// fixture (D-076).
      const marker = 'SLICE7-ACCEPTANCE';

      setUp(() async {
        await signInAs('giridhar@hki.com');
        revenue = RevenueRepository(db);
        outboxRepo = OutboxRepository(db);

        final refresh = await authority.refresh();
        expect(refresh, isA<AuthorityConfirmed>());
        snapshot = (refresh as AuthorityConfirmed).snapshot;
        actorId = snapshot.userId;

        // Real configuration, pulled by the real sync — not a fixture.
        final report = await sync.synchronise();
        expect(report.authorityConfirmed, isTrue);
        expect(report.rejectedSnapshotReason, isNull);

        engine = SyncEngine(
          outbox: outboxRepo,
          endpoint: RevenueMutationEndpoint(RevenueGateway(client)),
          clock: DateTime.now,
          actorUserId: actorId,
          reconciler: RevenueReconciler(revenue, RevenueGateway(client)),
        );
      });

      Future<String> createOne({
        required String categoryCode,
        required int amountMinor,
      }) async {
        final category = await (db.select(
          db.revenueCategories,
        )..where((c) => c.code.equals(categoryCode))).getSingle();

        final draft = RevenueEntryDraft(
          id: const Uuid().v4(),
          businessUnitId: category.businessUnitId,
          revenueCategoryId: category.id,
          businessDate: BusinessDate.of(2026, 6, 15),
          capturedAt: DateTime.now().toUtc(),
          notes: '$marker $categoryCode',
          components: [
            RevenueComponentDraft(
              id: const Uuid().v4(),
              enteredAmount: Money.fromPaise(amountMinor),
            ),
          ],
        );

        final decision = await revenue.evaluate(draft, authority: snapshot);
        expect(
          decision,
          isA<RevenueCreatePermitted>(),
          reason: decision is RevenueCreateRefused
              ? decision.refusal.toString()
              : null,
        );

        await revenue.createLocally(
          draft,
          resolutions: (decision as RevenueCreatePermitted).resolutions,
          actorUserId: actorId,
          orgId: snapshot.orgId,
          mutationId: const Uuid().v4(),
          now: DateTime.now().toUtc(),
        );
        return draft.id;
      }

      test(
        'each of the four records, syncs and receives a KI-REV number',
        () async {
          // The verified baseline, at the figures the parity vectors pin.
          const expected = <String, (int, int, int)>{
            'RESTAURANT': (10000000, 476190, 9523810),
            'NANDBHOG': (1250000, 59524, 1190476),
            'ROOM': (6500000, 309524, 6190476),
            'BANQUET': (4034300, 0, 4034300),
          };

          final ids = <String, String>{};
          for (final entry in expected.entries) {
            ids[entry.key] = await createOne(
              categoryCode: entry.key,
              amountMinor: entry.value.$1,
            );
          }

          final report = await engine.pushOnce();
          expect(report.applied, 4, reason: 'four accepted, none refused');
          expect(report.rejected, 0);
          expect(report.conflicts, 0);

          final numbers = <String>{};
          for (final entry in expected.entries) {
            final local = await revenue.load(ids[entry.key]!);
            expect(local, isNotNull, reason: entry.key);
            expect(
              local!.txnNumber,
              startsWith('KI-REV-'),
              reason: '${entry.key} received a server-issued number',
            );
            numbers.add(local.txnNumber!);

            final component = local.components.single;
            expect(component.gross.paise, entry.value.$1, reason: entry.key);
            expect(component.tax.paise, entry.value.$2, reason: entry.key);
            expect(component.net.paise, entry.value.$3, reason: entry.key);
          }

          expect(
            numbers,
            hasLength(4),
            reason:
                'four documents, four distinct numbers from one FY sequence',
          );

          // The server agrees, read back through the authorised projection.
          for (final id in ids.values) {
            final rows = await client
                .from('revenue_document')
                .select('id, txn_number')
                .eq('id', id);
            expect(
              rows,
              hasLength(1),
              reason: 'exactly one canonical document',
            );
          }
        },
      );

      test('a redelivery of the same intent creates nothing new', () async {
        final id = await createOne(
          categoryCode: 'RESTAURANT',
          amountMinor: 5000000,
        );
        final mutationId =
            (await db
                        .customSelect(
                          'SELECT mutation_id FROM sync_outbox WHERE entity_id = ?',
                          variables: [Variable<String>(id)],
                        )
                        .getSingle())
                    .data['mutation_id']!
                as String;

        await engine.pushOnce();
        final first = (await revenue.load(id))!.txnNumber;
        expect(first, isNotNull);

        // Deliver the identical intent again, exactly as a lost response would.
        final replay = await RevenueGateway(client).create(
          arguments: RevenueRepository.createPayload((await revenue.load(id))!),
          mutationId: mutationId,
        );
        expect(replay, isA<RemoteOk<Map<String, dynamic>>>());
        final payload = (replay as RemoteOk<Map<String, dynamic>>).value;
        expect(
          payload['status'],
          'replayed',
          reason: 'the stored result, replayed',
        );
        expect(
          payload['txn_number'],
          first,
          reason: 'the same canonical number, not a second one',
        );

        final rows = await client
            .from('revenue_document')
            .select('id')
            .eq('id', id);
        expect(
          rows,
          hasLength(1),
          reason: 'one mutation id, one financial record',
        );
      });

      test(
        'a declared figure the server disagrees with is refused (KM030)',
        () async {
          // The tax-mismatch contract, against the real server. The client sends what it
          // showed the operator; the server computes its own and refuses rather than
          // quietly recording different money under the same acceptance.
          final category = await (db.select(
            db.revenueCategories,
          )..where((c) => c.code.equals('RESTAURANT'))).getSingle();

          final outcome = await RevenueGateway(client).create(
            arguments: {
              'p_id': const Uuid().v4(),
              'p_business_unit_id': category.businessUnitId,
              'p_revenue_category_id': category.id,
              'p_business_date': '2026-06-15',
              'p_entry_kind': 'daily_summary',
              'p_notes': '$marker MISMATCH',
              'p_components': [
                {
                  'entered_amount_minor': 10000000,
                  // One paisa away from the server's own figure.
                  'declared_tax_minor': 476191,
                },
              ],
            },
            mutationId: const Uuid().v4(),
          );

          expect(outcome, isA<RemoteRefused<Map<String, dynamic>>>());
          final refusal =
              (outcome as RemoteRefused<Map<String, dynamic>>).refusal;
          expect(refusal.kind, RefusalKind.taxConfigurationMismatch);
          expect(
            refusal.message,
            contains('changed since it was prepared'),
            reason: 'the sentence names what happened, so a person can decide',
          );
          for (final internal in const [
            'KM030',
            'SQLSTATE',
            'revenue_tax_rates',
            'plpgsql',
          ]) {
            expect(
              refusal.message,
              isNot(contains(internal)),
              reason: 'no refusal may hand a user an implementation detail',
            );
          }
        },
      );

      test('no revenue entry surface shipped in this slice', () {
        // Slice 8 owns the Android entry screen and Slice 9 the Windows ledger. Asserted
        // rather than assumed, because "we did not build it" is exactly the claim D-077
        // showed can be false while everything looks green.
        final revenueFeature = Directory('lib/features/revenue');
        expect(
          revenueFeature.existsSync() &&
              revenueFeature.listSync().whereType<File>().isNotEmpty,
          isFalse,
          reason: 'no revenue feature surface belongs in Slice 7',
        );
      });
    },
  );

  group(
    'revenue-cleanup · the fixtures this phase created are reversed',
    skip: phase != 'revenue-cleanup',
    () {
      test('every acceptance document is voided, and the baseline is intact', () async {
        await signInAs('giridhar@hki.com');

        // Found by the marker rather than by an id held in memory, because each phase is
        // its own process — the mistake D-071 records. Voided rather than deleted:
        // financial history is corrected by void plus audit, never by removing rows
        // (D-006), and no client role holds DELETE on a financial table.
        final open = await client
            .from('revenue_document')
            .select('id, row_version, notes')
            .like('notes', '%SLICE7-ACCEPTANCE%')
            .isFilter('voided_at', null);

        var reversed = 0;
        for (final row in open.cast<Map<String, dynamic>>()) {
          final outcome = await RevenueGateway(client).voidEntry(
            entryId: row['id'] as String,
            baseRowVersion: row['row_version'] as int? ?? 1,
            reason: 'Slice 7 acceptance fixture reversal',
            mutationId: const Uuid().v4(),
          );
          expect(outcome, isA<RemoteOk<Map<String, dynamic>>>());
          reversed++;
        }

        final remaining = await client
            .from('revenue_document')
            .select('id')
            .like('notes', '%SLICE7-ACCEPTANCE%')
            .isFilter('voided_at', null);
        expect(
          remaining,
          isEmpty,
          reason: 'reversed $reversed of ${open.length}; none may remain open',
        );

        // And the verified configuration is exactly as the migration installed it.
        final rules = await client
            .from('revenue_tax_rates')
            .select('id')
            .isFilter('archived_at', null);
        expect(rules, hasLength(4));
        expect(await client.from('revenue_value_bands').select('id'), isEmpty);
        expect(
          await client.from('revenue_supply_subtypes').select('id'),
          isEmpty,
        );
        expect(
          await client.from('business_unit_tax_statuses').select('id'),
          isEmpty,
        );
      });
    },
  );

  group('the repository and the server agree', skip: phase != 'drift', () {
    test('every applied migration has a file in supabase/migrations', () async {
      await signInAs('giridhar@hki.com');

      // `supabase_migrations` is not exposed through PostgREST, so this reads the
      // versions the way a developer would: from the filenames the CLI would push, and
      // from the functions the server actually exposes. The check that matters is that
      // nothing is callable on the server which no committed migration creates.
      final files = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      final exposed = await client.rpc<dynamic>('my_authority');
      expect(exposed, isA<Map>(), reason: 'my_authority must answer');

      for (final function in const [
        'my_authority',
        'master_rename',
        'master_archive',
        'master_restore',
        'user_role_grant',
        'user_role_revoke',
        'user_deactivate',
        'user_reactivate',
      ]) {
        expect(
          files,
          contains('function public.$function('),
          reason:
              '$function is callable on the server but no committed migration '
              'creates it — the repository could not rebuild this environment',
        );
      }
    });
  });
}
