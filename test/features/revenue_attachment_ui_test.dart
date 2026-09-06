/// The revenue evidence surfaces, on both shells (Phase 4 Slice 11).
///
/// Everything here drives the **real** providers, the real repository and a real
/// in-memory database. The one thing that is injected is the picker, at exactly the point
/// the OS would return a file — the technique D-058 established and the boundary
/// `attachment_source_wiring_test.dart` proves production crosses on its own.
///
/// That distinction is the whole of D-077, so it is worth restating: a synthetic source
/// here proves the pipeline behind the picker. It proves nothing about the picker, and
/// nothing in this file claims to.
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/attachments/attachment_source.dart';
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_detail_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_entry_page.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/revenue_parity_vectors.dart';
import '../support/test_session.dart';
import '../support/ui_harness.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _userA = 'user-a';

final _june15 = BusinessDate.of(2026, 6, 15);

/// A picker that returns a file without an OS dialog, at the point the real one would.
class _SyntheticSource implements AttachmentSource {
  _SyntheticSource(this.directory);

  /// The one name every picked file carries, so an assertion can be about the name.
  static const fileName = 'z-report.jpg';

  final Directory directory;
  int picks = 0;

  @override
  Set<AttachmentIntake> get available => const {
    AttachmentIntake.camera,
    AttachmentIntake.gallery,
    AttachmentIntake.file,
  };

  @override
  Future<PickedFile?> pick(AttachmentIntake intake) async {
    picks++;
    final file = File('${directory.path}/picked-$picks-$fileName')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.generate(2048, (i) => (i * 37) % 251));
    return PickedFile(
      file: file,
      fileName: fileName,
      contentType: 'image/jpeg',
    );
  }
}

