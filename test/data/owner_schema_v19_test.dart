/// Local schema **v19** — the Owner Accounts foundation, and the migration that adds it.
///
/// Phase 5 OA-1. Four tables: three masters and one financial document.
///
/// What is pinned here is not the shape but the rules the shape carries.
///
/// **No balance column exists anywhere.** A closing balance is derived (OA-D2). Storing
/// one would be a second writable copy of a derivable fact, with a lifecycle to keep in
/// step through every correction, void and replay — D-157's argument, and it binds harder
/// here because a balance also depends on the P&L.
///
/// **Amounts are positive and the direction is separate**, so one withdrawal has exactly
/// one representation (§43). The three fixed-direction types are held there by a check
/// constraint rather than by the repository remembering.
///
/// **A migration configures nothing.** The tables arrive empty: no owner, no family
/// member, no share, no opening balance. Every one of those is a business fact, and
/// seeding a `0 bp` share or a `₹0` opening would be a financial claim nobody made
/// (OA-D3 — D-043's rule applied to ownership).
///
/// **The upgrade leaves everything else alone.** A device carrying revenue, expenses and
/// a synchronised reporting cache keeps all of it, byte for byte (§35).
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/auth/cache_classification.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/expense_fixtures.dart' show createTempDatabaseFile;

const _ownerTables = [
  'owners',
  'ownership_shares',
  'owner_family_members',
  'owner_ledger_entries',
];

const _ownerIndexes = [
  'ix_owner_ledger_owner_period',
  'ix_owner_ledger_unit_date',
  'ix_owner_family_owner',
  'ix_ownership_shares_owner',
];

/// Rewinds a database built from the current schema back to v18 by removing exactly what
/// v19 added.
///
/// A fixture that claims to be an older schema has to actually be one — the trap D-144 and
/// D-159 both record, and which cost this project a red suite in three files at once.
Future<void> _rewindToV18(AppDatabase db) async {
  for (final index in _ownerIndexes) {
    await db.customStatement('DROP INDEX IF EXISTS $index');
  }
  for (final table in _ownerTables) {
    await db.customStatement('DROP TABLE IF EXISTS $table');
  }
  await db.customStatement('PRAGMA user_version = 18');
}

