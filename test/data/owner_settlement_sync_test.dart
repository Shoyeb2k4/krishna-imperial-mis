/// The canonical owner cache: what a synchronisation establishes, and what it never does.
///
/// Phase 5 OA-2 §18, §19, §20, §27, §28. Against a real SQLite database and a controllable
/// snapshot source, because the properties that matter here are about what survives a run
/// and what does not.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/owner_accounts/settlement/owner_settlement.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import '../support/cache_principal.dart';

/// A snapshot source under the test's control.
class _Source implements OwnerSnapshotSource {
  _Source(this.answer);

  RemoteOutcome<Map<String, dynamic>> Function() answer;
  int calls = 0;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot() async {
    calls++;
    return answer();
  }
}

Map<String, dynamic> movementJson({
  required String id,
  String owner = 'owner-a',
  String type = 'withdrawal',
  String direction = 'debit',
  int amount = 1000000,
  String date = '2026-06-15',
  String? voidedAt,
  String txn = 'KI-OWN-26-27-000001',
  int rowVersion = 1,
}) => {
  'id': id,
  'org_id': 'org',
  'business_unit_id': 'hki',
  'owner_id': owner,
  'txn_number': txn,
  'financial_year': '26-27',
  'business_date': date,
  'business_date_source': 'derived',
  'pnl_period_key': date.substring(0, 7),
  'movement_type': type,
  'direction': direction,
  'amount_minor': amount,
  'family_member_id': null,
  'collected_by_family_member_id': null,
  'nc_bill_reference': null,
  'reference_number': null,
  'remarks': null,
  'reason': type == 'manual_adjustment' ? 'stated' : null,
  'created_by': 'user',
  'captured_at': '2026-06-15T10:00:00.000Z',
  'row_version': rowVersion,
  'change_seq': 100,
  'voided_at': voidedAt,
  'void_reason': voidedAt == null ? null : 'stated',
};

Map<String, dynamic> shareJson(String owner, {int bp = 5000}) => {
  'id': 'share-$owner',
  'org_id': 'org',
  'owner_id': owner,
  'share_basis_points': bp,
  'effective_from': '2026-01-01',
  'effective_to': null,
  'note': null,
  'row_version': 1,
  'change_seq': 10,
};

Map<String, dynamic> ownerJson(String id, {bool active = true}) => {
  'id': id,
  'org_id': 'org',
  'code': id.toUpperCase(),
  'display_name': 'Owner $id',
  'active': active,
  'archived_at': null,
  'row_version': 1,
  'change_seq': 5,
};

/// The OA-3 transport: the caller's authority is stated, and the start date travels with
/// the facts. Defaults to an authorised caller whose organisation has **not configured**
/// a start date, because that is the honest state of every real environment today.
Map<String, dynamic> snapshot({
  List<Map<String, dynamic>>? movements,
  List<Map<String, dynamic>>? owners,
  List<Map<String, dynamic>>? shares,
  String snapshotId = 'snapshot-1',
  String serverTime = '2026-07-01T09:00:00.000Z',
  bool authorised = true,
  String? ownershipStartDate,
}) => {
  'snapshot_id': snapshotId,
  'server_time': serverTime,
  'settlement_authorised': authorised,
  'ownership_start_date': authorised ? ownershipStartDate : null,
  'movements': authorised ? (movements ?? const []) : null,
  'owners': authorised
      ? (owners ?? [ownerJson('owner-a'), ownerJson('owner-b')])
      : null,
  'ownership_shares': authorised
      ? (shares ?? [shareJson('owner-a'), shareJson('owner-b')])
      : null,
  'family_members': authorised ? const [] : null,
};

