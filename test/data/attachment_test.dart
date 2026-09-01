/// Staging a bill, uploading it, and the guarantee that neither can hurt the expense.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/data/attachments/attachment_upload_worker.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

/// An object store that records what it was given and can be told to fail.
class FakeObjectStore implements AttachmentObjectStore {
  final Map<String, List<int>> objects = {};
  int uploadAttempts = 0;

  UploadOutcome? nextOutcome;

  /// When set, the store claims to hold a different hash than it was sent.
  String? corruptReportedHash;

  @override
  Future<UploadOutcome> upload({
    required String orgId,
    required String expenseId,
    required String attachmentId,
    required String fileName,
    required String contentType,
    required List<int> bytes,
  }) async {
    uploadAttempts++;
    if (nextOutcome case final forced?) {
      nextOutcome = null;
      return forced;
    }
    final path = attachmentStoragePath(
      orgId: orgId,
      expenseId: expenseId,
      attachmentId: attachmentId,
      fileName: fileName,
    );
    objects[path] = bytes;
    return UploadStored(
      storagePath: path,
      reportedHash: corruptReportedHash ?? sha256Of(bytes),
    );
  }

  @override
  Future<String?> hashOf(String storagePath) async {
    final bytes = objects[storagePath];
    return bytes == null ? null : sha256Of(bytes);
  }
}

