/// The Owner Ledger write path, and the invariant this whole slice is judged against.
///
/// Phase 5 OA-1. Two groups matter more than the rest:
///
/// **§40 and §41 — non-interference.** Recording an owner withdrawal or a non-chargeable
/// bill must not move a single paisa of Expense contributions, Revenue contributions,
/// Gross Sales, GST, Net Sales or Operating Profit. Not "should not": the figures are
/// captured before and compared after, so the assertion fails on one paisa.
///
/// **§18 and §25 — one transport.** The write and its outbox intent commit together, one
/// document holds at most one queued intent, and a correction rewrites it in place
/// carrying the version it was actually made against (D-125, D-130).
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/repositories/owner_ledger_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_ledger.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

const _ownerA = 'owner-a';
const _ownerB = 'owner-b';
const _ccr = 'ccr-unit';
const _hki = 'hki-unit';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late OwnerLedgerRepository owners;
  late ExpenseRepository expenses;
  late RevenueRepository revenue;

  final now = DateTime.utc(2026, 6, 15, 9, 30);
  final june = BusinessDate.of(2026, 6, 15);

  /// Two owners and three family members, as the tests need them.
  ///
  /// Written straight into the tables rather than through the administrative RPCs, which
  /// live on the server. This is the local read model, and the point of these tests is
  /// the write path over it.
  Future<void> seedOwners() async {
    // Parameterised rather than interpolated. A name like "Owner A's spouse" carries an
    // apostrophe, which is exactly the character that ends a SQL literal — and the first
    // version of this fixture failed with `syntax error near "s"` for that reason.
    Future<void> owner(String id, String code, String name) =>
        db.customStatement(
          'INSERT INTO owners (id, org_id, code, display_name, updated_at) '
          'VALUES (?1, ?2, ?3, ?4, ?5)',
          [id, 'org', code, name, now.toIso8601String()],
        );
    Future<void> member(
      String id,
      String ownerId,
      String name, {
      bool mayUseNc = true,
    }) => db.customStatement(
      'INSERT INTO owner_family_members '
      '(id, org_id, owner_id, display_name, may_use_nc, effective_from, updated_at) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
      [
        id,
        'org',
        ownerId,
        name,
        mayUseNc ? 1 : 0,
        '2026-04-01',
        now.toIso8601String(),
      ],
    );

    await owner(_ownerA, 'OWNER_A', 'Owner A');
    await owner(_ownerB, 'OWNER_B', 'Owner B');
    await member('fam-a-self', _ownerA, 'Owner A');
    await member('fam-a1', _ownerA, "Owner A's spouse");
    await member('fam-a2', _ownerA, "Owner A's son");
    await member('fam-b1', _ownerB, "Owner B's daughter");
    await member('fam-a3', _ownerA, "Owner A's cousin", mayUseNc: false);
  }

  OwnerMovementDraft draft({
    String? id,
    OwnerMovementType type = OwnerMovementType.withdrawal,
    int paise = 5000000,
    String businessUnitId = _hki,
    String? ownerId = _ownerA,
    String? familyMemberId,
    OwnerLedgerDirection? direction,
    String? collectedBy,
    String? reason,
    BusinessDate? date,
  }) => OwnerMovementDraft(
    id: id ?? const Uuid().v4(),
    businessUnitId: businessUnitId,
    businessDate: date ?? june,
    movementType: type,
    amount: Money.fromPaise(paise),
    capturedAt: now,
    ownerId: ownerId,
    familyMemberId: familyMemberId,
    direction: direction,
    collectedByFamilyMemberId: collectedBy,
    reason: reason,
  );

  /// Records a movement through the real eligibility and write path.
  Future<OwnerLedgerEntry> record(
    OwnerMovementDraft d, {
    String actorUserId = 'user-1',
    String? mutationId,
  }) async {
    final decision = await owners.evaluate(
      d,
      periodOpen: true,
      authorisedForUnit: true,
      authenticated: true,
    );
    final permitted = decision as OwnerMovementPermitted;
    return owners.createLocally(
      d,
      ownerId: permitted.ownerId,
      direction: permitted.direction,
      actorUserId: actorUserId,
      orgId: 'org',
      mutationId: mutationId ?? const Uuid().v4(),
      now: now,
    );
  }

  /// Accepts a movement, as the server and the sync worker would together.
  ///
  /// **The queue entry is marked done as well as the row reconciled.** Reconciling alone
  /// would leave a state that never occurs in production — an accepted movement whose
  /// create is still queued — and a coalescing test built on it would be measuring a
  /// situation nobody can reach. Found by expecting a base version of 2 and getting null.
  Future<void> accept(
    String id, {
    String number = 'KI-OWN-26-27-000001',
  }) async {
    await owners.reconcileAcceptance(
      OwnerMovementAcceptance(
        entryId: id,
        rowVersion: 1,
        txnNumber: number,
        financialYear: '26-27',
      ),
    );
    await (db.update(db.syncOutbox)..where((o) => o.entityId.equals(id))).write(
      SyncOutboxCompanion(status: Value(OutboxStatus.done.name)),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: now);
    await seedOwners();
    owners = OwnerLedgerRepository(db);
    expenses = ExpenseRepository(db);
    revenue = RevenueRepository(db);
  });

  tearDown(() => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  group('the save is atomic, and the outbox is inside it (§18)', () {
    test('one transaction writes the movement and its queue entry', () async {
      final mutationId = const Uuid().v4();
      final entry = await record(draft(), mutationId: mutationId);

      final saved = await owners.load(entry.id);
      expect(saved, isNotNull);
      expect(saved!.amount.paise, 5000000);
      expect(saved.ownerId, _ownerA);
      expect(saved.direction, OwnerLedgerDirection.debit);

      final queued = await (db.select(
        db.syncOutbox,
      )..where((o) => o.entityId.equals(entry.id))).getSingle();
      expect(queued.mutationId, mutationId);
      expect(queued.entityType, ownerMovementEntityType);
      expect(queued.op, MutationOp.create.name);
      expect(
        queued.actorUserId,
        'user-1',
        reason: 'whose intent this is — D-050, and the basis for D-074',
      );
      expect(
        queued.baseRowVersion,
        isNull,
        reason: 'a create establishes a new identity (D-021)',
      );
    });

    test('no transaction number is ever invented locally', () async {
      final entry = await record(draft());
      final saved = await owners.load(entry.id);
      expect(saved!.txnNumber, isNull);
      expect(saved.financialYear, isNull);
      expect(saved.isAccepted, isFalse);
    });

    test('the payload sent is the one captured at save time', () async {
      final entry = await record(
        draft(type: OwnerMovementType.ncConsumption, familyMemberId: 'fam-a1'),
      );
      final queued = await (db.select(
        db.syncOutbox,
      )..where((o) => o.entityId.equals(entry.id))).getSingle();
      final payload = jsonDecode(queued.payload) as Map<String, Object?>;

      expect(payload['p_movement_type'], 'nc_consumption');
      expect(payload['p_family_member_id'], 'fam-a1');
      expect(
        payload['p_declared_owner_id'],
        _ownerA,
        reason:
            'what the surface showed — compared by the server, never used (§12)',
      );
      expect(
        payload['p_owner_id'],
        isNull,
        reason: 'a consumption derives its owner; it does not dictate one',
      );
    });

    test('a withdrawal dictates its owner and declares nothing', () async {
      final entry = await record(draft());
      final queued = await (db.select(
        db.syncOutbox,
      )..where((o) => o.entityId.equals(entry.id))).getSingle();
      final payload = jsonDecode(queued.payload) as Map<String, Object?>;

      expect(payload['p_owner_id'], _ownerA);
      expect(payload['p_declared_owner_id'], isNull);
      expect(payload['p_direction'], 'debit');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('eligibility is decided before anything is written (§12, D-113)', () {
    test('a consumption derives its owner from the person', () async {
      final decision = await owners.evaluate(
        draft(
          type: OwnerMovementType.ncConsumption,
          familyMemberId: 'fam-a2',
          ownerId: null,
        ),
        periodOpen: true,
        authorisedForUnit: true,
        authenticated: true,
      );
      expect((decision as OwnerMovementPermitted).ownerId, _ownerA);
    });

    test(
      'a declared owner that disagrees is refused, not re-attributed',
      () async {
        final decision = await owners.evaluate(
          draft(
            type: OwnerMovementType.ncConsumption,
            familyMemberId: 'fam-a2',
            ownerId: _ownerB,
          ),
          periodOpen: true,
          authorisedForUnit: true,
          authenticated: true,
        );
        expect(
          (decision as OwnerMovementRefused).refusal.reason,
          OwnerLedgerRefusalReason.attributionMismatch,
        );

        // And nothing was written.
        final count = await db
            .customSelect('SELECT COUNT(*) AS n FROM owner_ledger_entries')
            .getSingle();
        expect(count.read<int>('n'), 0);
      },
    );

    test(
      'a person not approved for NC is refused with its own reason',
      () async {
        final decision = await owners.evaluate(
          draft(
            type: OwnerMovementType.ncConsumption,
            familyMemberId: 'fam-a3',
            ownerId: null,
          ),
          periodOpen: true,
          authorisedForUnit: true,
          authenticated: true,
        );
        expect(
          (decision as OwnerMovementRefused).refusal.reason,
          OwnerLedgerRefusalReason.consumerNotApprovedForNc,
        );
      },
    );

    test(
      'a closed period, an unknown owner and no authority each refuse',
      () async {
        Future<OwnerLedgerRefusalReason> refusalOf(
          OwnerMovementDraft d, {
          bool periodOpen = true,
          bool authorised = true,
          bool authenticated = true,
        }) async =>
            ((await owners.evaluate(
                      d,
                      periodOpen: periodOpen,
                      authorisedForUnit: authorised,
                      authenticated: authenticated,
                    ))
                    as OwnerMovementRefused)
                .refusal
                .reason;

        expect(
          await refusalOf(draft(), periodOpen: false),
          OwnerLedgerRefusalReason.periodClosed,
        );
        expect(
          await refusalOf(draft(), authorised: false),
          OwnerLedgerRefusalReason.notAuthorisedForUnit,
        );
        expect(
          await refusalOf(draft(), authenticated: false),
          OwnerLedgerRefusalReason.notAuthenticated,
        );
        expect(
          await refusalOf(draft(ownerId: 'nobody')),
          OwnerLedgerRefusalReason.unknownOwner,
        );
      },
    );

    test('an opening balance without a direction is refused', () async {
      final decision = await owners.evaluate(
        draft(type: OwnerMovementType.openingBalance),
        periodOpen: true,
        authorisedForUnit: true,
        authenticated: true,
      );
      expect(
        (decision as OwnerMovementRefused).refusal.reason,
        OwnerLedgerRefusalReason.directionRequired,
      );
    });

    test('an adjustment without a reason is refused', () async {
      final decision = await owners.evaluate(
        draft(
          type: OwnerMovementType.manualAdjustment,
          direction: OwnerLedgerDirection.credit,
          reason: '   ',
        ),
        periodOpen: true,
        authorisedForUnit: true,
        authenticated: true,
      );
      expect(
        (decision as OwnerMovementRefused).refusal.reason,
        OwnerLedgerRefusalReason.reasonRequired,
      );
    });

    test(
      'no refusal message carries an exception, a table name or a code',
      () async {
        final refusals = <String>[];
        for (final d in [
          draft(ownerId: 'nobody'),
          draft(type: OwnerMovementType.openingBalance),
          draft(
            type: OwnerMovementType.manualAdjustment,
            direction: OwnerLedgerDirection.credit,
          ),
          draft(type: OwnerMovementType.ncConsumption, ownerId: null),
          draft(
            type: OwnerMovementType.ncConsumption,
            familyMemberId: 'fam-a3',
            ownerId: null,
          ),
          draft(
            type: OwnerMovementType.ncConsumption,
            familyMemberId: 'fam-a2',
            ownerId: _ownerB,
          ),
          draft(paise: -1),
        ]) {
          final decision = await owners.evaluate(
            d,
            periodOpen: false,
            authorisedForUnit: true,
            authenticated: true,
          );
          if (decision is OwnerMovementRefused) {
            refusals.add(decision.refusal.message);
          }
        }
        expect(refusals, isNotEmpty);
        for (final message in refusals) {
          for (final leak in [
            'KM0',
            'Exception',
            'owner_ledger_entries',
            'SQL',
            'null',
            'Sqlite',
            '_minor',
          ]) {
            expect(
              message,
              isNot(contains(leak)),
              reason: 'a refusal is a sentence a person can act on: "$message"',
            );
          }
        }
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('one queued intent per document (D-125)', () {
    test(
      'a correction rewrites the queued create rather than adding an update',
      () async {
        final entry = await record(draft());

        final refusal = await owners.updateLocally(
          entry.id,
          amount: Money.fromPaise(4500000),
          businessDate: june,
          actorUserId: 'user-1',
          baseRowVersion: 1,
          mutationId: const Uuid().v4(),
          now: now,
        );
        expect(refusal, isNull);

        final queued = await (db.select(
          db.syncOutbox,
        )..where((o) => o.entityId.equals(entry.id))).get();
        expect(
          queued,
          hasLength(1),
          reason:
              'a correction to a movement whose create is still queued must not '
              'produce a second intent that arrives first and is refused (D-125)',
        );
        expect(queued.single.op, MutationOp.create.name);
        expect(
          queued.single.baseRowVersion,
          isNull,
          reason: 'a create stays a create; there is nothing to be based on',
        );

        final payload =
            jsonDecode(queued.single.payload) as Map<String, Object?>;
        expect(
          payload['p_amount_minor'],
          4500000,
          reason: "the payload is the operator's current intent",
        );
      },
    );

    test('two corrections before either syncs leave one intent', () async {
      final entry = await record(draft());
      await accept(entry.id);

      await owners.updateLocally(
        entry.id,
        amount: Money.fromPaise(4500000),
        businessDate: june,
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );
      await owners.updateLocally(
        entry.id,
        amount: Money.fromPaise(4000000),
        businessDate: june,
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );

      final queued =
          await (db.select(db.syncOutbox)..where(
                (o) =>
                    o.entityId.equals(entry.id) &
                    o.status.isNotValue(OutboxStatus.done.name),
              ))
              .get();
      expect(queued, hasLength(1));
      final payload = jsonDecode(queued.single.payload) as Map<String, Object?>;
      expect(payload['p_amount_minor'], 4000000);
    });

    test(
      'a correction re-applied after a conflict carries the version it was made against (D-130)',
      () async {
        // The sequence that was unresolvable through the shipped revenue path: refused on
        // v1, operator reviews the latest, corrects again against v2 — and the coalesced
        // intent kept v1, so it was refused as stale for ever.
        final entry = await record(draft());
        await accept(entry.id);

        await owners.updateLocally(
          entry.id,
          amount: Money.fromPaise(4500000),
          businessDate: june,
          actorUserId: 'user-1',
          baseRowVersion: 1,
          mutationId: const Uuid().v4(),
          now: now,
        );

        // The server refuses **the correction** as stale; the record is now at v2.
        //
        // Targeted at the update intent rather than at every row for this movement: the
        // create is already done, and putting it back to `conflict` would model a queue
        // state nothing can produce.
        await (db.update(db.syncOutbox)..where(
              (o) =>
                  o.entityId.equals(entry.id) &
                  o.op.equals(MutationOp.update.name),
            ))
            .write(
              SyncOutboxCompanion(status: Value(OutboxStatus.conflict.name)),
            );
        await owners.reconcileAcceptance(
          OwnerMovementAcceptance(entryId: entry.id, rowVersion: 2),
        );

        // The operator corrects again, against what the record now says.
        await owners.updateLocally(
          entry.id,
          amount: Money.fromPaise(4200000),
          businessDate: june,
          actorUserId: 'user-1',
          baseRowVersion: 2,
          mutationId: const Uuid().v4(),
          now: now,
        );

        final queued =
            await (db.select(db.syncOutbox)..where(
                  (o) =>
                      o.entityId.equals(entry.id) &
                      o.status.isNotValue(OutboxStatus.done.name),
                ))
                .getSingle();
        expect(
          queued.baseRowVersion,
          2,
          reason:
              'carrying 1 again would be refused on the version it was already '
              'refused on — for ever (D-130)',
        );
        final payload = jsonDecode(queued.payload) as Map<String, Object?>;
        expect(payload['p_base_row_version'], 2);
        expect(
          queued.status,
          OutboxStatus.pending.name,
          reason: 'the operator has just acted; it is due now',
        );
      },
    );

    test('a void replaces whatever was queued', () async {
      final entry = await record(draft());
      await accept(entry.id);
      await owners.updateLocally(
        entry.id,
        amount: Money.fromPaise(4500000),
        businessDate: june,
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );

      final refusal = await owners.voidLocally(
        entry.id,
        reason: 'recorded twice',
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );
      expect(refusal, isNull);

      final queued =
          await (db.select(db.syncOutbox)..where(
                (o) =>
                    o.entityId.equals(entry.id) &
                    o.status.isNotValue(OutboxStatus.done.name),
              ))
              .getSingle();
      expect(
        queued.op,
        MutationOp.void_.name,
        reason:
            'sending both would ask the server to correct a movement and then '
            'throw the correction away',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('void refuses rather than throws (D-129)', () {
    test('a blank reason, in every shape of whitespace', () async {
      final entry = await record(draft());
      await accept(entry.id);

      for (final blank in ['', '   ', '\t', '\n', ' \t\r\n ']) {
        final refusal = await owners.voidLocally(
          entry.id,
          reason: blank,
          actorUserId: 'user-1',
          baseRowVersion: 1,
          mutationId: const Uuid().v4(),
          now: now,
        );
        expect(
          refusal?.reason,
          OwnerLedgerRefusalReason.voidReasonRequired,
          reason: 'spec §14.1 — whitespace is not a reason',
        );
      }
    });

    test('a movement whose create is still queued cannot be voided', () async {
      final entry = await record(draft());
      final refusal = await owners.voidLocally(
        entry.id,
        reason: 'entered twice',
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );
      expect(refusal?.reason, OwnerLedgerRefusalReason.notYetOnTheServer);
    });

    test('an already-voided movement, and an unknown one', () async {
      final entry = await record(draft());
      await accept(entry.id);
      await owners.voidLocally(
        entry.id,
        reason: 'entered twice',
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );

      expect(
        (await owners.voidLocally(
          entry.id,
          reason: 'again',
          actorUserId: 'user-1',
          baseRowVersion: 2,
          mutationId: const Uuid().v4(),
          now: now,
        ))?.reason,
        OwnerLedgerRefusalReason.alreadyVoided,
      );
      expect(
        (await owners.voidLocally(
          'no-such-movement',
          reason: 'x',
          actorUserId: 'user-1',
          baseRowVersion: 1,
          mutationId: const Uuid().v4(),
          now: now,
        ))?.reason,
        OwnerLedgerRefusalReason.unknownMovement,
      );
    });

    test('a voided movement cannot then be corrected', () async {
      final entry = await record(draft());
      await accept(entry.id);
      await owners.voidLocally(
        entry.id,
        reason: 'entered twice',
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );
      expect(
        (await owners.updateLocally(
          entry.id,
          amount: Money.fromPaise(1),
          businessDate: june,
          actorUserId: 'user-1',
          baseRowVersion: 2,
          mutationId: const Uuid().v4(),
          now: now,
        ))?.reason,
        OwnerLedgerRefusalReason.alreadyVoided,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('reconciliation writes only what the server restated (D-072a)', () {
    test('an update answer does not erase the transaction number', () async {
      final entry = await record(draft());
      await accept(entry.id, number: 'KI-OWN-26-27-000042');

      // `owner_movement_update` returns a row version and no number, exactly as
      // `expense_update` does — and writing every field back is what erased the number on
      // every expense edit until D-072a caught it.
      await owners.reconcileAcceptance(
        OwnerMovementAcceptance(entryId: entry.id, rowVersion: 2),
      );

      final saved = await owners.load(entry.id);
      expect(saved!.txnNumber, 'KI-OWN-26-27-000042');
      expect(saved.rowVersion, 2);
    });

    test(
      'the canonical owner is written back when the server states one',
      () async {
        final entry = await record(
          draft(
            type: OwnerMovementType.ncConsumption,
            familyMemberId: 'fam-a1',
          ),
        );
        await owners.reconcileAcceptance(
          OwnerMovementAcceptance(
            entryId: entry.id,
            rowVersion: 1,
            txnNumber: 'KI-OWN-26-27-000001',
            financialYear: '26-27',
            ownerId: _ownerA,
            businessDateSource: 'derived',
          ),
        );
        final saved = await owners.load(entry.id);
        expect(saved!.ownerId, _ownerA);
        expect(saved.businessDateSource, BusinessDateSource.derived);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('sync state is derived from the outbox, one way (D-131)', () {
    test('pending, then synced once the queue entry is done', () async {
      final entry = await record(draft());
      expect(
        await owners.watchSyncState(entry.id).first,
        SyncState.pendingSync,
      );

      await (db.update(db.syncOutbox)
            ..where((o) => o.entityId.equals(entry.id)))
          .write(SyncOutboxCompanion(status: Value(OutboxStatus.done.name)));
      expect(await owners.watchSyncState(entry.id).first, SyncState.synced);
    });

    test('a conflict reaches the surface as a conflict', () async {
      final entry = await record(draft());
      await (db.update(
        db.syncOutbox,
      )..where((o) => o.entityId.equals(entry.id))).write(
        SyncOutboxCompanion(status: Value(OutboxStatus.conflict.name)),
      );
      expect(await owners.watchSyncState(entry.id).first, SyncState.conflict);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the ledger query (§10, D-121)', () {
    test('scope is applied first and no filter can drop it', () async {
      await record(draft(businessUnitId: _hki));
      await record(
        draft(
          businessUnitId: _ccr,
          type: OwnerMovementType.ncConsumption,
          familyMemberId: 'fam-a1',
          ownerId: null,
          paise: 2000000,
        ),
      );

      final scoped = await owners.query(
        _Query(businessUnitIds: const {_ccr}, includeVoided: true),
      );
      expect(scoped, hasLength(1));
      expect(scoped.single.businessUnitId, _ccr);
    });

    test('a quarantined movement is excluded before any filter', () async {
      final entry = await record(draft());
      await db.customStatement(
        "UPDATE owner_ledger_entries SET scope_revoked_at = '${now.toIso8601String()}' "
        "WHERE id = '${entry.id}'",
      );

      expect(await owners.query(_Query(includeVoided: true)), isEmpty);
      expect(
        await owners.query(_Query(includeVoided: true, ownerId: _ownerA)),
        isEmpty,
      );
      expect(
        await owners.listRetainedAfterRevocation(actorUserId: 'user-1'),
        hasLength(1),
        reason: 'its own actor still reaches it through the dedicated path',
      );
      expect(
        await owners.listRetainedAfterRevocation(actorUserId: 'user-2'),
        isEmpty,
        reason:
            "another person on a shared workstation never inherits somebody's "
            'unsent work (D-074)',
      );
    });

    test('the date range filters the business date, and paging is stable', () async {
      // Dates filter on the **business date**, never the capture instant: a withdrawal
      // recorded at 02:00 belongs to the previous trading day, and filtering on
      // `captured_at` because it suits SQL would put it in the wrong month of a
      // statement (D-067, D-121). Every fixture here shares one `capturedAt`, so a
      // filter that used it would return all four.
      for (final day in [10, 15, 20, 25]) {
        await record(
          draft(date: BusinessDate.of(2026, 6, day), paise: day * 100000),
        );
      }

      final window = await owners.query(
        _Query(
          from: BusinessDate.of(2026, 6, 12),
          to: BusinessDate.of(2026, 6, 22),
        ),
      );
      expect(window.map((e) => e.businessDate.day), [20, 15]);

      // Paging is deterministic across a boundary — the `id` tie-break is what stops a
      // row being shown twice or skipped.
      final firstPage = await owners.query(_Query(limit: 2));
      final secondPage = await owners.query(_Query(limit: 2, offset: 2));
      final ids = [
        ...firstPage.map((e) => e.id),
        ...secondPage.map((e) => e.id),
      ];
      expect(ids.toSet(), hasLength(4));
    });

    test('the movement type and the property each narrow', () async {
      await record(draft(businessUnitId: _hki, paise: 5000000));
      await record(
        draft(
          businessUnitId: _ccr,
          type: OwnerMovementType.ncConsumption,
          familyMemberId: 'fam-a1',
          ownerId: null,
          paise: 2000000,
        ),
      );

      final withdrawals = await owners.query(
        _Query(movementType: OwnerMovementType.withdrawal),
      );
      expect(withdrawals.single.amount.paise, 5000000);

      final atCcr = await owners.query(_Query(businessUnitId: _ccr));
      expect(atCcr.single.movementType, OwnerMovementType.ncConsumption);
    });

    test('voided movements are excluded unless asked for', () async {
      final entry = await record(draft());
      await accept(entry.id);
      await owners.voidLocally(
        entry.id,
        reason: 'entered twice',
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );

      expect(await owners.query(_Query()), isEmpty);
      expect(await owners.query(_Query(includeVoided: true)), hasLength(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // §40 and §41 — the invariant this slice is judged against
  // ═══════════════════════════════════════════════════════════════════════════
  group('an owner movement changes no business figure (§40, §41)', () {
    /// The whole P&L, from the canonical facts this device holds.
    Future<PnlResult> pnl(String unitId) async {
      final range = MonthPeriod(2026, 6);
      final revenueTotals = await revenue.contributionTotals(
        RevenueContributionQuery(periodKey: '2026-06', businessUnitId: unitId),
      );
      final expenseTotals = await expenses.contributionTotals(
        ExpenseContributionQuery(periodKey: '2026-06', businessUnitId: unitId),
      );
      final outcome = Pnl.compute(
        period: range,
        revenue: SideAvailable(revenueTotals),
        expenses: SideAvailable(expenseTotals),
        businessUnitId: unitId,
      );
      return (outcome as PnlComputed).result;
    }

    Future<void> givenAnAcceptedExpense() async {
      final expense = simpleExpense();
      await expenses.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await expenses.reconcileAcceptance(
        ExpenseAcceptance(
          expenseId: expense.id,
          rowVersion: 1,
          txnNumber: 'KI-EXP-26-27-000001',
          financialYear: 2026,
          serverUpdatedAt: now,
        ),
      );
    }

    test(
      'a Rs 50,000 owner withdrawal moves no expense figure and no Operating Profit',
      () async {
        await givenAnAcceptedExpense();

        final unit = simpleExpense().allocations.single.businessUnitId;
        final before = await pnl(unit);
        final expensesBefore = before.expenses.paise;
        final contributionsBefore = before.expenseContributions;

        // The act §40 names, recorded and accepted.
        final entry = await record(draft(businessUnitId: unit, paise: 5000000));
        await accept(entry.id);

        final after = await pnl(unit);

        expect(
          after.expenses.paise,
          expensesBefore,
          reason:
              'a withdrawal is not a business expense — Rs 50,000 out of the '
              'owner account must not reduce Operating Profit by a paisa (§4, §40)',
        );
        expect(
          after.expenseContributions,
          contributionsBefore,
          reason:
              'and it must not create a contribution row either: equal totals over '
              'a different number of rows would be the same figure by luck',
        );
        expect(after.operatingProfit.paise, before.operatingProfit.paise);
        expect(after.grossSales.paise, before.grossSales.paise);
        expect(after.gst.paise, before.gst.paise);
        expect(after.netSales.paise, before.netSales.paise);

        // And the owner account did move, so the test is about non-interference rather
        // than about nothing having happened.
        final ledger = await owners.query(_Query(ownerId: _ownerA));
        expect(
          OwnerLedgerTotals.of(_ownerA, ledger).withdrawals.paise,
          5000000,
        );
      },
    );

    test(
      'a Rs 20,000 family NC creates no revenue and no expense contribution (§41)',
      () async {
        await givenAnAcceptedExpense();
        final unit = simpleExpense().allocations.single.businessUnitId;

        final before = await pnl(unit);

        // Owner A's own bill, spouse's and son's — the §18 aggregation, recorded through
        // the Owner Ledger and through nothing else.
        for (final (person, paise) in [
          ('fam-a-self', 800000),
          ('fam-a1', 700000),
          ('fam-a2', 500000),
        ]) {
          final entry = await record(
            draft(
              businessUnitId: unit,
              type: OwnerMovementType.ncConsumption,
              familyMemberId: person,
              ownerId: null,
              paise: paise,
            ),
          );
          await accept(entry.id, number: 'KI-OWN-26-27-$person');
        }

        final after = await pnl(unit);

        expect(
          after.grossSales.paise,
          before.grossSales.paise,
          reason:
              'NC recorded in the Owner Ledger must not inflate Gross Sales — '
              'entering it as Restaurant revenue would have added gross, GST and '
              'net at 5% inclusive (§41)',
        );
        expect(after.gst.paise, before.gst.paise);
        expect(after.netSales.paise, before.netSales.paise);
        expect(after.revenueContributions, before.revenueContributions);

        expect(
          after.expenses.paise,
          before.expenses.paise,
          reason: 'and it is not an expense either (§7 of the addendum)',
        );
        expect(after.expenseContributions, before.expenseContributions);
        expect(after.operatingProfit.paise, before.operatingProfit.paise);

        // The owner account carries all three, aggregated to Owner A (§18).
        final ledger = await owners.query(_Query(ownerId: _ownerA));
        expect(
          OwnerLedgerTotals.of(_ownerA, ledger).ncConsumption.paise,
          2000000,
        );
        expect(
          OwnerLedgerTotals.of(_ownerB, ledger).ncConsumption,
          Money.zero,
          reason: 'and none of it to Owner B',
        );
      },
    );

    test('the Owner Ledger writes to no expense or revenue table', () async {
      // Structural rather than incidental: whatever the write path does, the two
      // financial engines' tables are untouched — counted directly rather than through
      // the reporting projections, so a filter cannot hide a row.
      Future<int> count(String table) async =>
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n');

      final before = {
        for (final t in [
          'expenses',
          'expense_allocations',
          'expense_period_allocations',
          'revenue_entries',
          'revenue_components',
        ])
          t: await count(t),
      };

      final entry = await record(draft());
      await accept(entry.id);
      await owners.updateLocally(
        entry.id,
        amount: Money.fromPaise(4500000),
        businessDate: june,
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );
      await owners.voidLocally(
        entry.id,
        reason: 'recorded twice',
        actorUserId: 'user-1',
        baseRowVersion: 1,
        mutationId: const Uuid().v4(),
        now: now,
      );

      for (final entry in before.entries) {
        expect(
          await count(entry.key),
          entry.value,
          reason: '${entry.key} was touched by an owner-account write',
        );
      }
    });

    test(
      'a correction of Rs 5,000 moves the owner position and nothing else',
      () async {
        await givenAnAcceptedExpense();
        final unit = simpleExpense().allocations.single.businessUnitId;
        final before = await pnl(unit);

        final entry = await record(draft(businessUnitId: unit, paise: 5000000));
        await accept(entry.id);
        await owners.updateLocally(
          entry.id,
          amount: Money.fromPaise(4500000),
          businessDate: june,
          actorUserId: 'user-1',
          baseRowVersion: 1,
          mutationId: const Uuid().v4(),
          now: now,
        );

        final ledger = await owners.query(_Query(ownerId: _ownerA));
        expect(
          OwnerLedgerTotals.of(_ownerA, ledger).withdrawals.paise,
          4500000,
          reason: 'exactly Rs 5,000 less (§29)',
        );

        final after = await pnl(unit);
        expect(after.expenses.paise, before.expenses.paise);
        expect(after.operatingProfit.paise, before.operatingProfit.paise);
      },
    );
  });
}

/// A plain query, so the tests exercise the interface the presentation will implement
/// rather than a convenience the repository grew for them.
final class _Query implements OwnerLedgerQuery {
  const _Query({
    this.businessUnitIds,
    this.ownerId,
    this.businessUnitId,
    this.movementType,
    this.from,
    this.to,
    this.includeVoided = false,
    this.limit = 50,
    this.offset = 0,
  });

  @override
  final Set<String>? businessUnitIds;
  @override
  final String? ownerId;
  @override
  final String? businessUnitId;
  @override
  final OwnerMovementType? movementType;
  @override
  final BusinessDate? from;
  @override
  final BusinessDate? to;
  @override
  final bool includeVoided;
  @override
  final int limit;
  @override
  final int offset;
}