Future<Set<String>> _objects(AppDatabase db, String type) async {
  final rows = await db
      .customSelect(
        'SELECT name FROM sqlite_master WHERE type = ?',
        variables: [Variable<String>(type)],
      )
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.read<String>('name')};
}

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // ═══════════════════════════════════════════════════════════════════════════
  group('a fresh database is born with the owner-account schema', () {
    late File file;
    late AppDatabase db;

    setUp(() async {
      file = await createTempDatabaseFile();
      db = AppDatabase(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      if (file.existsSync()) file.deleteSync();
    });

    test('opens at v19 or later', () async {
      expect(await _userVersion(db), greaterThanOrEqualTo(19));
    });

    test('all four tables and all four indexes exist', () async {
      expect(await _objects(db, 'table'), containsAll(_ownerTables));
      expect(await _objects(db, 'index'), containsAll(_ownerIndexes));
    });

    test('every table arrives empty — a migration configures nothing', () async {
      for (final table in _ownerTables) {
        final count = await db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        expect(
          count.read<int>('n'),
          0,
          reason:
              '$table must ship empty: an owner, a share and an opening balance '
              'are business facts nobody has supplied yet (OA-D3, §45, §46)',
        );
      }
    });

    test('no owner-account table carries a stored balance (OA-D2)', () async {
      // The whole of the carry-forward design: a closing balance is derived. A column
      // here would be the second copy whose lifecycle D-157 argues against.
      for (final table in _ownerTables) {
        final columns = await _columns(db, table);
        for (final forbidden in [
          'balance',
          'balance_minor',
          'closing_balance',
          'closing_balance_minor',
          'opening_balance_minor',
          'running_balance',
          'entitlement_minor',
        ]) {
          expect(
            columns,
            isNot(contains(forbidden)),
            reason:
                '$table.$forbidden would be a second financial truth source',
          );
        }
      }
    });

    test(
      'an owner carries no user id, and neither does a family member',
      () async {
        // §3 and §7: an owner is a business subject. Tying the id to an auth account would
        // mean provisioning a login granted somebody a share of the business.
        for (final table in ['owners', 'owner_family_members']) {
          final columns = await _columns(db, table);
          expect(columns, isNot(contains('user_id')));
          expect(columns, isNot(contains('auth_user_id')));
          expect(columns, isNot(contains('profile_id')));
        }
      },
    );

    test(
      'the ledger carries what a movement needs and nothing money-shaped beyond it',
      () async {
        final columns = await _columns(db, 'owner_ledger_entries');
        expect(
          columns,
          containsAll([
            'id',
            'org_id',
            'owner_id',
            'business_unit_id',
            'business_date',
            'pnl_period_key',
            'business_date_source',
            'movement_type',
            'direction',
            'amount_minor',
            'family_member_id',
            'collected_by_family_member_id',
            'nc_bill_reference',
            'payment_method_id',
            'reference_number',
            'remarks',
            'reason',
            'txn_number',
            'financial_year',
            'created_by',
            'captured_at',
            'row_version',
            'voided_at',
            'void_reason',
            'scope_revoked_at',
            'pending_mutation_id',
          ]),
        );
        // Exactly one monetary column. A second would be somewhere for a derived figure to
        // be stored, which is the move this design exists to refuse.
        expect(columns.where((c) => c.endsWith('_minor')), {'amount_minor'});
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the constraints refuse what they exist to refuse', () {
    late File file;
    late AppDatabase db;

    Future<void> insertMovement({
      String id = 'm1',
      String type = 'withdrawal',
      String direction = 'debit',
      int amount = 5000000,
      String? familyMemberId,
      String? reason,
      String businessDate = '2026-06-15',
      String periodKey = '2026-06',
    }) => db.customStatement(
      'INSERT INTO owner_ledger_entries '
      '(id, org_id, owner_id, business_unit_id, business_date, pnl_period_key, '
      ' business_date_source, movement_type, direction, amount_minor, '
      ' family_member_id, reason, created_by, captured_at, updated_at) '
      "VALUES ('$id', 'org', 'owner-a', 'ccr', '$businessDate', '$periodKey', "
      "'derived', '$type', '$direction', $amount, "
      '${familyMemberId == null ? 'NULL' : "'$familyMemberId'"}, '
      '${reason == null ? 'NULL' : "'$reason'"}, '
      "'user-1', '2026-06-15T12:00:00.000Z', '2026-06-15T12:00:00.000Z')",
    );

    setUp(() async {
      file = await createTempDatabaseFile();
      db = AppDatabase(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      if (file.existsSync()) file.deleteSync();
    });

    test('an ordinary withdrawal inserts', () async {
      await insertMovement();
      final n = await db
          .customSelect('SELECT COUNT(*) AS n FROM owner_ledger_entries')
          .getSingle();
      expect(n.read<int>('n'), 1);
    });

    test('a withdrawal stored as a credit is refused by the database', () async {
      // Not merely by the domain: a direct write cannot create the second representation
      // of one event either (§43).
      await expectLater(insertMovement(direction: 'credit'), throwsA(anything));
    });

    test('a negative amount is refused', () async {
      await expectLater(insertMovement(amount: -1), throwsA(anything));
    });

    test('an unknown movement type is refused', () async {
      await expectLater(insertMovement(type: 'drawing'), throwsA(anything));
    });

    test('only a consumption may name a consumer', () async {
      await expectLater(
        insertMovement(familyMemberId: 'fam-a1'),
        throwsA(anything),
      );
      await insertMovement(
        id: 'nc1',
        type: 'nc_consumption',
        familyMemberId: 'fam-a1',
      );
    });

    test(
      'a manual adjustment with a whitespace-only reason is refused',
      () async {
        for (final blank in ['', '   ', '\t']) {
          await expectLater(
            insertMovement(
              id: 'adj-${blank.length}-${blank.hashCode}',
              type: 'manual_adjustment',
              direction: 'credit',
              reason: blank,
            ),
            throwsA(anything),
            reason: 'spec §14.1 — whitespace is not a reason',
          );
        }
        await insertMovement(
          id: 'adj-ok',
          type: 'manual_adjustment',
          direction: 'credit',
          reason: 'agreed correction',
        );
      },
    );

    test('an opening balance may be a credit or a debit (OA-D3)', () async {
      await insertMovement(
        id: 'ob-credit',
        type: 'opening_balance',
        direction: 'credit',
      );
      await insertMovement(
        id: 'ob-debit',
        type: 'opening_balance',
        direction: 'debit',
      );
    });

    test('the period key must agree with the business date', () async {
      await expectLater(
        insertMovement(businessDate: '2026-06-15', periodKey: '2026-6'),
        throwsA(anything),
      );
    });

    test('an ownership share outside 1..10000 basis points is refused', () async {
      Future<void> insertShare(int bp, String from) => db.customStatement(
        'INSERT INTO ownership_shares '
        '(id, org_id, owner_id, share_basis_points, effective_from, updated_at) '
        "VALUES ('s-$bp-$from', 'org', 'owner-a', $bp, '$from', "
        "'2026-04-01T00:00:00.000Z')",
      );

      await expectLater(insertShare(0, '2026-04-01'), throwsA(anything));
      await expectLater(insertShare(10001, '2026-05-01'), throwsA(anything));
      await insertShare(5000, '2026-06-01');
    });

    test('an ownership share must start on the first of a month (§5)', () async {
      Future<void> insertShare(String from) => db.customStatement(
        'INSERT INTO ownership_shares '
        '(id, org_id, owner_id, share_basis_points, effective_from, updated_at) '
        "VALUES ('s-$from', 'org', 'owner-a', 5000, '$from', "
        "'2026-04-01T00:00:00.000Z')",
      );

      await expectLater(insertShare('2026-06-15'), throwsA(anything));
      await insertShare('2026-07-01');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('v18 → v19 on a device that already holds financial history (§35)', () {
    late File file;

    setUp(() async {
      file = await createTempDatabaseFile();
    });

    tearDown(() {
      // Best effort: a test that failed mid-way may still hold the handle open on
      // Windows, and a PathAccessException in teardown would mask the real failure.
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // left for the OS temp sweep
      }
    });

    test('the upgrade adds the owner schema and disturbs nothing already there', () async {
      // Build a v19 database, put real rows into the surfaces an upgrading device would
      // be carrying, then rewind the schema to v18 and let the migration run for real.
      final seeded = AppDatabase(NativeDatabase(file));
      await seeded.customSelect('SELECT 1').get();

      await seeded.customStatement(
        'INSERT INTO app_meta (key, value, updated_at) '
        "VALUES ('probe', 'kept', '2026-09-08T10:00:00.000Z')",
      );
      await seeded.customStatement(
        'INSERT INTO reporting_coverage_markers '
        '(owner_user_id, org_id, business_unit_id, dataset, financial_year, '
        ' generation, server_confirmed_at, updated_at) '
        "VALUES ('user-1', 'org', 'ccr', 'revenue', 2026, 4242, "
        "'2026-09-08T10:00:00.000Z', '2026-09-08T10:00:00.000Z')",
      );
      await seeded.customStatement(
        'INSERT INTO reporting_revenue_contributions '
        '(owner_user_id, org_id, contribution_id, revenue_entry_id, business_unit_id, '
        ' revenue_category_id, pnl_date, pnl_period_key, gross_minor, tax_minor, '
        ' net_minor, tax_treatment, tax_rate_basis_points, entered_basis, '
        ' financial_year, document_generation, synced_at) '
        "VALUES ('user-1', 'org', 'c1', 'e1', 'ccr', 'restaurant', '2026-06-15', "
        "'2026-06', 10000000, 476190, 9523810, 'inclusive', 500, 'inclusive_total', "
        "2026, 4242, '2026-09-08T10:00:00.000Z')",
      );

      final markersBefore = await seeded
          .customSelect('SELECT COUNT(*) AS n FROM reporting_coverage_markers')
          .getSingle();
      final grossBefore = await seeded
          .customSelect(
            'SELECT SUM(gross_minor) AS g FROM reporting_revenue_contributions',
          )
          .getSingle();

      await _rewindToV18(seeded);
      expect(await _userVersion(seeded), 18);
      expect(
        await _objects(seeded, 'table'),
        isNot(contains('owner_ledger_entries')),
        reason: 'the fixture must genuinely be a v18 schema',
      );
      await seeded.close();

      // Reopen: the real migration runs.
      final upgraded = AppDatabase(NativeDatabase(file));
      await upgraded.customSelect('SELECT 1').get();

      expect(await _userVersion(upgraded), greaterThanOrEqualTo(19));
      expect(await _objects(upgraded, 'table'), containsAll(_ownerTables));
      expect(await _objects(upgraded, 'index'), containsAll(_ownerIndexes));

      // Everything that was there is still there, unchanged.
      final probe = await upgraded
          .customSelect("SELECT value FROM app_meta WHERE key = 'probe'")
          .getSingle();
      expect(probe.read<String>('value'), 'kept');

      final markersAfter = await upgraded
          .customSelect('SELECT COUNT(*) AS n FROM reporting_coverage_markers')
          .getSingle();
      expect(markersAfter.read<int>('n'), markersBefore.read<int>('n'));

      final grossAfter = await upgraded
          .customSelect(
            'SELECT SUM(gross_minor) AS g FROM reporting_revenue_contributions',
          )
          .getSingle();
      expect(
        grossAfter.read<int>('g'),
        grossBefore.read<int>('g'),
        reason:
            'an owner-accounts migration must not move a single paisa of an '
            'existing reported figure (§41)',
      );

      // And the new tables are empty on an upgraded device, exactly as on a fresh one.
      for (final table in _ownerTables) {
        final n = await upgraded
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        expect(n.read<int>('n'), 0);
      }

      await upgraded.close();
    });

    test('the upgrade is idempotent across a second open', () async {
      final first = AppDatabase(NativeDatabase(file));
      await first.customSelect('SELECT 1').get();
      await _rewindToV18(first);
      await first.close();

      final second = AppDatabase(NativeDatabase(file));
      await second.customSelect('SELECT 1').get();
      await second.close();

      final third = AppDatabase(NativeDatabase(file));
      await third.customSelect('SELECT 1').get();
      expect(await _objects(third, 'table'), containsAll(_ownerTables));
      await third.close();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('cache classification (D-070, D-074, §33)', () {
    test('every owner-account table is classified', () {
      for (final table in _ownerTables) {
        expect(
          () => CacheClassification.ownershipOf(table),
          returnsNormally,
          reason:
              'an unclassified table is one nobody has decided anything about',
        );
      }
    });

    test('the three masters are organisation-global and survive a revocation', () {
      for (final table in [
        'owners',
        'ownership_shares',
        'owner_family_members',
      ]) {
        expect(
          CacheClassification.ownershipOf(table),
          CacheOwnership.organizationGlobal,
          reason:
              'an owner is an owner of the business, not of a property — losing one '
              'property does not make the masters unreadable (D-049 reasoning)',
        );
      }
      final purged = {
        for (final t in CacheClassification.purgedOnRevocation) t.name,
      };
      expect(purged, isNot(contains('owners')));
      expect(purged, isNot(contains('ownership_shares')));
      expect(purged, isNot(contains('owner_family_members')));
    });

    test(
      'the ledger is scoped financial history: purged, sparing the actor own work',
      () {
        expect(
          CacheClassification.ownershipOf('owner_ledger_entries'),
          CacheOwnership.scopedFinancialHistory,
        );

        final entry = CacheClassification.tables.firstWhere(
          (t) => t.name == 'owner_ledger_entries',
        );
        expect(entry.isPurgedOnRevocation, isTrue, reason: 'D-070');
        expect(
          entry.retainsUnsyncedWork,
          isTrue,
          reason:
              "a queued movement exists nowhere else and is not the server's to hand "
              'back (D-070, D-074)',
        );
        expect(
          entry.unitColumn,
          'business_unit_id',
          reason: 'the source property is what a revocation can act on (§10)',
        );
      },
    );

    test('the outbox is still never purged for any authority reason', () {
      // The rule the Owner Ledger relies on for its retention exception.
      expect(
        CacheClassification.ownershipOf('sync_outbox'),
        CacheOwnership.userLocal,
      );
      expect({
        for (final t in CacheClassification.neverPurged) t.name,
      }, contains('sync_outbox'));
    });
  });
}