void main() {
  late AppDatabase db;
  late _Source source;
  late OwnerSettlementSync sync;
  late OwnerSettlementRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    source = _Source(() => RemoteOk(snapshot()));
    sync = OwnerSettlementSync(
      database: db,
      gateway: source,
      ownerUserId: 'user-1',
    );
    repository = OwnerSettlementRepository(
      db,
      principal: canonicalCachePrincipal('user-1'),
    );
  });

  tearDown(() => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  group('§18 · a device knows whether it may settle at all', () {
    test(
      'before any run there is no coverage, and a settlement refuses',
      () async {
        expect(await repository.coverage(), isNull);

        final outcome = await repository.settle(
          periodKey: '2026-06',
          periodStart: BusinessDate.of(2026, 6, 1),
          periodEnd: BusinessDate.of(2026, 6, 30),
          inception: BusinessDate.of(2026, 1, 1),
          operatingProfit: const CanonicalOperatingProfit(
            cumulativeBeforePeriod: Money.zero,
            cumulativeAtPeriodEnd: Money.zero,
          ),
        );

        expect(
          (outcome as OwnerSettlementRefused).refusal,
          OwnerSettlementRefusal.ledgerCoverageIncomplete,
          reason:
              'a device that has never synchronised holds only what it recorded itself, '
              'and a settlement over that is wrong by exactly what it never saw',
        );
      },
    );

    test(
      'a successful run establishes coverage from the server own evidence',
      () async {
        final result = await sync.synchronise();

        expect(result, isA<OwnerSettlementSynchronised>());
        final coverage = await repository.coverage();
        expect(coverage, isNotNull);
        expect(coverage!.snapshotId, 'snapshot-1');
        expect(
          coverage.serverConfirmedAt,
          DateTime.utc(2026, 7, 1, 9),
          reason: 'the server time, from the statement that returned the facts',
        );
        expect(coverage.movementCount, 0);
      },
    );

    test(
      'zero movements is a synchronised answer, not an unsynchronised one',
      () async {
        await sync.synchronise();
        // The distinction D-106 and D-108 exist for: "the owners have moved no money" and
        // "this device has never asked" are different facts and must not collapse.
        expect(await repository.coverage(), isNotNull);
        expect(
          await repository.canonicalMovements(
            through: BusinessDate.of(2026, 12, 31),
          ),
          isEmpty,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§19 · the full replace, and what it makes automatic', () {
    test('movements, shares and owners all arrive', () async {
      source.answer = () => RemoteOk(
        snapshot(
          movements: [
            movementJson(id: 'm1'),
            movementJson(id: 'm2'),
          ],
        ),
      );
      await sync.synchronise();

      expect(
        await repository.canonicalMovements(
          through: BusinessDate.of(2026, 12, 31),
        ),
        hasLength(2),
      );
      expect((await repository.ownershipShares()).shares, hasLength(2));
      expect(await repository.activeOwnerIds(), {'owner-a', 'owner-b'});
    });

    test(
      'a correction arrives corrected, with no propagation machinery (§27)',
      () async {
        source.answer = () => RemoteOk(
          snapshot(movements: [movementJson(id: 'm1', amount: 1000000)]),
        );
        await sync.synchronise();

        source.answer = () => RemoteOk(
          snapshot(
            movements: [movementJson(id: 'm1', amount: 700000, rowVersion: 2)],
            snapshotId: 'snapshot-2',
          ),
        );
        await sync.synchronise();

        final movements = await repository.canonicalMovements(
          through: BusinessDate.of(2026, 12, 31),
        );
        expect(movements, hasLength(1), reason: 'replaced, never appended');
        expect(movements.single.amount, Money.fromPaise(700000));
        expect(movements.single.rowVersion, 2);
      },
    );

    test(
      'a void arrives carrying voided_at, and contributes nothing (§28)',
      () async {
        source.answer = () =>
            RemoteOk(snapshot(movements: [movementJson(id: 'm1')]));
        await sync.synchronise();

        source.answer = () => RemoteOk(
          snapshot(
            movements: [
              movementJson(id: 'm1', voidedAt: '2026-06-20T10:00:00.000Z'),
            ],
            snapshotId: 'snapshot-2',
          ),
        );
        await sync.synchronise();

        final movements = await repository.canonicalMovements(
          through: BusinessDate.of(2026, 12, 31),
        );
        expect(
          movements.single.isVoided,
          isTrue,
          reason: 'history is preserved',
        );
        expect(
          movements.single.isCanonical,
          isFalse,
          reason:
              'and it contributes nothing — the one rule, stated in the domain',
        );
      },
    );

    test(
      'a movement the server no longer returns simply ceases to exist here',
      () async {
        source.answer = () => RemoteOk(
          snapshot(
            movements: [
              movementJson(id: 'm1'),
              movementJson(id: 'm2'),
            ],
          ),
        );
        await sync.synchronise();

        source.answer = () => RemoteOk(
          snapshot(
            movements: [movementJson(id: 'm1')],
            snapshotId: 'snapshot-2',
          ),
        );
        await sync.synchronise();

        expect(
          await repository.canonicalMovements(
            through: BusinessDate.of(2026, 12, 31),
          ),
          hasLength(1),
          reason:
              'nothing is preserved across a run, so a stale row cannot survive — which '
              'is what a full replace buys instead of a watermark',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('a failed or malformed run withdraws nothing', () {
    setUp(() async {
      source.answer = () =>
          RemoteOk(snapshot(movements: [movementJson(id: 'm1')]));
      await sync.synchronise();
    });

    test(
      'an unreachable server leaves yesterday coverage exactly as it was',
      () async {
        source.answer = () => const RemoteUnreachable(RemoteFailure.offline);
        final result = await sync.synchronise();

        expect(result, isA<OwnerSettlementSyncUnavailable>());
        expect(
          (await repository.coverage())!.snapshotId,
          'snapshot-1',
          reason:
              'an answer that did not arrive is not an answer that said no (D-048)',
        );
        expect(
          await repository.canonicalMovements(
            through: BusinessDate.of(2026, 12, 31),
          ),
          hasLength(1),
        );
      },
    );

    test('a refusal is reported and destroys nothing', () async {
      source.answer = () => RemoteRefused(
        ServerRefusal.fromCode('missing_capability', serverMessage: 'no'),
      );
      expect(await sync.synchronise(), isA<OwnerSettlementSyncUnavailable>());
      expect(await repository.coverage(), isNotNull);
    });

    test('a malformed snapshot is refused, and the good one is kept', () async {
      // Fail closed rather than repair: replacing working coverage with unusable coverage
      // would make the device refuse every settlement *while claiming to be
      // synchronised*.
      source.answer = () => RemoteOk({'snapshot_id': 'x'});
      expect(await sync.synchronise(), isA<OwnerSettlementSyncRefused>());
      expect((await repository.coverage())!.snapshotId, 'snapshot-1');
    });

    test(
      'a movement the server has not accepted refuses the whole snapshot',
      () async {
        source.answer = () => RemoteOk(
          snapshot(
            movements: [movementJson(id: 'm9', txn: '')],
            snapshotId: 's9',
          ),
        );
        final result = await sync.synchronise();

        expect(result, isA<OwnerSettlementSyncRefused>());
        expect(
          (result as OwnerSettlementSyncRefused).reason,
          contains('not accepted'),
          reason:
              'a boundary that started returning attempts is a defect to surface, not to '
              'filter around (§16, §17)',
        );
        expect((await repository.coverage())!.snapshotId, 'snapshot-1');
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('OA-3 Q1 · the settlement start date travels with the facts', () {
    test('a configured date is recorded on this person coverage', () async {
      source.answer = () =>
          RemoteOk(snapshot(ownershipStartDate: '2026-04-01'));
      await sync.synchronise();

      expect(
        (await repository.coverage())!.ownershipStartDate,
        BusinessDate.of(2026, 4, 1),
        reason:
            'one authoritative server date: 50:50 ownership and settlement begin here',
      );
    });

    test(
      'not configured is recorded as not configured, and never defaulted',
      () async {
        await sync.synchronise();

        final coverage = await repository.coverage();
        expect(coverage, isNotNull, reason: 'the history itself is complete');
        expect(
          coverage!.ownershipStartDate,
          isNull,
          reason:
              'no financial-year start, no tax-configuration date, no earliest share: '
              'the production date is outstanding and is never guessed',
        );
      },
    );

    test('a start date that is not the first of a month is refused', () async {
      await sync.synchronise();
      source.answer = () => RemoteOk(
        snapshot(ownershipStartDate: '2026-04-15', snapshotId: 's2'),
      );

      expect(await sync.synchronise(), isA<OwnerSettlementSyncRefused>());
      expect(
        (await repository.coverage())!.snapshotId,
        'snapshot-1',
        reason: 'the good coverage is kept rather than replaced by a defect',
      );
    });

    test('an unreadable start date is refused', () async {
      source.answer = () =>
          RemoteOk(snapshot(ownershipStartDate: 'first of April'));
      expect(await sync.synchronise(), isA<OwnerSettlementSyncRefused>());
      expect(await repository.coverage(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('OA-3 · a confirmed not-authorised answer', () {
    test(
      'writes no coverage, and withdraws what this person held (D-070)',
      () async {
        source.answer = () => RemoteOk(
          snapshot(
            movements: [movementJson(id: 'm1')],
            ownershipStartDate: '2026-04-01',
          ),
        );
        await sync.synchronise();
        expect(await repository.coverage(), isNotNull);

        source.answer = () =>
            RemoteOk(snapshot(authorised: false, snapshotId: 's2'));
        final result = await sync.synchronise();

        expect(result, isA<OwnerSettlementSyncNotAuthorised>());
        expect(
          await repository.coverage(),
          isNull,
          reason:
              'the server said, in an answer that arrived, that this person may not read '
              'a settlement. That is confirmed authority loss, not a network failure',
        );
        expect(
          await repository.canonicalMovements(
            through: BusinessDate.of(2026, 12, 31),
          ),
          isEmpty,
        );
        expect((await repository.ownershipShares()).shares, isEmpty);
        expect(await repository.activeOwnerIds(), isEmpty);
      },
    );

    test('is never certified as complete history with nothing in it', () async {
      // The failure the null-not-empty server contract exists to prevent: if an
      // unauthorised answer were read as empty arrays, the device would certify "complete
      // history, no movements" — a missing side replaced with zero (D-163).
      source.answer = () => RemoteOk(snapshot(authorised: false));
      await sync.synchronise();
      expect(await repository.coverage(), isNull);
    });

    test('touches nobody else cache on the installation (D-074)', () async {
      final otherSync = OwnerSettlementSync(
        database: db,
        gateway: _Source(
          () => RemoteOk(snapshot(movements: [movementJson(id: 'm7')])),
        ),
        ownerUserId: 'user-2',
      );
      await otherSync.synchronise();

      source.answer = () => RemoteOk(snapshot(authorised: false));
      await sync.synchronise();

      final other = OwnerSettlementRepository(
        db,
        principal: canonicalCachePrincipal('user-2'),
      );
      expect(await other.coverage(), isNotNull);
      expect(
        await other.canonicalMovements(through: BusinessDate.of(2026, 12, 31)),
        hasLength(1),
      );
    });

    test(
      'an unreachable server is not a not-authorised answer, and withdraws nothing',
      () async {
        await sync.synchronise();
        source.answer = () => const RemoteUnreachable(RemoteFailure.offline);
        expect(await sync.synchronise(), isA<OwnerSettlementSyncUnavailable>());
        expect(await repository.coverage(), isNotNull);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('OA-3 · the transport contract is stated, never inferred', () {
    test(
      'a snapshot that does not say whether the caller was authorised is refused',
      () async {
        await sync.synchronise();
        final legacy = snapshot(snapshotId: 's2')
          ..remove('settlement_authorised');
        source.answer = () => RemoteOk(legacy);

        expect(await sync.synchronise(), isA<OwnerSettlementSyncRefused>());
        expect((await repository.coverage())!.snapshotId, 'snapshot-1');
      },
    );

    test('an authorised snapshot with a null dataset is malformed', () async {
      final broken = snapshot()..['movements'] = null;
      source.answer = () => RemoteOk(broken);
      expect(await sync.synchronise(), isA<OwnerSettlementSyncRefused>());
      expect(await repository.coverage(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('D-074 · the cache belongs to a person, not to the installation', () {
    test(
      'a second person on the same device reads none of the first cache',
      () async {
        source.answer = () =>
            RemoteOk(snapshot(movements: [movementJson(id: 'm1')]));
        await sync.synchronise();

        final otherPerson = OwnerSettlementRepository(
          db,
          principal: canonicalCachePrincipal('user-2'),
        );
        expect(await otherPerson.coverage(), isNull);
        expect(
          await otherPerson.canonicalMovements(
            through: BusinessDate.of(2026, 12, 31),
          ),
          isEmpty,
        );
        expect((await otherPerson.ownershipShares()).shares, isEmpty);
        expect(await otherPerson.activeOwnerIds(), isEmpty);
      },
    );

    test(
      'and one person run does not disturb another already-synchronised one',
      () async {
        await sync.synchronise();

        final other = OwnerSettlementSync(
          database: db,
          gateway: _Source(
            () => RemoteOk(
              snapshot(
                movements: [movementJson(id: 'm9')],
                snapshotId: 'other',
              ),
            ),
          ),
          ownerUserId: 'user-2',
        );
        await other.synchronise();

        expect((await repository.coverage())!.snapshotId, 'snapshot-1');
        expect(
          await repository.canonicalMovements(
            through: BusinessDate.of(2026, 12, 31),
          ),
          isEmpty,
          reason: 'user-1 synchronised an empty ledger and still holds one',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the settlement reads the cache, offline, and refuses on the vector', () {
    test(
      'a settlement computes with the source gone, once coverage exists',
      () async {
        source.answer = () => RemoteOk(
          snapshot(
            movements: [
              movementJson(id: 'm1', amount: 2000000, date: '2026-06-15'),
            ],
          ),
        );
        await sync.synchronise();

        // The transport is now unusable. Reporting is never gated on the network, and
        // neither is settlement over coverage already established (§19).
        source.answer = () => const RemoteUnreachable(RemoteFailure.offline);

        final outcome = await repository.settle(
          periodKey: '2026-06',
          periodStart: BusinessDate.of(2026, 6, 1),
          periodEnd: BusinessDate.of(2026, 6, 30),
          inception: BusinessDate.of(2026, 1, 1),
          operatingProfit: CanonicalOperatingProfit(
            cumulativeBeforePeriod: Money.zero,
            cumulativeAtPeriodEnd: Money.fromPaise(20000000),
          ),
        );

        final computed = outcome as OwnerSettlementComputed;
        expect(computed.lines, hasLength(2));
        final a = computed.lines.firstWhere((l) => l.ownerId == 'owner-a');
        expect(a.profitEntitlement, Money.fromPaise(10000000));
        expect(a.withdrawals, Money.fromPaise(2000000));
        expect(a.closingPosition, Money.fromPaise(8000000));
        expect(computed.entitlementReconciles, isTrue);
        expect(computed.linesReconcile, isTrue);
      },
    );

    test('a cached vector that is not the V1 pair refuses', () async {
      source.answer = () => RemoteOk(
        snapshot(
          shares: [
            shareJson('owner-a', bp: 6000),
            shareJson('owner-b', bp: 4000),
          ],
        ),
      );
      await sync.synchronise();

      final outcome = await repository.settle(
        periodKey: '2026-06',
        periodStart: BusinessDate.of(2026, 6, 1),
        periodEnd: BusinessDate.of(2026, 6, 30),
        inception: BusinessDate.of(2026, 1, 1),
        operatingProfit: const CanonicalOperatingProfit(
          cumulativeBeforePeriod: Money.zero,
          cumulativeAtPeriodEnd: Money.zero,
        ),
      );
      expect(
        (outcome as OwnerSettlementRefused).refusal,
        OwnerSettlementRefusal.ownershipUnavailable,
      );
    });

    test(
      'an archived owner holding an open share fails the count (D-204)',
      () async {
        source.answer = () => RemoteOk(
          snapshot(
            owners: [ownerJson('owner-a'), ownerJson('owner-b', active: false)],
          ),
        );
        await sync.synchronise();

        expect(await repository.activeOwnerIds(), {'owner-a'});

        final vector = (await repository.ownershipShares()).resolveV1For(
          BusinessDate.of(2026, 6, 1),
          BusinessDate.of(2026, 6, 30),
          activeOwnerIds: await repository.activeOwnerIds(),
        );
        expect(
          (vector as OwnershipRefused).refusal,
          OwnershipRefusal.shareBelongsToInactiveOwner,
        );
      },
    );
  });
}