Principal _principal({Set<String> units = const {_ccr, _hki}}) => Principal(
  userId: _userA,
  grants: [
    for (final unit in units)
      for (final capability in const [
        Capability.revenueCreate,
        Capability.revenueView,
        Capability.revenueEdit,
        Capability.mastersView,
        Capability.attachmentUpload,
        Capability.attachmentView,
      ])
        CapabilityGrant(capability, businessUnitId: unit),
  ],
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
  late _SyntheticSource source;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    repository = RevenueRepository(db, tax: RevenueTaxRepository(db));
    root = await Directory.systemTemp.createTemp('krishna_revenue_ui');
    source = _SyntheticSource(Directory('${root.path}/incoming'));

    for (final unit in const [
      (_ccr, 'CCR', 'Crystal Canopy Rooftop'),
      (_hki, 'HKI', 'Hotel Krishna Imperial'),
    ]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [unit.$1, unit.$2, unit.$3],
      );
    }
    for (final c in const [
      (vCategoryRestaurant, _ccr, 'RESTAURANT', 'Restaurant', 1),
      (vCategoryNandbhog, _ccr, 'NANDBHOG', 'Nandbhog', 2),
      (vCategoryRoom, _hki, 'ROOM', 'Room', 1),
      (vCategoryBanquet, _hki, 'BANQUET', 'Banquet', 2),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, ?, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$4, c.$5],
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
    for (final unit in const [_ccr, _hki]) {
      await db.customStatement(
        'INSERT OR REPLACE INTO revenue_config_snapshots (user_id, org_id, '
        'business_unit_id, status, datasets, generation, confirmed_at, '
        'updated_at) '
        "VALUES ('$_userA', '$_org', ?, 'complete', "
        "'bands,rules,statuses,subtypes', '900', ?, ?)",
        [
          unit,
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    }
  });

  tearDown(() async {
    await db.close();
    // Windows keeps a handle open briefly after a staged write, and a failed cleanup of
    // a temporary directory is not a finding about the product.
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // ignored
    }
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Principal? principal,
    Size size = const Size(430, 932),
    ThemeData? theme,
  }) async {
    final actor = principal ?? _principal();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          outboxProvider.overrideWithValue(OutboxRepository(db)),
          sessionProvider.overrideWith(
            () => StubSession(
              readySession(
                authority: AuthoritySnapshot(
                  userId: actor.userId,
                  orgId: _org,
                  grants: actor.grants,
                  resolvedAt: DateTime.now().toUtc(),
                ),
              ),
            ),
          ),
          principalProvider.overrideWithValue(actor),
          currentBusinessDateProvider.overrideWithValue(_june15),
          // The one injection, at the boundary the harness cannot cross.
          attachmentSourceProvider.overrideWithValue(source),
          attachmentStagingProvider.overrideWithValue(
            AttachmentStagingService(
              resolveStagingDirectory: () async =>
                  Directory('${root.path}/staging')
                    ..createSync(recursive: true),
            ),
          ),
        ],
        child: MaterialApp(theme: theme ?? AppTheme.mobile, home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// Taps a control whose handler does **real** file I/O, and waits for the result.
  ///
  /// Staging copies bytes into app-private storage, which is genuine `dart:io`. A test
  /// body runs inside the fake-async zone, where `pumpAndSettle` drives a fake clock and
  /// returns as soon as no frame is scheduled — so it can return long before that copy
  /// has finished, and the assertion after it would be about a form that has not been
  /// told yet. `runAsync` lets the real event loop turn, which is what the copy waits on.
  ///
  /// **It waits for the file, not for a number of turns.** A fixed count of pumps is a
  /// wall-clock race: it passes alone and fails under a full suite, which is precisely the
  /// timing-dependent assertion D-075 records — one that impersonates a product defect.
  Future<void> tapAndStage(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump();
      if (find.text(_SyntheticSource.fileName).evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    fail('the staged file never reached the form');
  }

  /// Stages a file straight into app-private storage, for a fixture that needs one
  /// already recorded rather than one picked through the interface.
  ///
  /// Wrapped in `runAsync` because staging is genuine `dart:io`: a test body runs inside
  /// the fake-async zone, where an await on real file I/O simply never completes — which
  /// presents as a hung test rather than as a failed one.
  Future<DocumentAttachment> stageFile(
    WidgetTester tester,
    String entryId,
    String name,
  ) async {
    final staged = await tester.runAsync(() async {
      final service = AttachmentStagingService(
        resolveStagingDirectory: () async =>
            Directory('${root.path}/staging')..createSync(recursive: true),
      );
      return service.stage(
        source: File('${root.path}/fixture-$name')
          ..createSync(recursive: true)
          ..writeAsBytesSync(List<int>.filled(900, 7)),
        ownerId: entryId,
        fileName: name,
        contentType: 'image/jpeg',
      );
    });
    return staged!.toDomain();
  }

  /// A sale already in the ledger, optionally already numbered by the server.
  Future<RevenueEntry> recorded({
    String id = 'entry-1',
    String category = vCategoryRestaurant,
    String? number = 'KI-REV-26-27-000001',
    bool voided = false,
  }) async {
    final unit = category == vCategoryRoom || category == vCategoryBanquet
        ? _hki
        : _ccr;
    final draft = RevenueEntryDraft(
      id: id,
      businessUnitId: unit,
      revenueCategoryId: category,
      businessDate: _june15,
      capturedAt: DateTime.now().toUtc(),
      components: [
        RevenueComponentDraft(
          id: '$id-c0',
          enteredAmount: Money.fromPaise(10000000),
        ),
      ],
    );
    final authority = AuthoritySnapshot(
      userId: _userA,
      orgId: _org,
      grants: _principal().grants,
      resolvedAt: DateTime.now().toUtc(),
    );
    final decision = await repository.evaluate(draft, authority: authority);
    await repository.createLocally(
      draft,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: _userA,
      orgId: _org,
      mutationId: 'mut-$id',
      now: DateTime.now().toUtc(),
    );
    if (number != null) {
      await repository.reconcileAcceptance(
        RevenueAcceptance(
          entryId: id,
          rowVersion: 1,
          txnNumber: number,
          financialYear: '2026',
          serverUpdatedAt: DateTime.now().toUtc(),
        ),
      );
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'done' WHERE entity_id = ?",
        [id],
      );
    }
    if (voided) {
      await repository.voidLocally(
        entryId: id,
        reason: 'duplicate entry',
        actorUserId: _userA,
        baseRowVersion: 1,
        mutationId: 'void-$id',
        now: DateTime.now().toUtc(),
      );
    }
    return (await repository.load(id))!;
  }

  group('the Android entry form (§18, §38)', () {
    uiTest('attaching is behind More details and is never required', (
      tester,
    ) async {
      await pump(tester, const RevenueEntryPage());
      await tapKey(tester, 'revenue-unit-CCR');
      await tapKey(tester, 'revenue-category-RESTAURANT');

      // The fast path is untouched: nothing about evidence is on screen until asked for.
      expect(find.byKey(const Key('attach-file')), findsNothing);

      await tapKey(tester, 'revenue-more-details');
      expect(find.byKey(const Key('attach-file')), findsOneWidget);
      expect(find.byKey(const Key('attach-camera')), findsOneWidget);
      expect(find.byKey(const Key('attach-gallery')), findsOneWidget);
    });

    uiTest('a picked file is staged and shown by name', (tester) async {
      await pump(tester, const RevenueEntryPage());
      await tapKey(tester, 'revenue-unit-CCR');
      await tapKey(tester, 'revenue-category-RESTAURANT');
      await tapKey(tester, 'revenue-more-details');
      await tapAndStage(tester, 'attach-file');

      expect(source.picks, 1);
      expect(find.text('z-report.jpg'), findsOneWidget);
      expect(
        find.text('Attached'),
        findsOneWidget,
        reason: 'staged, and honestly not yet anywhere else',
      );
    });

    uiTest('saving the sale writes the evidence against it', (tester) async {
      await pump(tester, const RevenueEntryPage());
      await tapKey(tester, 'revenue-unit-CCR');
      await tapKey(tester, 'revenue-category-RESTAURANT');
      await tester.enterText(find.byType(TextField).first, '100000');
      await tester.pumpAndSettle();
      await tapKey(tester, 'revenue-more-details');
      await tapAndStage(tester, 'attach-file');
      await tapKey(tester, 'revenue-save');

      final rows = await db.select(db.revenueEntries).get();
      expect(rows, hasLength(1));
      final files = await repository.attachmentsOf(rows.single.id);
      expect(files, hasLength(1));
      expect(
        files.single.uploadState.name,
        'waitingForExpense',
        reason: 'the server has not accepted the sale yet (D-073 §2)',
      );
      // And the sale is exactly what it would have been without a file.
      final entry = (await repository.load(rows.single.id))!;
      expect(entry.gross.paise, 10000000);
      expect(entry.tax.paise, 476190);
    });

    uiTest('an untaxed category is unaffected by attaching', (tester) async {
      await pump(tester, const RevenueEntryPage());
      await tapKey(tester, 'revenue-unit-HKI');
      await tapKey(tester, 'revenue-category-BANQUET');
      await tester.enterText(find.byType(TextField).first, '40343');
      await tester.pumpAndSettle();
      await tapKey(tester, 'revenue-more-details');
      await tapAndStage(tester, 'attach-file');
      await tapKey(tester, 'revenue-save');

      final rows = await db.select(db.revenueEntries).get();
      final entry = (await repository.load(rows.single.id))!;
      expect(
        entry.tax.paise,
        0,
        reason: 'No GST, and evidence does not add any',
      );
      expect(entry.gross, entry.net);
      expect(await repository.attachmentsOf(rows.single.id), hasLength(1));
    });

    uiTest('a staged file can be taken back out before saving', (tester) async {
      await pump(tester, const RevenueEntryPage());
      await tapKey(tester, 'revenue-unit-CCR');
      await tapKey(tester, 'revenue-category-RESTAURANT');
      await tapKey(tester, 'revenue-more-details');
      await tapAndStage(tester, 'attach-file');
      expect(find.text('z-report.jpg'), findsOneWidget);

      // Not removal — nothing has been recorded to remove (D-072a).
      await tester.tap(find.byTooltip('Take this file back out'));
      await tester.pumpAndSettle();
      expect(find.text('z-report.jpg'), findsNothing);
    });
  });

  group('the detail surface, on both shells (§19, §38, §39)', () {
    uiTest('a recorded sale shows an evidence section and an attach control', (
      tester,
    ) async {
      await recorded();
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      expect(find.byKey(const Key('revenue-evidence')), findsOneWidget);
      expect(find.text('EVIDENCE'), findsOneWidget);
      expect(find.byKey(const Key('attach-file')), findsOneWidget);
    });

    uiTest('attaching after the sale is synced changes no figure', (
      tester,
    ) async {
      final before = await recorded();
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));
      await tapAndStage(tester, 'attach-file');

      final after = (await repository.load('entry-1'))!;
      expect(after.gross, before.gross);
      expect(after.tax, before.tax);
      expect(after.net, before.net);
      expect(after.rowVersion, before.rowVersion);
      expect(after.txnNumber, before.txnNumber);
      expect(after.businessDate.iso, before.businessDate.iso);
      expect(after.attachments, hasLength(1));
      expect(
        after.attachments.single.uploadState.name,
        'pendingUpload',
        reason:
            'the sale is already numbered, so the file is uploadable at once',
      );
    });

    uiTest('the file name and state are shown, and no storage key is', (
      tester,
    ) async {
      await recorded();
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));
      await tapAndStage(tester, 'attach-file');

      expect(find.text('z-report.jpg'), findsOneWidget);
      expect(find.text('Pending upload'), findsOneWidget);
      expect(
        find.textContaining('org/'),
        findsNothing,
        reason: 'a path is implementation, not information (spec §15.2)',
      );
      expect(find.textContaining('expense-attachments'), findsNothing);
    });

    uiTest('a voided sale shows its evidence and offers no attach control', (
      tester,
    ) async {
      await recorded();
      await repository.attachLocally(
        entryId: 'entry-1',
        staged: [await stageFile(tester, 'entry-1', 'banquet-bill.jpg')],
        actorUserId: _userA,
        orgId: _org,
        now: DateTime.now().toUtc(),
      );
      await repository.voidLocally(
        entryId: 'entry-1',
        reason: 'duplicate entry',
        actorUserId: _userA,
        baseRowVersion: 1,
        mutationId: 'void-1',
        now: DateTime.now().toUtc(),
      );

      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      expect(
        find.text('banquet-bill.jpg'),
        findsOneWidget,
        reason: 'evidence for what was recorded is what an audit needs (§30)',
      );
      expect(find.byKey(const Key('attach-file')), findsNothing);
      expect(
        find.byKey(const Key('revenue-evidence-voided')),
        findsOneWidget,
        reason: 'a missing control is explained rather than merely absent',
      );
    });

    uiTest('a voided sale with no evidence says so plainly', (tester) async {
      await recorded(voided: true);
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      expect(find.byKey(const Key('revenue-evidence-none')), findsOneWidget);
      expect(find.byKey(const Key('attach-file')), findsNothing);
    });
  });

  group('layout at real sizes (§38, §39, D-123)', () {
    for (final (name, size, theme) in [
      ('a phone', const Size(430, 932), AppTheme.mobile),
      ('a 1366pt laptop', const Size(1366, 768), AppTheme.desktop),
      ('a maximised screen', const Size(1920, 1080), AppTheme.desktop),
    ]) {
      uiTest('the evidence surface renders on $name', (tester) async {
        await recorded();
        await pump(
          tester,
          const RevenueDetailPage(entryId: 'entry-1'),
          size: size,
          theme: theme,
        );
        await tapAndStage(tester, 'attach-file');

        // Slice 8 and Slice 9 both shipped an overflow that only appeared at one width
        // and in one state, and both would have looked correct in a screenshot because
        // the figures still fitted (D-119, D-123).
        expect(tester.takeException(), isNull);
        expect(find.text('z-report.jpg'), findsOneWidget);
      });
    }
  });
}
