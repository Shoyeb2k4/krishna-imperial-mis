/// Revenue records how its current business date was established (spec §9, D-019).
///
/// The server owns the answer; this suite covers the three things a host test can decide:
/// that the stored vocabulary is pinned rather than coincidental, that a v12 device
/// upgrades without inventing a correction, and that the client copies the server's answer
/// instead of deriving one.
///
/// **Why the wire names are pinned separately from `.name`.** They agree today, and that is
/// exactly the shape of D-104: `EnteredBasis` was written and read through `.name` while
/// both schemas stored the snake-case form, and every rule carrying one would have thrown
/// on read. It survived three slices because nothing crossed the boundary. A wire name that
/// is a coincidence is a wire name waiting to break, so it is stated and asserted.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/expense_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  group('the stored vocabulary is stated, not coincidental', () {
    test('every source has the exact string both schemas hold', () {
      expect(BusinessDateSource.derived.wireName, 'derived');
      expect(BusinessDateSource.manual.wireName, 'manual');
      expect(BusinessDateSource.corrected.wireName, 'corrected');
    });

    test('the wire form round-trips, and an unknown value throws', () {
      for (final source in BusinessDateSource.values) {
        expect(BusinessDateSource.fromWire(source.wireName), source);
      }
      // No safe default exists: guessing between "the cut-off derived this" and
      // "somebody moved it" would answer a provenance question with a shrug.
      expect(
        () => BusinessDateSource.fromWire('businessDateSource'),
        throwsArgumentError,
      );
      expect(() => BusinessDateSource.fromWire(''), throwsArgumentError);
    });

    test('the server admits exactly the two values revenue can produce', () {
      // Read from the migration rather than restated here, so the two cannot be edited
      // into agreement with each other.
      final sql = File(
        'supabase/migrations/20260905190229_revenue_business_date_provenance.sql',
      ).readAsStringSync();
      expect(sql, contains("in ('derived', 'corrected')"));
      expect(
        sql,
        isNot(contains("'manual'")),
        reason:
            'no revenue surface offers a trading day at entry, so `manual` has no '
            'producer — a column admitting it would claim the system can do something '
            'it cannot',
      );
    });

    test('revenue_create takes no provenance argument', () {
      // The server owns it. A parameter would be a caller asserting its own provenance,
      // which is the shape the migration audit already forbids for authority claims.
      final sql = File(
        'supabase/migrations/20260905190229_revenue_business_date_provenance.sql',
      ).readAsStringSync();
      final createHeader = sql.substring(
        sql.indexOf('create or replace function public.revenue_create('),
        sql.indexOf('returns jsonb language plpgsql security definer'),
      );
      expect(createHeader, isNot(contains('business_date_source')));
    });
  });

  group('a v12 device upgrades without inventing a correction', () {
    test(
      'an existing revenue entry becomes derived, and keeps everything else',
      () async {
        final file = await createTempDatabaseFile();
        addTearDown(() => file.parent.deleteSync(recursive: true));

        // A v12-shaped revenue entry, written before the column existed. Raw SQL, because
        // building it from today's table classes would create the column and prove nothing.
        final raw = sqlite3.open(file.path);
        raw
          ..execute('PRAGMA user_version = 12')
          // Every real database of this version carries the expense tables: they
          // arrive at v7. Omitting them made the fixture a schema nobody has had,
          // which only surfaced once a later step read them (D-159).
          ..execute(v7ExpenseTablesDdl[0])
          ..execute(v7ExpenseTablesDdl[1])
          ..execute(v7ExpenseTablesDdl[2])
          ..execute('''
          CREATE TABLE revenue_entries (
            id TEXT NOT NULL PRIMARY KEY, org_id TEXT NOT NULL,
            txn_number TEXT NULL, financial_year TEXT NULL,
            business_unit_id TEXT NOT NULL, revenue_category_id TEXT NOT NULL,
            business_date TEXT NOT NULL, pnl_period_key TEXT NOT NULL,
            captured_at TEXT NOT NULL,
            entry_kind TEXT NOT NULL DEFAULT 'daily_summary',
            source_reference TEXT NULL, notes TEXT NULL, created_by TEXT NOT NULL,
            voided_at TEXT NULL, voided_by TEXT NULL, void_reason TEXT NULL,
            pending_mutation_id TEXT NULL,
            row_version INTEGER NOT NULL DEFAULT 1,
            server_updated_at TEXT NULL, updated_at TEXT NOT NULL,
            scope_revoked_at TEXT NULL
          )
        ''')
          ..execute('''
          CREATE TABLE revenue_components (
            id TEXT NOT NULL PRIMARY KEY, org_id TEXT NOT NULL,
            revenue_entry_id TEXT NOT NULL,
            entered_amount_minor INTEGER NOT NULL, entered_basis TEXT NOT NULL,
            gross_amount_minor INTEGER NOT NULL, tax_amount_minor INTEGER NOT NULL,
            net_amount_minor INTEGER NOT NULL,
            tax_rule_id TEXT NOT NULL, tax_rate_basis_points INTEGER NOT NULL,
            tax_treatment TEXT NOT NULL,
            value_band_id TEXT NULL, value_band_label TEXT NULL,
            value_band_floor_minor INTEGER NULL, value_band_ceiling_minor INTEGER NULL,
            supply_subtype_id TEXT NULL, supply_subtype_label TEXT NULL,
            premises_status_code TEXT NULL
          )
        ''')
          ..execute('''
          INSERT INTO revenue_entries (
            id, org_id, txn_number, financial_year, business_unit_id,
            revenue_category_id, business_date, pnl_period_key, captured_at,
            entry_kind, notes, created_by, row_version, updated_at)
          VALUES (
            'rev-1', 'org-1', 'KI-REV-26-27-000042', '26-27', 'unit-ccr',
            'cat-restaurant', '2026-06-15', '2026-06', '2026-06-15T09:00:00.000Z',
            'daily_summary', 'a pre-v13 sale', 'user-1', 4, '2026-06-15T09:00:00.000Z')
        ''')
          ..execute('''
          INSERT INTO revenue_components (
            id, org_id, revenue_entry_id, entered_amount_minor, entered_basis,
            gross_amount_minor, tax_amount_minor, net_amount_minor,
            tax_rule_id, tax_rate_basis_points, tax_treatment)
          VALUES (
            'comp-1', 'org-1', 'rev-1', 10000000, 'inclusive_total',
            10000000, 476190, 9523810, 'rule-1', 500, 'inclusive')
        ''')
          ..close();

        final db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();

        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.data.values.first, db.schemaVersion);

        final row = (await db.select(db.revenueEntries).get()).single;
        expect(
          row.businessDateSource,
          BusinessDateSource.derived.wireName,
          reason:
              'nothing infers a past correction from updated_at, a row version, notes '
              'or a date comparison — none of those is evidence',
        );

        // And the migration corrupted nothing it was not asked to touch.
        expect(row.txnNumber, 'KI-REV-26-27-000042');
        expect(row.financialYear, '26-27');
        expect(row.rowVersion, 4);
        expect(row.businessDate, '2026-06-15');
        expect(row.pnlPeriodKey, '2026-06');
        expect(row.voidedAt, isNull);
        expect(row.pendingMutationId, isNull);
        expect(row.notes, 'a pre-v13 sale');

        final component = (await db.select(db.revenueComponents).get()).single;
        expect(component.grossAmountMinor, 10000000);
        expect(component.taxAmountMinor, 476190);
        expect(component.netAmountMinor, 9523810);
        expect(component.taxRateBasisPoints, 500);
        expect(component.enteredBasis, 'inclusive_total');
      },
    );

    test(
      'a fresh database is born with the column, defaulting to derived',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();

        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.data.values.first, db.schemaVersion);

        final columns = await db
            .customSelect("PRAGMA table_info('revenue_entries')")
            .get();
        final provenance = columns.where(
          (c) => c.data['name'] == 'business_date_source',
        );
        expect(provenance, hasLength(1));
        expect(provenance.single.data['notnull'], 1);
        expect(provenance.single.data['dflt_value'], "'derived'");
      },
    );
  });

  group('the client copies the server answer rather than deriving one', () {
    late AppDatabase db;
    late RevenueRepository repository;
    final now = DateTime.utc(2026, 6, 15, 9, 30);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.customStatement('PRAGMA foreign_keys = ON');
      await seedMasterData(db, now: now);
      repository = RevenueRepository(db, tax: RevenueTaxRepository(db));
    });

    tearDown(() => db.close());

    /// A locally recorded sale, written straight into the read model.
    Future<void> seedEntry({String source = 'derived'}) => db
        .into(db.revenueEntries)
        .insert(
          RevenueEntriesCompanion.insert(
            id: 'rev-1',
            orgId: seedOrgId,
            businessUnitId: 'unit-1',
            revenueCategoryId: 'cat-1',
            businessDate: '2026-06-15',
            pnlPeriodKey: '2026-06',
            capturedAt: now,
            createdBy: 'user-1',
            businessDateSource: Value(source),
            updatedAt: now,
          ),
        );

    Future<String> storedSource() async =>
        (await db.select(db.revenueEntries).getSingle()).businessDateSource;

    test('an acceptance that states corrected is written through', () async {
      await seedEntry();
      await repository.reconcileAcceptance(
        const RevenueAcceptance(
          entryId: 'rev-1',
          rowVersion: 2,
          businessDateSource: BusinessDateSource.corrected,
        ),
      );
      expect(await storedSource(), 'corrected');
    });

    test('an acceptance that states derived does not un-correct a row', () async {
      // The server preserves provenance across an ordinary edit, so an acceptance for a
      // corrected row states `corrected` again. This asserts the client writes what it is
      // told rather than second-guessing it — and the case that would matter if the
      // server ever did say `derived` is the next test.
      await seedEntry(source: 'corrected');
      await repository.reconcileAcceptance(
        const RevenueAcceptance(
          entryId: 'rev-1',
          rowVersion: 3,
          businessDateSource: BusinessDateSource.corrected,
        ),
      );
      expect(await storedSource(), 'corrected');
    });

    test('an acceptance that states nothing leaves the value alone', () async {
      // A replayed result stored by an older build. D-072a's rule: a field the server did
      // not restate is not written, because writing every field back is how the
      // transaction number was erased on every edit.
      await seedEntry(source: 'corrected');
      await repository.reconcileAcceptance(
        const RevenueAcceptance(entryId: 'rev-1', rowVersion: 5),
      );
      expect(
        await storedSource(),
        'corrected',
        reason: 'silence is not an instruction to reset the provenance',
      );
      expect((await db.select(db.revenueEntries).getSingle()).rowVersion, 5);
    });

    test('the acceptance parser reads the server field, and only that', () {
      final accepted = RevenueAcceptance.fromResult('rev-1', const {
        'row_version': 2,
        'txn_number': 'KI-REV-26-27-000001',
        'business_date_source': 'corrected',
      });
      expect(accepted!.businessDateSource, BusinessDateSource.corrected);

      final silent = RevenueAcceptance.fromResult('rev-1', const {
        'row_version': 2,
      });
      expect(silent!.businessDateSource, isNull);

      // An unrecognised value throws rather than defaulting, for the same reason
      // `fromWire` does: there is no safe guess about how a trading day came to be.
      expect(
        () => RevenueAcceptance.fromResult('rev-1', const {
          'row_version': 2,
          'business_date_source': 'invented',
        }),
        throwsArgumentError,
      );
    });

    test('a queued correction does not claim the date was corrected', () async {
      // The local write is an *attempt*. The server decides whether the date really
      // moved, whether this actor may move it and whether the period allows it — so a
      // refused correction must not leave a device claiming a corrected trading day.
      await seedEntry();
      final queuedPayload = jsonEncode({'p_id': 'rev-1'});
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              mutationId: 'm-1',
              actorUserId: const Value('user-1'),
              entityType: 'revenue_entry',
              entityId: 'rev-1',
              op: 'update',
              payload: queuedPayload,
              nextAttemptAt: now,
              status: 'pending',
              createdAt: now,
            ),
          );

      expect(
        await storedSource(),
        'derived',
        reason:
            'nothing between the operator pressing save and the server accepting it '
            'may write the provenance',
      );
    });
  });
}