/// A JPEG of [dimension] square, noisy enough that it does not compress to nothing.
Uint8List syntheticPhoto(int dimension) {
  final image = img.Image(width: dimension, height: dimension);
  for (var y = 0; y < dimension; y++) {
    for (var x = 0; x < dimension; x++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x * y) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late Directory root;
  late Directory staging;
  late AttachmentStagingService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('krishna_attachments');
    staging = Directory('${root.path}/staging');
    service = AttachmentStagingService(
      resolveStagingDirectory: () async => staging..createSync(recursive: true),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  File sourceFile(String name, List<int> bytes) {
    final file = File('${root.path}/incoming/$name')
      ..createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('staging copies the bytes somewhere durable', () {
    test('the source is copied, not referenced', () async {
      final source = sourceFile('bill.jpg', syntheticPhoto(200));
      final staged = await service.stage(source: source, expenseId: 'exp-1');

      expect(staged.localPath, isNot(source.path));
      expect(staged.localPath, contains('staging'));
      expect(File(staged.localPath).existsSync(), isTrue);

      // The gallery copy goes away, as the OS is free to do at any time.
      source.deleteSync();
      expect(
        File(staged.localPath).existsSync(),
        isTrue,
        reason: 'the receipt must survive its source disappearing',
      );
      expect(
        await sha256OfFile(File(staged.localPath)),
        staged.contentHash,
        reason: 'the hash describes the copy that will actually be uploaded',
      );
    });

    test('staged files survive a restart', () async {
      final staged = await service.stage(
        source: sourceFile('bill.jpg', syntheticPhoto(200)),
        expenseId: 'exp-1',
      );

      // A new service instance, as after an app restart, finds the same bytes.
      final again = AttachmentStagingService(
        resolveStagingDirectory: () async => staging,
      );
      expect(again, isNotNull);
      expect(File(staged.localPath).existsSync(), isTrue);
      expect(await sha256OfFile(File(staged.localPath)), staged.contentHash);
    });

    test('each expense gets its own staging directory', () async {
      final a = await service.stage(
        source: sourceFile('a.jpg', syntheticPhoto(120)),
        expenseId: 'exp-a',
      );
      final b = await service.stage(
        source: sourceFile('b.jpg', syntheticPhoto(120)),
        expenseId: 'exp-b',
      );
      expect(a.localPath, contains('exp-a'));
      expect(b.localPath, contains('exp-b'));
    });
  });

  group('the approved policy is enforced on the way in', () {
    test('a sixth attachment is refused', () async {
      final five = [
        for (var i = 0; i < 5; i++) stagedAttachment(id: 'a$i', bytes: 1024),
      ];
      await expectLater(
        service.stage(
          source: sourceFile('bill.jpg', syntheticPhoto(100)),
          expenseId: 'exp-1',
          alreadyAttached: five,
        ),
        throwsA(
          isA<AttachmentRefused>().having(
            (e) => e.reason,
            'reason',
            AttachmentRejection.tooManyAttachments,
          ),
        ),
      );
    });

    test('a document over 10 MB is refused', () async {
      await expectLater(
        service.stage(
          source: sourceFile(
            'invoice.pdf',
            List<int>.filled(11 * 1024 * 1024, 7),
          ),
          expenseId: 'exp-1',
        ),
        throwsA(
          isA<AttachmentRefused>().having(
            (e) => e.reason,
            'reason',
            AttachmentRejection.documentTooLarge,
          ),
        ),
      );
    });

    test('exceeding 25 MB across one expense is refused', () async {
      final existing = [
        for (var i = 0; i < 3; i++)
          stagedAttachment(id: 'a$i', bytes: 8 * 1024 * 1024),
      ];
      await expectLater(
        service.stage(
          source: sourceFile(
            'invoice.pdf',
            List<int>.filled(2 * 1024 * 1024, 7),
          ),
          expenseId: 'exp-1',
          alreadyAttached: existing,
        ),
        throwsA(
          isA<AttachmentRefused>().having(
            (e) => e.reason,
            'reason',
            AttachmentRejection.expenseWouldExceedTotal,
          ),
        ),
      );
    });

    test('an unsupported type is refused', () async {
      await expectLater(
        service.stage(
          source: sourceFile('clip.mp4', List<int>.filled(1024, 1)),
          expenseId: 'exp-1',
        ),
        throwsA(
          isA<AttachmentRefused>().having(
            (e) => e.reason,
            'reason',
            AttachmentRejection.unsupportedType,
          ),
        ),
      );
    });

    test(
      'a large photo is brought under the target and stays readable',
      () async {
        final huge = syntheticPhoto(4000);
        expect(
          huge.length,
          greaterThan(AttachmentPolicy.imageTargetBytes),
          reason:
              'the fixture has to actually be too big for this to mean anything',
        );

        final staged = await service.stage(
          source: sourceFile('bill.jpg', huge),
          expenseId: 'exp-1',
        );

        expect(
          staged.byteSize,
          lessThanOrEqualTo(AttachmentPolicy.imageTargetBytes),
        );
        expect(staged.wasOptimized, isTrue);
        expect(staged.originalByteSize, huge.length);

        final decoded = img.decodeImage(
          File(staged.localPath).readAsBytesSync(),
        );
        expect(decoded, isNotNull);
        expect(
          decoded!.width,
          greaterThanOrEqualTo(1400),
          reason: 'below about 1400px the figures on a bill start to go',
        );
      },
      // Decoding, resizing and re-encoding a 4000px JPEG in pure Dart is genuinely
      // CPU-bound, and on this machine it lands within a second of the 30s default.
      // A test that passes at 29s is not passing for a reason — it is passing until the
      // machine is busy, and then it reports a failure that says nothing about the code.
      // The assertions above are untouched; only the clock is.
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('a small photo is left alone', () async {
      final small = syntheticPhoto(150);
      final staged = await service.stage(
        source: sourceFile('bill.jpg', small),
        expenseId: 'exp-1',
      );
      expect(staged.byteSize, small.length);
      expect(staged.wasOptimized, isFalse);
    });
  });

  group('the v10 lifecycle migration rewrites what it cannot copy', () {
    test('old values are transformed during the copy, not after it', () async {
      // Found by the Windows acceptance, on a machine that actually had a v9 database.
      // The emulator is reinstalled between runs and always had a fresh one, so this
      // only ever failed where real data existed — which is the whole reason the
      // migration is exercised here against rows written under the old constraint.
      final file = await createTempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      // A v9-shaped attachments table, with the states v9 allowed.
      final raw = sqlite3.open(file.path);
      raw
        ..execute('PRAGMA user_version = 9')
        // Every real v9 database has these — they arrived in v2 and v3. The fixture
        // carried only the attachments table, which was enough until v11 began adding
        // columns to the rule cache; a partial fixture that omits what the migration
        // touches tests the migration against a database nobody has.
        ..execute('''
          CREATE TABLE revenue_categories (
            id TEXT NOT NULL PRIMARY KEY, org_id TEXT NOT NULL,
            business_unit_id TEXT NOT NULL, code TEXT NOT NULL, name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0, archived_at TEXT NULL,
            row_version INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL
          )
        ''')
        ..execute('''
          CREATE TABLE revenue_tax_rates (
            id TEXT NOT NULL PRIMARY KEY, org_id TEXT NOT NULL,
            revenue_category_id TEXT NOT NULL, rate_basis_points INTEGER NOT NULL,
            treatment TEXT NOT NULL, effective_from TEXT NOT NULL,
            effective_to TEXT NULL, note TEXT NULL, archived_at TEXT NULL,
            created_by TEXT NOT NULL, created_at TEXT NOT NULL,
            row_version INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL
          )
        ''')
        ..execute("""
          CREATE TABLE expense_attachments (
            id TEXT NOT NULL PRIMARY KEY,
            org_id TEXT NOT NULL,
            expense_id TEXT NOT NULL,
            file_name TEXT NOT NULL,
            content_type TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            content_hash TEXT NOT NULL,
            local_path TEXT NULL,
            upload_state TEXT NOT NULL DEFAULT 'pending',
            storage_path TEXT NULL,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            next_attempt_at TEXT NULL,
            last_error TEXT NULL,
            uploaded_at TEXT NULL,
            reclaimable_after TEXT NULL,
            uploaded_by TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            CHECK (upload_state IN ('pending','uploaded','stagingReclaimed','failed'))
          )
        """);
      for (final row in const [
        ('a1', 'pending', null, null),
        ('a2', 'failed', '2026-06-15T10:00:00.000Z', null),
        ('a3', 'failed', null, null),
        // An already-uploaded row carries its path and time, as the constraint that has
        // always been on this table requires.
        ('a4', 'uploaded', null, 'org/o/expenses/e/a4.jpg'),
      ]) {
        raw.execute(
          'INSERT INTO expense_attachments (id, org_id, expense_id, file_name, '
          'content_type, byte_size, content_hash, upload_state, next_attempt_at, '
          'storage_path, uploaded_at, uploaded_by, created_at, updated_at) '
          "VALUES (?, 'o', 'e', 'b.jpg', 'image/jpeg', 10, 'h', ?, ?, ?, "
          "CASE WHEN ? IS NULL THEN NULL ELSE '2026-06-15T09:30:00.000Z' END, "
          "'u', '2026-06-15T09:00:00.000Z', '2026-06-15T09:00:00.000Z')",
          [row.$1, row.$2, row.$3, row.$4, row.$4],
        );
      }
      raw.close();

      // Opening at v10 runs the migration.
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final states = {
        for (final r
            in await db
                .customSelect(
                  'SELECT id, upload_state FROM expense_attachments',
                )
                .get())
          r.data['id'] as String: r.data['upload_state'] as String,
      };

      expect(states['a1'], 'waitingForExpense');
      expect(
        states['a2'],
        'retryNeeded',
        reason: 'a retry time is the evidence that the failure was transient',
      );
      expect(
        states['a3'],
        'rejected',
        reason: 'no retry time means it was refused, and must never be retried',
      );
      expect(
        states['a4'],
        'uploaded',
        reason: 'unchanged states stay unchanged',
      );
    });
  });

  group('upload is out of band, and confirmation is about bytes', () {
    late AppDatabase db;
    late ExpenseRepository expenses;
    late FakeObjectStore store;
    var clock = DateTime.utc(2026, 6, 15, 10);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.customStatement('PRAGMA foreign_keys = ON');
      await seedMasterData(db, now: clock);
      expenses = ExpenseRepository(db);
      store = FakeObjectStore();
    });

    tearDown(() => db.close());

    AttachmentUploadWorker workerFor() =>
        AttachmentUploadWorker(db: db, store: store, clock: () => clock);

    /// Saves an expense carrying one genuinely staged attachment.
    Future<(String expenseId, StagedAttachment staged)>
    saveWithAttachment() async {
      final expenseId = const Uuid().v4();
      final staged = await service.stage(
        source: sourceFile('bill.jpg', syntheticPhoto(200)),
        expenseId: expenseId,
      );
      final expense = expenseWith(
        id: expenseId,
        lines: [line(unit: ccrId, rupees: 200)],
        attachments: [staged.toDomain()],
      );
      final mutationId = const Uuid().v4();
      await expenses.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: mutationId,
        now: clock,
      );

      // The attachment starts `staged` and becomes `waitingForExpense` when the document
      // is saved; it becomes uploadable only once the server has accepted the expense.
      // That ordering is the rule (D-073 §2) — the Storage write policy requires the
      // expense to exist canonically — so the helper puts the document where every
      // upload test needs it: accepted.
      await workerFor().markWaitingForExpense(expenseId);
      await expenses.reconcileAcceptance(
        ExpenseAcceptance(
          expenseId: expenseId,
          txnNumber: 'KI-EXP-26-27-000003',
          financialYear: 2026,
          rowVersion: 2,
          serverUpdatedAt: clock,
        ),
      );
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'done' WHERE mutation_id = ?",
        [mutationId],
      );
      return (expenseId, staged);
    }

    test('an attachment is not uploaded before its expense is accepted', () async {
      // The ordering rule, asserted rather than assumed. Uploading first is not merely
      // early: the Storage policy calls `may_read_expense_attachments`, which requires
      // the expense to exist canonically, so the attempt would be refused for a reason
      // that reads like a permission problem and is really an ordering one.
      final expenseId = const Uuid().v4();
      final staged = await service.stage(
        source: sourceFile('bill.jpg', syntheticPhoto(200)),
        expenseId: expenseId,
      );
      await expenses.createLocally(
        expenseWith(
          id: expenseId,
          lines: [line(unit: ccrId, rupees: 200)],
          attachments: [staged.toDomain()],
        ),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: clock,
      );
      await workerFor().markWaitingForExpense(expenseId);

      expect(
        await workerFor().uploadDue(),
        0,
        reason: 'the expense has no transaction number yet',
      );
      expect(
        (await db.select(db.expenseAttachments).get()).single.uploadState,
        'waitingForExpense',
      );
      expect(store.uploadAttempts, 0);

      // The server accepts the expense, and the same worker promotes and uploads it.
      await expenses.reconcileAcceptance(
        ExpenseAcceptance(
          expenseId: expenseId,
          txnNumber: 'KI-EXP-26-27-000009',
          financialYear: 2026,
          rowVersion: 2,
          serverUpdatedAt: clock,
        ),
      );
      expect(await workerFor().uploadDue(), 1);
      expect(
        (await db.select(db.expenseAttachments).get()).single.uploadState,
        'uploaded',
      );
    });

    test('a confirmed upload is verified, not merely accepted', () async {
      final (expenseId, staged) = await saveWithAttachment();

      expect(await workerFor().uploadDue(), 1);

      final row = (await db.select(db.expenseAttachments).get()).single;
      expect(row.uploadState, 'uploaded');
      expect(
        row.storagePath,
        'org/$seedOrgId/expenses/$expenseId/${staged.id}.jpg',
      );
      expect(row.uploadedAt, isNotNull);
      expect(
        row.reclaimableAfter,
        clock.add(AttachmentPolicy.stagingRetention),
        reason: 'the local copy stays for a week after confirmation',
      );
      expect(File(row.localPath!).existsSync(), isTrue);
    });

    test('a mismatched hash is not confirmed', () async {
      await saveWithAttachment();
      store.corruptReportedHash = 'sha256-something-else';

      expect(await workerFor().uploadDue(), 0);

      final row = (await db.select(db.expenseAttachments).get()).single;
      expect(row.uploadState, 'retryNeeded');
      expect(row.lastError, contains('did not match'));
      expect(
        row.storagePath,
        isNull,
        reason: 'an unverified object is not recorded as the attachment',
      );
    });

    test(
      'a failing upload never touches the expense, which stays Synced',
      () async {
        final (expenseId, _) = await saveWithAttachment();

        // The financial record is accepted and numbered.
        await expenses.reconcileAcceptance(
          ExpenseAcceptance(
            expenseId: expenseId,
            rowVersion: 2,
            txnNumber: 'KI-EXP-26-27-000001',
            financialYear: 2026,
          ),
        );

        // The photograph then fails, twice.
        store.nextOutcome = const UploadUnreachable('no route to host');
        expect(await workerFor().uploadDue(), 0);
        clock = clock.add(const Duration(minutes: 30));
        store.nextOutcome = const UploadUnreachable('no route to host');
        expect(await workerFor().uploadDue(), 0);

        final expense = await expenses.load(expenseId);
        expect(
          expense!.syncState,
          SyncState.synced,
          reason: 'an attachment failure is not the expense s failure',
        );
        expect(expense.row.txnNumber, 'KI-EXP-26-27-000001');
        expect(
          await db.select(db.expenses).get(),
          hasLength(1),
          reason: 'and no duplicate expense was created to retry the photo',
        );

        final row = (await db.select(db.expenseAttachments).get()).single;
        expect(row.uploadState, 'retryNeeded');
        expect(row.attemptCount, 2);
        expect(
          row.nextAttemptAt,
          isNotNull,
          reason: 'it retries on its own clock',
        );

        // And when the network comes back, it succeeds on its own.
        clock = row.nextAttemptAt!.add(const Duration(seconds: 1));
        expect(await workerFor().uploadDue(), 1);
        expect(
          (await db.select(db.expenseAttachments).get()).single.uploadState,
          'uploaded',
        );
      },
    );

    test('backoff is respected between attempts', () async {
      await saveWithAttachment();
      store.nextOutcome = const UploadUnreachable('offline');
      await workerFor().uploadDue();

      final attempts = store.uploadAttempts;
      // Immediately afterwards nothing is due.
      expect(await workerFor().uploadDue(), 0);
      expect(store.uploadAttempts, attempts);
    });

    test('a refusal is terminal and is not retried', () async {
      await saveWithAttachment();
      store.nextOutcome = const UploadRefused('This bucket is not writable.');
      await workerFor().uploadDue();

      final row = (await db.select(db.expenseAttachments).get()).single;
      expect(
        row.uploadState,
        'rejected',
        reason:
            'a refusal is the server s considered answer, and is kept apart from a '
            'transient failure precisely so it is never retried (D-073 §4)',
      );
      expect(row.nextAttemptAt, isNull, reason: 'nothing to retry towards');

      clock = clock.add(const Duration(days: 7));
      final attempts = store.uploadAttempts;
      expect(await workerFor().uploadDue(), 0);
      expect(store.uploadAttempts, attempts);
    });

    test(
      'staging is reclaimed only after confirmation and retention',
      () async {
        await saveWithAttachment();
        await workerFor().uploadDue();

        // Six days: not yet.
        clock = clock.add(const Duration(days: 6));
        expect(await workerFor().reclaimVerifiedStaging(), 0);
        var row = (await db.select(db.expenseAttachments).get()).single;
        expect(File(row.localPath!).existsSync(), isTrue);

        // Eight days: reclaimed, and the server copy remains canonical.
        clock = clock.add(const Duration(days: 2));
        expect(await workerFor().reclaimVerifiedStaging(), 1);
        row = (await db.select(db.expenseAttachments).get()).single;
        expect(row.uploadState, 'stagingReclaimed');
        expect(row.localPath, isNull);
        expect(row.storagePath, isNotNull);
      },
    );

    test(
      'an unconfirmed staging copy is never reclaimed, however old',
      () async {
        await saveWithAttachment();
        store.nextOutcome = const UploadUnreachable('offline');
        await workerFor().uploadDue();

        clock = clock.add(const Duration(days: 90));
        expect(
          await workerFor().reclaimVerifiedStaging(),
          0,
          reason: 'it is the only copy there is',
        );
        final row = (await db.select(db.expenseAttachments).get()).single;
        expect(File(row.localPath!).existsSync(), isTrue);
      },
    );

    test('voiding an expense does not remove its attachments', () async {
      final (expenseId, _) = await saveWithAttachment();
      await workerFor().uploadDue();

      await (db.update(
        db.expenses,
      )..where((t) => t.id.equals(expenseId))).write(
        ExpensesCompanion(
          voidedAt: Value(clock),
          voidedBy: const Value('accountant'),
          voidReason: const Value('Entered twice'),
        ),
      );

      final attachments = await db.select(db.expenseAttachments).get();
      expect(
        attachments,
        hasLength(1),
        reason: 'the document and its evidence remain part of history',
      );
      expect(attachments.single.uploadState, 'uploaded');
      expect(attachments.single.storagePath, isNotNull);
    });
  });

  group('the storage path', () {
    test('follows the approved structure and is stable', () {
      final path = attachmentStoragePath(
        orgId: 'org-1',
        expenseId: 'exp-1',
        attachmentId: 'att-1',
        fileName: 'bill.JPG',
      );
      expect(path, 'org/org-1/expenses/exp-1/att-1.jpg');

      // The same attachment always lands in the same place, so a retry overwrites
      // itself rather than leaving two copies.
      expect(
        attachmentStoragePath(
          orgId: 'org-1',
          expenseId: 'exp-1',
          attachmentId: 'att-1',
          fileName: 'bill.jpg',
        ),
        path,
      );
    });
  });
}
