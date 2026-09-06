/// Evidence attached to a sale (Phase 4 Slice 11).
///
/// The governing rule, and what every group here is defending:
///
/// > Revenue attachments are supporting evidence for a Revenue document. They are
/// > private, offline-capable, actor/scope-safe, retryable, and must never become an
/// > alternate financial source of truth.
///
/// The last clause is the one with teeth, and it is asserted directly rather than argued:
/// a sale's gross, tax, net, business date, transaction number and row version are
/// captured before evidence is attached and compared after, through every path that
/// touches an attachment.
///
/// Nothing here re-tests the pipeline itself. Staging, hashing, the eight-state
/// lifecycle, backoff, hash confirmation and reclamation are the Phase 3 mechanism
/// (D-073a) and are proven in `attachment_test.dart`; this file proves that revenue uses
/// **that** mechanism, on its own parent, without a second one appearing.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/data/attachments/attachment_upload_worker.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/cache_classification.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/revenue_parity_vectors.dart';
import 'attachment_test.dart' show FakeObjectStore;

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
      CapabilityGrant(Capability.attachmentUpload, businessUnitId: unit),
      CapabilityGrant(Capability.attachmentView, businessUnitId: unit),
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
  late Directory root;
  late Directory staging;
  late AttachmentStagingService stagingService;
  late FakeObjectStore store;
  var seq = 0;
  var clock = DateTime.utc(2026, 6, 15, 10);

  AttachmentUploadWorker worker() =>
      AttachmentUploadWorker(db: db, store: store, clock: () => clock);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    repository = RevenueRepository(db, tax: RevenueTaxRepository(db));
    store = FakeObjectStore();
    seq = 0;
    clock = DateTime.utc(2026, 6, 15, 10);

    root = await Directory.systemTemp.createTemp('krishna_revenue_evidence');
    staging = Directory('${root.path}/staging');
    stagingService = AttachmentStagingService(
      resolveStagingDirectory: () async => staging..createSync(recursive: true),
    );

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
        'created_by, created_at, row_version, updated_at) '
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

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  RevenueEntryDraft draft({
    String? id,
    String category = vCategoryRestaurant,
    List<int> amounts = const [10000000],
    String date = '2026-06-15',
  }) {
    seq++;
    final entryId = id ?? 'entry-$seq';
    return RevenueEntryDraft(
      id: entryId,
      businessUnitId: _unitOf(category),
      revenueCategoryId: category,
      businessDate: vDate(date),
      capturedAt: DateTime.now().toUtc(),
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
  }) async {
    final who = authority ?? _authority();
    final decision = await repository.evaluate(d, authority: who);
    expect(decision, isA<RevenueCreatePermitted>());
    return repository.createLocally(
      d,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: who.userId,
      orgId: _org,
      mutationId: 'mut-${d.id}',
      now: DateTime.now().toUtc(),
    );
  }

  /// Marks a sale accepted the way the reconciler does, so its evidence becomes
  /// uploadable. Deliberately through the real reconciliation path.
  Future<void> accept(String entryId, {String number = 'KI-REV-26-27-000001'}) {
    return db.transaction(() async {
      await repository.reconcileAcceptance(
        RevenueAcceptance(
          entryId: entryId,
          rowVersion: 1,
          txnNumber: number,
          financialYear: '2026',
          serverUpdatedAt: clock,
        ),
      );
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'done' WHERE entity_id = ?",
        [entryId],
      );
    });
  }

  Future<DocumentAttachment> stage(
    String entryId, {
    String name = 'z.jpg',
  }) async {
    final file = File('${root.path}/incoming/$entryId-$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.generate(4096, (i) => (i * 31) % 251));
    final staged = await stagingService.stage(
      source: file,
      ownerId: entryId,
      fileName: name,
      contentType: 'image/jpeg',
    );
    return staged.toDomain();
  }

  Future<RevenueRefusal?> attach(
    String entryId,
    List<DocumentAttachment> files, {
    String actor = _userA,
  }) => repository.attachLocally(
    entryId: entryId,
    staged: files,
    actorUserId: actor,
    orgId: _org,
    now: clock,
  );

  /// Everything about a sale that evidence must never move.
  Future<Map<String, Object?>> financialState(String id) async {
    final entry = (await repository.load(id))!;
    return {
      'gross': entry.gross.paise,
      'tax': entry.tax.paise,
      'net': entry.net.paise,
      'businessDate': entry.businessDate.iso,
      'txnNumber': entry.txnNumber,
      'rowVersion': entry.rowVersion,
      'components': entry.components.length,
      'businessDateSource': entry.businessDateSource.wireName,
    };
  }

  group('evidence attaches to the sale, and to nothing else (§3, §10)', () {
    test('a file attached to a locally saved sale waits for its parent', () async {
      final entry = await create(draft(id: 'e1'));
      expect(await attach('e1', [await stage('e1')]), isNull);

      final files = await repository.attachmentsOf('e1');
      expect(files, hasLength(1));
      expect(
        files.single.uploadState,
        AttachmentUploadState.waitingForExpense,
        reason:
            'the server has not accepted the sale, so the Storage policy would refuse '
            'the object for a reason that reads like a permission problem (D-073 §2)',
      );
      expect(
        entry.attachments,
        isEmpty,
        reason: 'the create returned before this',
      );
    });

    test(
      'a file attached to an already-numbered sale is uploadable at once',
      () async {
        await create(draft(id: 'e2'));
        await accept('e2');

        expect(await attach('e2', [await stage('e2')]), isNull);
        expect(
          (await repository.attachmentsOf('e2')).single.uploadState,
          AttachmentUploadState.pendingUpload,
        );
      },
    );

    test('attaching queues no financial intent and moves no version', () async {
      await create(draft(id: 'e3'));
      await accept('e3');
      final before = await financialState('e3');
      final outboxBefore = await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
          .getSingle();

      await attach('e3', [await stage('e3')]);

      expect(await financialState('e3'), before);
      final outboxAfter = await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
          .getSingle();
      expect(
        outboxAfter.read<int>('n'),
        outboxBefore.read<int>('n'),
        reason: 'evidence is not a financial mutation and queues no intent',
      );
    });

    test('the sale is loaded with its evidence', () async {
      await create(draft(id: 'e4'));
      await attach('e4', [await stage('e4', name: 'z-report.jpg')]);

      final entry = await repository.load('e4');
      expect(entry!.attachments.single.fileName, 'z-report.jpg');
      // Still not a source of truth: the figures are the components' and nothing else.
      expect(entry.gross.paise, 10000000);
      expect(entry.reconciles, isTrue);
    });

    test('evidence belongs to the document, not to a component', () async {
      // A two-band Room day is two components and one evidence collection (§3).
      await create(
        draft(id: 'e5', category: vCategoryRoom, amounts: [4200000, 2300000]),
      );
      await attach('e5', [await stage('e5')]);

      final entry = (await repository.load('e5'))!;
      expect(entry.components, hasLength(2));
      expect(entry.attachments, hasLength(1));
    });
  });

  group('identity is the attachment id (§9)', () {
    test('re-attaching the same file writes one row, not two', () async {
      await create(draft(id: 'i1'));
      final file = await stage('i1');

      expect(await attach('i1', [file]), isNull);
      expect(await attach('i1', [file]), isNull);
      expect(await attach('i1', [file, file]), isNull);

      expect(await repository.attachmentsOf('i1'), hasLength(1));
    });

    test('a repeated attach does not consume the count limit', () async {
      await create(draft(id: 'i2'));
      final five = [
        for (var i = 0; i < AttachmentPolicy.maxPerDocument; i++)
          await stage('i2', name: 'f$i.jpg'),
      ];
      expect(await attach('i2', five), isNull);
      // The form hands back the whole collection it was showing. If that counted again,
      // saving twice would refuse a document for exceeding a count it never reached.
      expect(await attach('i2', five), isNull);
      expect(await repository.attachmentsOf('i2'), hasLength(5));
    });

    test(
      'one more than the limit is refused, and nothing is written',
      () async {
        await create(draft(id: 'i3'));
        final five = [
          for (var i = 0; i < AttachmentPolicy.maxPerDocument; i++)
            await stage('i3', name: 'f$i.jpg'),
        ];
        await attach('i3', five);

        final refusal = await attach('i3', [
          await stage('i3', name: 'sixth.jpg'),
        ]);
        expect(refusal, isNotNull);
        expect(refusal!.reason, RevenueRefusalReason.attachmentLimit);
        expect(refusal.message, contains('at most 5'));
        expect(await repository.attachmentsOf('i3'), hasLength(5));
      },
    );

    test(
      'a refusal message carries nothing an operator cannot act on',
      () async {
        await create(draft(id: 'i4'));
        final five = [
          for (var i = 0; i < AttachmentPolicy.maxPerDocument; i++)
            await stage('i4', name: 'f$i.jpg'),
        ];
        await attach('i4', five);
        final refusal = await attach('i4', [await stage('i4', name: 'x.jpg')]);

        for (final leak in const [
          'KM0',
          'revenue_attachments',
          'SQL',
          'Exception',
          'storage_path',
          'org/',
        ]) {
          expect(
            refusal!.message,
            isNot(contains(leak)),
            reason: 'a refusal is a sentence, not a diagnostic',
          );
        }
      },
    );
  });

  group('a voided sale keeps its evidence and gains none (§30)', () {
    test('existing evidence survives the void', () async {
      await create(draft(id: 'v1'));
      await accept('v1');
      await attach('v1', [await stage('v1')]);

      await repository.voidLocally(
        entryId: 'v1',
        reason: 'duplicate entry',
        actorUserId: _userA,
        baseRowVersion: 1,
        mutationId: 'void-v1',
        now: clock,
      );

      final entry = (await repository.load('v1'))!;
      expect(entry.isVoided, isTrue);
      expect(
        entry.attachments,
        hasLength(1),
        reason: 'evidence for what was recorded is exactly what an audit needs',
      );
    });

    test('nothing further can be attached to it', () async {
      await create(draft(id: 'v2'));
      await accept('v2');
      await repository.voidLocally(
        entryId: 'v2',
        reason: 'duplicate entry',
        actorUserId: _userA,
        baseRowVersion: 1,
        mutationId: 'void-v2',
        now: clock,
      );

      final refusal = await attach('v2', [await stage('v2')]);
      expect(refusal!.reason, RevenueRefusalReason.alreadyVoided);
      expect(await repository.attachmentsOf('v2'), isEmpty);
    });
  });

  group('a correction preserves evidence (§31)', () {
    test('the same file stays associated across an edit', () async {
      await create(draft(id: 'c1'));
      await accept('c1');
      final file = await stage('c1', name: 'till.jpg');
      await attach('c1', [file]);

      final corrected = draft(id: 'c1', amounts: [12000000]);
      final decision = await repository.evaluate(
        corrected,
        authority: _authority(),
      );
      await repository.updateLocally(
        corrected,
        resolutions: (decision as RevenueCreatePermitted).resolutions,
        actorUserId: _userA,
        orgId: _org,
        baseRowVersion: 1,
        mutationId: 'edit-c1',
        now: clock,
      );

      final entry = (await repository.load('c1'))!;
      expect(entry.gross.paise, 12000000, reason: 'the correction applied');
      expect(entry.attachments.single.id, file.id);
      expect(
        entry.txnNumber,
        'KI-REV-26-27-000001',
        reason: 'the number belongs to the identity and survives correction',
      );
    });
  });

  group('upload is the shared pipeline, on the sale as parent (§4, §8)', () {
    test(
      'the worker will not upload before the server accepts the sale',
      () async {
        await create(draft(id: 'u1'));
        await attach('u1', [await stage('u1')]);

        expect(await worker().uploadDue(), 0);
        expect(store.uploadAttempts, 0);

        await accept('u1');
        expect(await worker().uploadDue(), 1);
        expect(store.objects, hasLength(1));
      },
    );

    test(
      'the object lands under the revenue prefix, never the expense one',
      () async {
        await create(draft(id: 'u2'));
        await accept('u2');
        await attach('u2', [await stage('u2')]);
        await worker().uploadDue();

        final path = store.objects.keys.single;
        expect(path, startsWith('org/$_org/revenue/u2/'));
        expect(path, isNot(contains('/expenses/')));
        expect((await repository.attachmentsOf('u2')).single.storagePath, path);
      },
    );

    test('a retry writes the same object and one row', () async {
      await create(draft(id: 'u3'));
      await accept('u3');
      await attach('u3', [await stage('u3')]);

      store.nextOutcome = const UploadUnreachable('no route to host');
      expect(await worker().uploadDue(), 0);
      expect(
        (await repository.attachmentsOf('u3')).single.uploadState,
        AttachmentUploadState.retryNeeded,
      );

      clock = clock.add(const Duration(minutes: 30));
      expect(await worker().uploadDue(), 1);
      expect(store.objects, hasLength(1));
      expect(await repository.attachmentsOf('u3'), hasLength(1));
      expect(
        (await repository.attachmentsOf('u3')).single.uploadState,
        AttachmentUploadState.uploaded,
      );
    });

    test('a failed upload leaves the sale entirely alone (§24)', () async {
      await create(draft(id: 'u4'));
      await accept('u4');
      final before = await financialState('u4');
      await attach('u4', [await stage('u4')]);

      store.nextOutcome = const UploadRefused('that file type is not accepted');
      expect(await worker().uploadDue(), 0);

      expect(
        (await repository.attachmentsOf('u4')).single.uploadState,
        AttachmentUploadState.rejected,
      );
      expect(
        await financialState('u4'),
        before,
        reason: 'a rejected photograph is not a rejected sale',
      );
      expect(
        await repository.syncStateOf('u4'),
        isNot(equals(null)),
        reason: 'the sale keeps its own state, decided by the outbox',
      );
    });

    test('a terminal refusal carries no retry time', () async {
      await create(draft(id: 'u5'));
      await accept('u5');
      await attach('u5', [await stage('u5')]);

      store.nextOutcome = const UploadRefused('refused');
      await worker().uploadDue();

      final row = await db
          .customSelect('SELECT next_attempt_at FROM revenue_attachments')
          .getSingle();
      expect(
        row.data['next_attempt_at'],
        isNull,
        reason:
            'a null there once meant "due now" and retried a refusal for ever',
      );
      clock = clock.add(const Duration(days: 30));
      expect(await worker().uploadDue(), 0);
    });

    test('a missing local file is reported, not retried for ever', () async {
      await create(draft(id: 'u6'));
      await accept('u6');
      final file = await stage('u6');
      await attach('u6', [file]);
      File(file.localStagingPath!).deleteSync();

      expect(await worker().uploadDue(), 0);
      final stored = (await repository.attachmentsOf('u6')).single;
      expect(stored.uploadState, AttachmentUploadState.rejected);
      expect(await financialState('u6'), isNotNull);
    });

    test('an interrupted upload is recovered at start-up', () async {
      await create(draft(id: 'u7'));
      await accept('u7');
      await attach('u7', [await stage('u7')]);
      await db.customStatement(
        "UPDATE revenue_attachments SET upload_state = 'uploading'",
      );

      expect(await worker().recoverInterruptedUploads(), 1);
      expect(
        (await repository.attachmentsOf('u7')).single.uploadState,
        AttachmentUploadState.pendingUpload,
      );
    });

    test('one worker serves both documents in one pass', () async {
      // The point of the shared worker: not two clocks and two definitions of
      // "uploaded" that agree only until somebody edits one of them.
      await create(draft(id: 'u8'));
      await accept('u8');
      await attach('u8', [await stage('u8')]);

      expect(await worker().uploadDue(), 1);
      expect(
        store.objects.keys.single,
        contains('/revenue/'),
        reason: 'and the expense table, which is empty here, cost nothing',
      );
    });

    /// What happens to the bytes when the second of the two writes refuses.
    ///
    /// Slice 11 shipped a lifecycle in which they simply stayed: the register RPC refused,
    /// the row went terminally `rejected`, and the object sat in a private bucket named by
    /// nothing. Four of the eight objects the Slice 11 report could not account for were
    /// produced by exactly that, through the ordinary path with no seam involved.
    group('bytes that were never recorded do not stay in the bucket', () {
      test('a terminal registration refusal takes its object back', () async {
        await create(draft(id: 'x1'));
        await accept('x1');
        await attach('x1', [await stage('x1')]);

        // The object lands and the record refuses it — a limit reached from a second
        // device, or a path the server derives differently. Either way there will never
        // be a metadata row, and nothing else will ever look at the object again.
        store.refuseRegistrationOnce = true;
        expect(await worker().uploadDue(), 0);

        expect(
          (await repository.attachmentsOf('x1')).single.uploadState,
          AttachmentUploadState.rejected,
          reason: 'the refusal is still terminal; that part was right',
        );
        expect(
          store.objects,
          isEmpty,
          reason: 'and the bytes it refused are no longer in the bucket',
        );
        expect(store.discarded, hasLength(1));
        expect(store.registered, isEmpty);
      });

      test('reclamation cannot touch an object that is evidence', () async {
        // The guarantee that makes the reclamation safe, and it is the server's rather
        // than the client's: while a metadata row names the path the delete is refused,
        // so a client that lost a response and guessed wrong destroys nothing.
        await create(draft(id: 'x2'));
        await accept('x2');
        await attach('x2', [await stage('x2')]);
        expect(await worker().uploadDue(), 1);

        final path = store.objects.keys.single;
        expect(
          await store.discardUnregistered(AttachmentOwnerKind.sale, path),
          isFalse,
        );
        expect(store.objects, hasLength(1));
        expect(store.discarded, isEmpty);
      });

      test('a lost registration response reconciles without re-uploading', () async {
        // The case reclamation must never be applied to. The server committed; the
        // client heard nothing. The retry has to establish which of those happened
        // before it does anything, and the answer lives in the metadata row.
        await create(draft(id: 'x3'));
        await accept('x3');
        await attach('x3', [await stage('x3')]);

        store.loseRegistrationResponseOnce = true;
        expect(await worker().uploadDue(), 0);
        expect(
          (await repository.attachmentsOf('x3')).single.uploadState,
          AttachmentUploadState.retryNeeded,
          reason: 'not knowing is not a refusal (D-048 §1)',
        );
        expect(store.registered, hasLength(1));
        final attemptsAfterFirst = store.uploadAttempts;

        clock = clock.add(const Duration(hours: 1));
        expect(await worker().uploadDue(), 1);

        expect(
          store.uploadAttempts,
          attemptsAfterFirst,
          reason:
              'the retry asked whether the registration committed and found that it '
              'had, so it sent no bytes over evidence that already exists',
        );
        expect(store.objects, hasLength(1));
        expect(store.registered, hasLength(1));
        expect(store.discarded, isEmpty);
        expect(
          (await repository.attachmentsOf('x3')).single.uploadState,
          AttachmentUploadState.uploaded,
        );
      });

      test(
        'a different file recorded under this identity is not overwritten',
        () async {
          // The only outcome in which the pre-check finds a registration it disagrees
          // with. Replacing the record would be the one thing that is definitely wrong,
          // so it refuses and says so instead.
          await create(draft(id: 'x4'));
          await accept('x4');
          await attach('x4', [await stage('x4')]);

          store.nextOutcome = const UploadUnreachable('offline');
          expect(await worker().uploadDue(), 0);

          final expected = store.registered;
          expect(expected, isEmpty);
          // Somebody else's bytes are already recorded at this attachment's own path.
          final row = await db
              .customSelect('SELECT * FROM revenue_attachments')
              .getSingle();
          final path = attachmentStoragePath(
            orgId: row.read<String>('org_id'),
            owner: AttachmentOwnerKind.sale,
            ownerId: row.read<String>('revenue_entry_id'),
            attachmentId: row.read<String>('id'),
            fileName: row.read<String>('file_name'),
          );
          store.registered[path] = 'a-different-file-entirely';

          clock = clock.add(const Duration(hours: 1));
          expect(await worker().uploadDue(), 0);
          expect(
            (await repository.attachmentsOf('x4')).single.uploadState,
            AttachmentUploadState.rejected,
          );
          expect(
            store.registered[path],
            'a-different-file-entirely',
            reason: 'the record stands; the client does not get to replace it',
          );
          expect(store.discarded, isEmpty);
        },
      );

      test('none of it moves a financial figure (§25)', () async {
        // The Slice 11 rule, re-asserted over the paths this closure added: a refusal, a
        // reclamation and a lost response are all attachment events, and an attachment
        // event changes no amount, tax figure, date, number or row version.
        await create(draft(id: 'x5'));
        await accept('x5');
        final before = await financialState('x5');

        await attach('x5', [await stage('x5')]);
        store.refuseRegistrationOnce = true;
        await worker().uploadDue();
        expect(await financialState('x5'), before);

        await create(draft(id: 'x6'));
        await accept('x6', number: 'KI-REV-26-27-000002');
        final beforeLost = await financialState('x6');
        await attach('x6', [await stage('x6')]);
        store.loseRegistrationResponseOnce = true;
        await worker().uploadDue();
        clock = clock.add(const Duration(hours: 1));
        await worker().uploadDue();
        expect(await financialState('x6'), beforeLost);
      });
    });
  });

  group('persistence survives a restart (§11, §37)', () {
    test('the staged bytes and the row are both still there', () async {
      await create(draft(id: 'r1'));
      final file = await stage('r1');
      await attach('r1', [file]);

      // The bytes live in app-private storage, not in the financial database.
      expect(File(file.localStagingPath!).existsSync(), isTrue);
      expect(
        file.localStagingPath,
        contains(staging.path),
        reason: 'never a transient content URI (§11)',
      );

      final reopened = await repository.attachmentsOf('r1');
      expect(reopened.single.id, file.id, reason: 'identity is stable');
      expect(reopened.single.contentHash, file.contentHash);
    });
  });

  group('a revocation takes evidence with the sale (§26, D-070)', () {
    late ScopeCachePurge purge;
    final reclaimed = <String>[];

    setUp(() {
      reclaimed.clear();
      purge = ScopeCachePurge(
        db,
        reclaimStaging: (id) async {
          reclaimed.add(id);
          await stagingService.discardDocument(id);
        },
      );
    });

    test('a synced sale loses its evidence and its bytes', () async {
      await create(draft(id: 'p1'));
      await accept('p1');
      final file = await stage('p1');
      await attach('p1', [file]);
      await worker().uploadDue();

      final result = await purge.purgeUnits({_ccr}, actorUserId: _userA);

      expect(result.rowsRemoved['revenue_attachments'], 1);
      expect(await repository.attachmentsOf('p1'), isEmpty);
      expect(reclaimed, contains('p1'));
      expect(File(file.localStagingPath!).existsSync(), isFalse);
    });

    test('a sale kept for unsent work keeps its evidence too', () async {
      await create(draft(id: 'p2'));
      final file = await stage('p2');
      await attach('p2', [file]);

      final result = await purge.purgeUnits({_ccr}, actorUserId: _userA);

      expect(result.documentsRetainedForUnsyncedWork, contains('p2'));
      expect(
        await repository.attachmentsOf('p2'),
        hasLength(1),
        reason: 'the actor\'s own unsent work exists nowhere else (D-070)',
      );
      expect(File(file.localStagingPath!).existsSync(), isTrue);
      expect(reclaimed, isNot(contains('p2')));
    });

    test('a failed refresh is not a revocation and removes nothing', () async {
      await create(draft(id: 'p3'));
      await accept('p3');
      await attach('p3', [await stage('p3')]);

      final result = await purge.applyTo(
        const AuthorityUnavailable(AuthorityUnavailableReason.offline),
        previous: null,
      );

      expect(result.didPurge, isFalse);
      expect(
        await repository.attachmentsOf('p3'),
        hasLength(1),
        reason: 'unknown is not revoked (D-048 §1)',
      );
    });

    test('the local table is classified, so a purge has a defined effect', () {
      expect(
        CacheClassification.ownershipOf('revenue_attachments'),
        CacheOwnership.scopedFinancialHistory,
      );
      // Children before parents: the attachment must be listed before its entry, or a
      // purge would have to lean on the cascade and could not count what it removed.
      final order = [
        for (final t in CacheClassification.purgedOnRevocation) t.name,
      ];
      expect(
        order.indexOf('revenue_attachments'),
        lessThan(order.indexOf('revenue_entries')),
      );
    });
  });

  group('a user switch does not hand over evidence (§27, §28, D-074)', () {
    test(
      "user B does not inherit user A's retained, unsent attachment",
      () async {
        // A records a sale and attaches evidence; neither has synced.
        await create(draft(id: 'sw1'), authority: _authority());
        await attach('sw1', [await stage('sw1')], actor: _userA);

        // A signs out. Nothing browsable, nothing destroyed.
        final purge = ScopeCachePurge(db);
        await purge.quarantineAllDocuments();

        // B signs in, holding the same property.
        final confirmed = AuthorityConfirmed(
          _authority(user: _userB).copyWithResolvedAt(DateTime.now().toUtc()),
        );
        await purge.applyTo(confirmed, previous: null);

        expect(
          await repository.list(),
          isEmpty,
          reason: 'holding a property does not make B the author of A\'s work',
        );
        expect(
          await repository.listRetainedAfterRevocation(_userB),
          isEmpty,
          reason: 'retained work is reached by its own actor and nobody else',
        );
        expect(
          await repository.listRetainedAfterRevocation(_userA),
          contains('sw1'),
          reason: 'and A still has it when A signs back in',
        );
        // The evidence is still on the device, still A's, and unreachable through any
        // ordinary read.
        expect(await repository.attachmentsOf('sw1'), hasLength(1));
      },
    );

    test('quarantined sales are excluded from the browsable ledger', () async {
      await create(draft(id: 'sw2'));
      await accept('sw2');
      await attach('sw2', [await stage('sw2')]);
      expect(await repository.list(), hasLength(1));

      await ScopeCachePurge(db).quarantineAllDocuments();
      expect(await repository.list(), isEmpty);
    });
  });

  group('evidence never becomes a financial source of truth (§25)', () {
    test(
      'every attachment path leaves the money, dates and version untouched',
      () async {
        await create(draft(id: 'f1', amounts: [7654321]));
        await accept('f1', number: 'KI-REV-26-27-000042');
        final before = await financialState('f1');

        // Attach, upload, fail, retry, and attach again.
        await attach('f1', [await stage('f1', name: 'a.jpg')]);
        await worker().uploadDue();
        await attach('f1', [await stage('f1', name: 'b.jpg')]);
        store.nextOutcome = const UploadUnreachable('down');
        await worker().uploadDue();
        clock = clock.add(const Duration(minutes: 30));
        await worker().uploadDue();
        await worker().recoverInterruptedUploads();

        expect(
          await financialState('f1'),
          before,
          reason:
              'gross, tax, net, the business date, the number, the version and the '
              'component count are all decided elsewhere and stay decided',
        );
      },
    );

    test('the local schema stores no amount on an attachment', () async {
      final columns = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('revenue_attachments')",
          )
          .get();
      final names = [for (final c in columns) c.read<String>('name')];

      for (final forbidden in const [
        'amount_minor',
        'gross_amount_minor',
        'tax_amount_minor',
        'net_amount_minor',
        'pnl_period_key',
      ]) {
        expect(
          names,
          isNot(contains(forbidden)),
          reason: 'evidence carries no figure, so none can be summed from it',
        );
      }
    });

    test(
      'V1 ships no removal, so the table carries no removal columns',
      () async {
        final columns = await db
            .customSelect(
              "SELECT name FROM pragma_table_info('revenue_attachments')",
            )
            .get();
        final names = [for (final c in columns) c.read<String>('name')];

        for (final absent in const [
          'removed_at',
          'removed_by',
          'remove_reason',
        ]) {
          expect(
            names,
            isNot(contains(absent)),
            reason:
                'a column with no writer is how the last three findings started '
                '(D-072a, D-145)',
          );
        }
      },
    );
  });

  group('the v13 to v14 migration', () {
    test(
      'a fresh database is born with the table and its constraints',
      () async {
        expect(db.schemaVersion, 14);
        final table = await db
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'revenue_attachments'",
            )
            .getSingle();
        final sql = table.read<String>('sql');
        expect(sql, contains('REFERENCES revenue_entries'));
        expect(
          sql,
          contains("upload_state <> 'rejected' OR next_attempt_at IS NULL"),
        );
      },
    );

    test('an attachment cannot outlive the sale it explains', () async {
      await create(draft(id: 'm1'));
      await attach('m1', [await stage('m1')]);

      // The foreign key is real, and `PRAGMA foreign_keys` is on: the entry cannot be
      // removed while its evidence points at it by any path other than the cascade.
      await db.customStatement('DELETE FROM revenue_entries WHERE id = ?', [
        'm1',
      ]);
      expect(await repository.attachmentsOf('m1'), isEmpty);
    });
  });
}

extension on AuthoritySnapshot {
  AuthoritySnapshot copyWithResolvedAt(DateTime at) => AuthoritySnapshot(
    userId: userId,
    orgId: orgId,
    grants: grants,
    resolvedAt: at,
  );
}
