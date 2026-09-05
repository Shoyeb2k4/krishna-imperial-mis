/// The revenue correction and void path (Slice 10).
///
/// The guiding rule, and what each group here is defending:
///
/// > Correct revenue through auditable mutation. Never silently rewrite financial
/// > history, never auto-merge a financial conflict, and never destructively delete a
/// > revenue document.
///
/// The substance is the **one-intent-per-document** discipline. An expense edit queues a
/// fresh update intent every time, which leaves two reachable failure modes: an update
/// delivered before the create it corrects (refused `KM015`, terminal, for a legitimate
/// correction), and two pending edits sharing one base version (the second conflicts with
/// a version nobody ever saw). Revenue coalesces instead, and these tests are what hold
/// that in place.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/revenue_parity_vectors.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _userA = 'user-a';
const _userB = 'user-b';

String _unitOf(String category) =>
    category == vCategoryRoom || category == vCategoryBanquet ? _hki : _ccr;

AuthoritySnapshot _authority({
  String user = _userA,
  Set<String> units = const {_ccr, _hki},
}) => AuthoritySnapshot(
  userId: user,
  orgId: _org,
  grants: [
    for (final unit in units) ...[
      CapabilityGrant(Capability.revenueCreate, businessUnitId: unit),
      CapabilityGrant(Capability.revenueEdit, businessUnitId: unit),
      CapabilityGrant(Capability.revenueVoid, businessUnitId: unit),
    ],
  ],
  resolvedAt: DateTime.now().toUtc(),
);

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late RevenueRepository repository;
  late RevenueTaxRepository tax;
  var seq = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    seq = 0;
    tax = RevenueTaxRepository(db);
    repository = RevenueRepository(db, tax: tax);

    for (final unit in const [(_ccr, 'CCR'), (_hki, 'HKI')]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [unit.$1, unit.$2, unit.$2],
      );
    }
    for (final c in const [
      (vCategoryRestaurant, _ccr, 'RESTAURANT'),
      (vCategoryNandbhog, _ccr, 'NANDBHOG'),
      (vCategoryRoom, _hki, 'ROOM'),
      (vCategoryBanquet, _hki, 'BANQUET'),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, 1, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$3],
      );
    }

    for (final v in verifiedBaseline) {
      await db.customStatement(
        'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
        'rate_basis_points, treatment, effective_from, effective_to, '
        'input_basis, value_band_id, supply_subtype_id, premises_status_code, '
        "created_by, created_at, row_version, updated_at) "
        "VALUES (?, '$_org', ?, ?, ?, ?, ?, ?, ?, ?, ?, 'u', "
        "'2026-04-01T00:00:00.000Z', 1, '2026-04-01T00:00:00.000Z')",
        [
          v.id,
          v.category,
          v.rateBp,
          v.treatment.name,
          v.from,
          v.to,
          v.basis?.wireName,
          v.bandId,
          v.subtypeId,
          v.premisesStatus,
        ],
      );
    }
    for (final user in const [_userA, _userB]) {
      for (final unit in const [_ccr, _hki]) {
        await db.customStatement(
          'INSERT OR REPLACE INTO revenue_config_snapshots (user_id, org_id, '
          'business_unit_id, status, datasets, generation, confirmed_at, '
          'updated_at) '
          "VALUES (?, '$_org', ?, 'complete', "
          "'bands,rules,statuses,subtypes', '900', ?, ?)",
          [
            user,
            unit,
            DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      }
    }
  });

  tearDown(() => db.close());

  RevenueEntryDraft draft({
    String? id,
    String category = vCategoryRestaurant,
    List<int> amounts = const [10000000],
    String date = '2026-06-15',
    String? notes,
  }) {
    seq++;
    final entryId = id ?? 'entry-$seq';
    return RevenueEntryDraft(
      id: entryId,
      businessUnitId: _unitOf(category),
      revenueCategoryId: category,
      businessDate: vDate(date),
      capturedAt: DateTime.now().toUtc(),
      notes: notes,
      components: [
        for (var i = 0; i < amounts.length; i++)
          RevenueComponentDraft(
            id: '$entryId-c$i',
            enteredAmount: Money.fromPaise(amounts[i]),
          ),
      ],
    );
  }

  Future<RevenueEntry> create(
    RevenueEntryDraft d, {
    AuthoritySnapshot? authority,
    String? mutationId,
  }) async {
    final who = authority ?? _authority();
    final decision = await repository.evaluate(d, authority: who);
    expect(
      decision,
      isA<RevenueCreatePermitted>(),
      reason: decision is RevenueCreateRefused
          ? decision.refusal.toString()
          : null,
    );
    return repository.createLocally(
      d,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: who.userId,
      orgId: _org,
      mutationId: mutationId ?? 'mut-${d.id}',
      now: DateTime.now().toUtc(),
    );
  }

  Future<RevenueEntry> correct(
    RevenueEntryDraft d, {
    required int baseRowVersion,
    AuthoritySnapshot? authority,
    String? mutationId,
  }) async {
    final who = authority ?? _authority();
    final decision = await repository.evaluate(d, authority: who);
    expect(
      decision,
      isA<RevenueCreatePermitted>(),
      reason: decision is RevenueCreateRefused
          ? decision.refusal.toString()
          : null,
    );
    return repository.updateLocally(
      d,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: who.userId,
      orgId: _org,
      baseRowVersion: baseRowVersion,
      mutationId:
          mutationId ?? 'mut-edit-${DateTime.now().microsecondsSinceEpoch}',
      now: DateTime.now().toUtc(),
    );
  }

  Future<List<SyncOutboxRow>> outbox([String? entityId]) async {
    final all = await db.select(db.syncOutbox).get();
    return entityId == null
        ? all
        : all.where((o) => o.entityId == entityId).toList();
  }

  /// Marks an entry as the server accepted it, so the next correction is an update
  /// rather than a rewrite of a queued create.
  Future<void> accept(String entryId, {int rowVersion = 1}) async {
    await repository.reconcileAcceptance(
      RevenueAcceptance(
        entryId: entryId,
        rowVersion: rowVersion,
        txnNumber: 'KI-REV-26-27-000001',
        financialYear: '2026-27',
        serverUpdatedAt: DateTime.now().toUtc(),
      ),
    );
    await (db.update(db.syncOutbox)..where((o) => o.entityId.equals(entryId)))
        .write(const SyncOutboxCompanion(status: Value('done')));
  }

  group('one queued intent per document', () {
    test('correcting a sale the server has not seen rewrites the create', () async {
      final d = draft(amounts: [10000000]);
      final entry = await create(d);

      final before = await outbox(entry.id);
      expect(before.single.op, MutationOp.create.name);
      final originalMutationId = before.single.mutationId;
      final originalActor = before.single.actorUserId;
      final originalCreatedAt = before.single.createdAt;

      await correct(
        draft(id: entry.id, amounts: [12000000]),
        baseRowVersion: entry.rowVersion,
      );

      final after = await outbox(entry.id);
      // Still one intent. An update delivered before its own create would be refused
      // KM015 - a legitimate correction turned into a terminal rejection.
      expect(after, hasLength(1));
      expect(after.single.op, MutationOp.create.name);
      // Identity, ownership and creation time survive: idempotency (D-004), the actor
      // filter (D-050) and the retention rule (D-074) all key on them.
      expect(after.single.mutationId, originalMutationId);
      expect(after.single.actorUserId, originalActor);
      expect(after.single.createdAt, originalCreatedAt);
      // What changed is the payload - the operator's current intent.
      expect(after.single.payload, contains('12000000'));
      expect(after.single.payload, isNot(contains('10000000')));
    });

    test(
      'correcting an accepted sale queues an update on its base version',
      () async {
        final entry = await create(draft());
        await accept(entry.id, rowVersion: 4);

        await correct(
          draft(id: entry.id, amounts: [12000000]),
          baseRowVersion: 4,
        );

        final queued = (await outbox(
          entry.id,
        )).where((o) => o.status != 'done').toList();
        expect(queued, hasLength(1));
        expect(queued.single.op, MutationOp.update.name);
        expect(queued.single.baseRowVersion, 4);
      },
    );

    test(
      'two corrections before either syncs stay one intent on one base version',
      () async {
        final entry = await create(draft());
        await accept(entry.id, rowVersion: 4);

        await correct(
          draft(id: entry.id, amounts: [11000000]),
          baseRowVersion: 4,
        );
        await correct(
          draft(id: entry.id, amounts: [13000000]),
          baseRowVersion: 4,
        );

        final queued = (await outbox(
          entry.id,
        )).where((o) => o.status != 'done').toList();
        // Not two intents sharing one base version, which is how the second conflicts
        // with a version its author never saw.
        expect(queued, hasLength(1));
        expect(queued.single.baseRowVersion, 4);
        expect(queued.single.payload, contains('13000000'));
      },
    );

    test(
      'a correction after a conflict carries the version it was made against',
      () async {
        // The defect the two-client acceptance found, pinned here so it cannot come back
        // without the live suite.
        //
        // A refused correction leaves a conflicted intent based on version N. The operator
        // reviews the latest, the document is now at N+1, and they correct it again. If the
        // rewritten intent kept N, the server would refuse it as stale for ever and the
        // conflict would be unresolvable through the shipped path.
        final entry = await create(draft());
        await accept(entry.id, rowVersion: 2);

        await correct(
          draft(id: entry.id, amounts: [12000000]),
          baseRowVersion: 2,
        );
        await (db.update(db.syncOutbox)..where(
              (o) => o.entityId.equals(entry.id) & o.status.equals('pending'),
            ))
            .write(const SyncOutboxCompanion(status: Value('conflict')));

        // Review latest brings the document to version 5, and a fresh correction is made
        // against that.
        await correct(
          draft(id: entry.id, amounts: [15000000]),
          baseRowVersion: 5,
        );

        final queued = (await outbox(
          entry.id,
        )).where((o) => o.status != 'done').single;
        expect(queued.op, MutationOp.update.name);
        expect(
          queued.baseRowVersion,
          5,
          reason:
              'the version the operator was looking at, not the refused one',
        );
        expect(queued.status, 'pending', reason: 'and it is deliverable again');
      },
    );

    test('a rewritten create still carries no base version', () async {
      // A create establishes a new identity and has nothing to be based on (D-021).
      final entry = await create(draft());
      await correct(
        draft(id: entry.id, amounts: [12000000]),
        baseRowVersion: entry.rowVersion,
      );

      final queued = (await outbox(entry.id)).single;
      expect(queued.op, MutationOp.create.name);
      expect(queued.baseRowVersion, isNull);
    });

    test(
      'a rewritten intent is due immediately, not after an earlier backoff',
      () async {
        final entry = await create(draft());
        final future = DateTime.now().toUtc().add(const Duration(hours: 3));
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.entityId.equals(entry.id))).write(
          SyncOutboxCompanion(
            status: const Value('failed'),
            nextAttemptAt: Value(future),
            lastError: const Value('network'),
          ),
        );

        await correct(
          draft(id: entry.id, amounts: [12000000]),
          baseRowVersion: entry.rowVersion,
        );

        final queued = (await outbox(entry.id)).single;
        expect(queued.status, 'pending');
        expect(queued.nextAttemptAt.isBefore(future), isTrue);
        expect(queued.lastError, isNull);
      },
    );
  });

  group('the correction itself', () {
    test('the tax is re-resolved and the figures re-derived', () async {
      final entry = await create(draft(amounts: [10000000]));
      final corrected = await correct(
        draft(id: entry.id, amounts: [21000000]),
        baseRowVersion: entry.rowVersion,
      );

      // 5% inclusive on 2,10,000.00: tax = round_half_up(gross * 500 / 10500).
      expect(corrected.gross.paise, 21000000);
      expect(corrected.tax.paise, 1000000);
      expect(corrected.net.paise, 20000000);
      expect(corrected.gross.paise - corrected.tax.paise, corrected.net.paise);
    });

    test('the transaction number survives a correction', () async {
      final entry = await create(draft());
      await accept(entry.id, rowVersion: 2);

      await correct(
        draft(id: entry.id, amounts: [12000000]),
        baseRowVersion: 2,
      );

      final reloaded = await repository.load(entry.id);
      // D-072a: writing every field back on reconciliation erased the server-issued
      // number on every expense edit. The number belongs to the document.
      expect(reloaded!.txnNumber, 'KI-REV-26-27-000001');
    });

    test('the business unit and category cannot be moved by a correction', () async {
      final entry = await create(draft(category: vCategoryRestaurant));

      // A draft claiming a different property, as a modified client might send.
      await correct(
        RevenueEntryDraft(
          id: entry.id,
          businessUnitId: _hki,
          revenueCategoryId: vCategoryRoom,
          businessDate: vDate('2026-06-15'),
          capturedAt: DateTime.now().toUtc(),
          components: [
            RevenueComponentDraft(
              id: '${entry.id}-c0',
              enteredAmount: Money.fromPaise(10000000),
            ),
          ],
        ),
        baseRowVersion: entry.rowVersion,
      );

      final reloaded = await repository.load(entry.id);
      // Locally too. A correction that moved revenue between properties would be a
      // scope transfer wearing a correction's clothes, and the server refuses it.
      expect(reloaded!.businessUnitId, _ccr);
      expect(reloaded.revenueCategoryId, vCategoryRestaurant);
    });

    test(
      'the capture instant is the document\'s and is not restamped',
      () async {
        final entry = await create(draft());
        final captured = entry.capturedAt;
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await correct(
          draft(id: entry.id, amounts: [12000000]),
          baseRowVersion: entry.rowVersion,
        );

        final reloaded = await repository.load(entry.id);
        expect(reloaded!.capturedAt, captured);
      },
    );

    test(
      'the business date may be corrected, and the period key follows it',
      () async {
        final entry = await create(draft(date: '2026-06-15'));
        await correct(
          draft(id: entry.id, date: '2026-05-31'),
          baseRowVersion: entry.rowVersion,
        );

        final row = await (db.select(
          db.revenueEntries,
        )..where((e) => e.id.equals(entry.id))).getSingle();
        expect(row.businessDate, '2026-05-31');
        // Derived, stored, and never recomputed at read time (D-019).
        expect(row.pnlPeriodKey, '2026-05');
      },
    );

    test('a voided sale cannot be corrected', () async {
      final entry = await create(draft());
      await accept(entry.id, rowVersion: 2);
      await repository.voidLocally(
        entryId: entry.id,
        reason: 'duplicate of the evening summary',
        actorUserId: _userA,
        baseRowVersion: 2,
        mutationId: 'mut-void-1',
        now: DateTime.now().toUtc(),
      );

      await expectLater(
        correct(draft(id: entry.id, amounts: [1]), baseRowVersion: 2),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'correcting a sale that is not here at all throws rather than inventing one',
      () async {
        await expectLater(
          correct(draft(id: 'never-existed'), baseRowVersion: 1),
          throwsA(isA<StateError>()),
        );
        expect(await db.select(db.revenueEntries).get(), isEmpty);
      },
    );
  });

  group('void', () {
    test(
      'a void is queued with its reason and its base version, and deletes nothing',
      () async {
        final entry = await create(draft());
        await accept(entry.id, rowVersion: 3);

        final refusal = await repository.voidLocally(
          entryId: entry.id,
          reason: 'entered twice',
          actorUserId: _userA,
          baseRowVersion: 3,
          mutationId: 'mut-void-1',
          now: DateTime.now().toUtc(),
        );
        expect(refusal, isNull);

        final queued = (await outbox(
          entry.id,
        )).where((o) => o.status != 'done').single;
        expect(queued.op, MutationOp.void_.name);
        expect(queued.baseRowVersion, 3);
        expect(queued.payload, contains('entered twice'));

        // Nothing destroyed: the document and its components are still here (D-006).
        final reloaded = await repository.load(entry.id);
        expect(reloaded, isNotNull);
        expect(reloaded!.components, isNotEmpty);
        expect(reloaded.voidedAt, isNotNull);
        expect(reloaded.voidReason, 'entered twice');
      },
    );

    test('a void refuses when the create has not reached the server', () async {
      final entry = await create(draft());

      final refusal = await repository.voidLocally(
        entryId: entry.id,
        reason: 'mistake',
        actorUserId: _userA,
        baseRowVersion: entry.rowVersion,
        mutationId: 'mut-void-2',
        now: DateTime.now().toUtc(),
      );

      expect(refusal, isNotNull);
      // The create is untouched, and the sale is not marked voided on a version the
      // server has never issued.
      final reloaded = await repository.load(entry.id);
      expect(reloaded!.voidedAt, isNull);
      expect((await outbox(entry.id)).single.op, MutationOp.create.name);
    });

    test('voiding twice is refused rather than queued twice', () async {
      final entry = await create(draft());
      await accept(entry.id, rowVersion: 2);
      await repository.voidLocally(
        entryId: entry.id,
        reason: 'first',
        actorUserId: _userA,
        baseRowVersion: 2,
        mutationId: 'mut-void-a',
        now: DateTime.now().toUtc(),
      );

      final second = await repository.voidLocally(
        entryId: entry.id,
        reason: 'second',
        actorUserId: _userA,
        baseRowVersion: 2,
        mutationId: 'mut-void-b',
        now: DateTime.now().toUtc(),
      );

      expect(second, isNotNull);
      expect(second!.reason, RevenueRefusalReason.alreadyVoided);
      final queued = (await outbox(
        entry.id,
      )).where((o) => o.status != 'done' && o.op == MutationOp.void_.name);
      expect(queued, hasLength(1));
      expect((await repository.load(entry.id))!.voidReason, 'first');
    });

    test(
      'a void replaces a queued correction rather than following it',
      () async {
        final entry = await create(draft());
        await accept(entry.id, rowVersion: 2);
        await correct(
          draft(id: entry.id, amounts: [12000000]),
          baseRowVersion: 2,
        );

        await repository.voidLocally(
          entryId: entry.id,
          reason: 'wrong day entirely',
          actorUserId: _userA,
          baseRowVersion: 2,
          mutationId: 'mut-void-c',
          now: DateTime.now().toUtc(),
        );

        final queued = (await outbox(
          entry.id,
        )).where((o) => o.status != 'done').toList();
        // Sending both would ask the server to correct a document and then throw the
        // correction away. Voiding is the later and more decisive intent.
        expect(queued, hasLength(1));
        expect(queued.single.op, MutationOp.void_.name);
      },
    );

    test('a blank reason is refused before anything is written', () async {
      final entry = await create(draft());
      await accept(entry.id, rowVersion: 2);

      final refusal = await repository.voidLocally(
        entryId: entry.id,
        reason: '   ',
        actorUserId: _userA,
        baseRowVersion: 2,
        mutationId: 'mut-void-d',
        now: DateTime.now().toUtc(),
      );

      expect(refusal, isNotNull);
      expect(refusal!.reason, RevenueRefusalReason.voidReasonRequired);
      expect((await repository.load(entry.id))!.voidedAt, isNull);
    });
  });

  group('replacing the local copy with the server\'s (Review latest)', () {
    Map<String, dynamic> serverHeader(String id, {int rowVersion = 9}) => {
      'id': id,
      'txn_number': 'KI-REV-26-27-000042',
      'financial_year': '2026-27',
      'business_date': '2026-06-16',
      'pnl_period_key': '2026-06',
      'entry_kind': 'daily_summary',
      'source_reference': null,
      'notes': 'corrected by the accountant',
      'row_version': rowVersion,
      'voided_at': null,
      'void_reason': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    List<Map<String, dynamic>> serverComponents(String id) => [
      {
        'id': '$id-server-c0',
        'entered_amount_minor': 9000000,
        'entered_basis': 'inclusive_total',
        'gross_amount_minor': 9000000,
        'tax_amount_minor': 428571,
        'net_amount_minor': 8571429,
        'tax_rule_id': 'rule-restaurant',
        'tax_rate_bp': 500,
        'tax_treatment': 'inclusive',
        'value_band_id': null,
        'value_band_label': null,
        'value_band_floor_minor': null,
        'value_band_ceiling_minor': null,
        'supply_subtype_id': null,
        'premises_status_code': null,
      },
    ];

    test(
      'a conflicted document is replaced, and the attempt survives in the intent',
      () async {
        final entry = await create(draft(amounts: [10000000]));
        await accept(entry.id, rowVersion: 2);
        await correct(
          draft(id: entry.id, amounts: [12000000]),
          baseRowVersion: 2,
        );
        await (db.update(db.syncOutbox)..where(
              (o) => o.entityId.equals(entry.id) & o.status.equals('pending'),
            ))
            .write(const SyncOutboxCompanion(status: Value('conflict')));

        await repository.applyServerDocument(
          header: serverHeader(entry.id),
          components: serverComponents(entry.id),
          orgId: _org,
        );

        final reloaded = await repository.load(entry.id);
        expect(reloaded!.rowVersion, 9);
        expect(reloaded.gross.paise, 9000000);
        expect(reloaded.businessDate.iso, '2026-06-16');

        // The attempt is not lost: it is in the conflicted intent's own payload, and the
        // intent itself is never deleted (D-048 §2).
        final conflicted = (await outbox(
          entry.id,
        )).where((o) => o.status == 'conflict').single;
        expect(conflicted.payload, contains('12000000'));
      },
    );

    test('a deliverable intent blocks the replacement', () async {
      final entry = await create(draft());
      await accept(entry.id, rowVersion: 2);
      await correct(
        draft(id: entry.id, amounts: [12000000]),
        baseRowVersion: 2,
      );

      await expectLater(
        repository.applyServerDocument(
          header: serverHeader(entry.id),
          components: serverComponents(entry.id),
          orgId: _org,
        ),
        throwsA(isA<StateError>()),
      );
      // Untouched: the operator's correction is still on its way.
      expect((await repository.load(entry.id))!.gross.paise, 12000000);
    });

    test(
      'a document with no components is refused rather than emptied',
      () async {
        final entry = await create(draft());
        await accept(entry.id, rowVersion: 2);

        await expectLater(
          repository.applyServerDocument(
            header: serverHeader(entry.id),
            components: const [],
            orgId: _org,
          ),
          throwsA(isA<StateError>()),
        );
        expect((await repository.load(entry.id))!.components, isNotEmpty);
      },
    );
  });

  group('sync state, read from the outbox', () {
    test(
      'pending, conflict and synced are each reported for a detail surface',
      () async {
        final entry = await create(draft());
        expect(await repository.syncStateOf(entry.id), SyncState.pendingSync);

        await (db.update(db.syncOutbox)
              ..where((o) => o.entityId.equals(entry.id)))
            .write(const SyncOutboxCompanion(status: Value('conflict')));
        expect(await repository.syncStateOf(entry.id), SyncState.conflict);

        await accept(entry.id, rowVersion: 2);
        expect(await repository.syncStateOf(entry.id), SyncState.synced);
      },
    );
  });

  group('ownership and scope are unchanged by any of this', () {
    test(
      'another actor\'s correction does not take over the queued intent\'s owner',
      () async {
        final entry = await create(
          draft(),
          authority: _authority(user: _userA),
        );
        await accept(entry.id, rowVersion: 2);

        await correct(
          draft(id: entry.id, amounts: [12000000]),
          baseRowVersion: 2,
          authority: _authority(user: _userB),
        );

        final queued = (await outbox(
          entry.id,
        )).where((o) => o.status != 'done').single;
        // A new intent, so it belongs to whoever queued it. The create's own entry keeps
        // its actor (D-050), which is what the retention rule reads (D-074).
        expect(queued.actorUserId, _userB);
      },
    );
  });
}
