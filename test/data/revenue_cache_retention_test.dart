/// Revenue inherits D-070 and D-074 rather than getting a second policy (Slice 3).
///
/// The expense engine already answers every question these tests ask, and answers them
/// the hard way — through two defects found on real devices. Revenue reuses the answers,
/// and these tests exist to prove the reuse is real rather than assumed:
///
/// * a confirmed revocation purges **synced** revenue and spares the actor's **unsent**
///   attempt, stamped and unbrowsable (D-070);
/// * a retained attempt is never handed to the next person who happens to hold the same
///   business unit — restoring browsability requires **ownership**, not just scope
///   (D-074). Removing that predicate must fail these tests, and does.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ScopeCachePurge purge;
  final now = DateTime.utc(2026, 6, 15, 9, 30);

  AuthoritySnapshot snapshotFor(
    String userId,
    Set<String> units, {
    bool orgWide = false,
  }) => AuthoritySnapshot(
    userId: userId,
    orgId: 'org-1',
    resolvedAt: now,
    grants: [
      if (orgWide)
        const CapabilityGrant(Capability.expenseViewAll)
      else
        for (final unit in units)
          CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
    ],
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    for (final unit in const [(_ccr, 'CCR'), (_hki, 'HKI')]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, 'org-1', ?, ?, 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
        "'2026-06-01T00:00:00.000Z')",
        [unit.$1, unit.$2, unit.$2],
      );
    }
    purge = ScopeCachePurge(db);
  });

  tearDown(() => db.close());

  /// A revenue entry with one component.
  ///
  /// [pendingMutationId] non-null, or an outbox row that is not `done`, is what makes it
  /// *the actor's unsent work* rather than canonical server data — the distinction the
  /// whole retention policy turns on.
  Future<void> entry(
    String id, {
    String unit = _ccr,
    String actor = 'user-1',
    bool synced = true,
  }) async {
    await db.customStatement(
      'INSERT INTO revenue_entries (id, org_id, business_unit_id, '
      'revenue_category_id, business_date, pnl_period_key, captured_at, '
      'entry_kind, created_by, pending_mutation_id, row_version, updated_at) '
      "VALUES (?, 'org-1', ?, 'cat-x', '2026-06-15', '2026-06', "
      "'2026-06-15T09:00:00.000Z', 'daily_summary', ?, ?, 1, "
      "'2026-06-15T09:00:00.000Z')",
      [id, unit, actor, synced ? null : 'mut-$id'],
    );
    await db.customStatement(
      'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
      'entered_amount_minor, entered_basis, gross_amount_minor, '
      'tax_amount_minor, net_amount_minor, tax_rule_id, '
      'tax_rate_basis_points, tax_treatment) '
      "VALUES (?, 'org-1', ?, 10000000, 'inclusive_total', 10000000, 476190, "
      "9523810, 'rule-1', 500, 'inclusive')",
      ['$id-c1', id],
    );
    if (!synced) {
      await db.customStatement(
        'INSERT INTO sync_outbox (mutation_id, entity_type, entity_id, op, '
        'payload, status, attempt_count, next_attempt_at, created_at, '
        'actor_user_id) '
        "VALUES (?, 'revenue_entry', ?, 'create', '{}', 'pending', 0, "
        "'2026-06-15T09:00:00.000Z', '2026-06-15T09:00:00.000Z', ?)",
        ['mut-$id', id, actor],
      );
    }
  }

  Future<List<String>> browsable() async => [
    for (final r
        in await db
            .customSelect(
              'SELECT id FROM revenue_entries WHERE scope_revoked_at IS NULL '
              'ORDER BY id',
            )
            .get())
      r.data['id'] as String,
  ];

  Future<List<String>> stamped() async => [
    for (final r
        in await db
            .customSelect(
              'SELECT id FROM revenue_entries WHERE scope_revoked_at IS NOT NULL '
              'ORDER BY id',
            )
            .get())
      r.data['id'] as String,
  ];

  Future<int> countOf(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']!
          as int;

  group('a confirmed revocation', () {
    test('purges synced revenue for the revoked unit', () async {
      await entry('synced-ccr');
      await entry('synced-hki', unit: _hki);

      final result = await purge.purgeUnits({_ccr});

      expect(await browsable(), ['synced-hki']);
      expect(result.rowsRemoved['revenue_entries'], 1);
      expect(
        result.rowsRemoved['revenue_components'],
        1,
        reason: 'components go with their entry, not left orphaned',
      );
      expect(
        await countOf('revenue_components'),
        1,
        reason: 'only the surviving entry keeps its component',
      );
    });

    test("spares the actor's unsent attempt, stamped and unbrowsable", () async {
      await entry('synced', synced: true);
      await entry('unsent', synced: false);

      final result = await purge.purgeUnits({_ccr});

      expect(await browsable(), isEmpty);
      expect(await stamped(), ['unsent']);
      expect(result.documentsRetainedForUnsyncedWork, contains('unsent'));
      expect(
        await countOf('revenue_entries'),
        1,
        reason: 'the synced one is gone; the unsent one is kept whole',
      );
      expect(
        await countOf('revenue_components'),
        1,
        reason:
            'a half-deleted entry could not be inspected, which is why it was kept',
      );
    });

    test('purges the revenue reference caches for that unit', () async {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES ('cat-x', 'org-1', ?, 'X', 'X', 1, 1, "
        "'2026-06-01T00:00:00.000Z')",
        [_ccr],
      );
      await db.customStatement(
        'INSERT INTO revenue_value_bands (id, org_id, revenue_category_id, '
        'code, label, floor_minor, ceiling_minor, row_version, updated_at) '
        "VALUES ('band-1', 'org-1', 'cat-x', 'LOW', 'Lower', 0, 750000, 1, "
        "'2026-06-01T00:00:00.000Z')",
      );
      await db.customStatement(
        'INSERT INTO business_unit_tax_statuses (id, org_id, business_unit_id, '
        'effective_from, status_code, row_version, updated_at) '
        "VALUES ('st-1', 'org-1', ?, '2026-04-01', 'STATUS_A', 1, "
        "'2026-06-01T00:00:00.000Z')",
        [_ccr],
      );

      await purge.purgeUnits({_ccr});

      expect(await countOf('revenue_value_bands'), 0);
      expect(await countOf('business_unit_tax_statuses'), 0);
    });

    test(
      'a retained entry stays explainable after its reference cache is purged',
      () async {
        // D-070 §11. The component's own snapshot is the explanation; nothing it needs
        // lives in a row a revocation may legitimately delete.
        await entry('unsent', synced: false);
        await purge.purgeUnits({_ccr});

        final row = await db
            .customSelect(
              'SELECT tax_rule_id, tax_rate_basis_points, tax_treatment, '
              'entered_basis, gross_amount_minor, tax_amount_minor, '
              'net_amount_minor FROM revenue_components',
            )
            .getSingle();
        expect(row.data['tax_rate_basis_points'], 500);
        expect(row.data['tax_treatment'], 'inclusive');
        expect(row.data['entered_basis'], 'inclusive_total');
        expect(row.data['tax_amount_minor'], 476190);
      },
    );

    test('unknown authority purges nothing', () async {
      await entry('synced');

      final result = await purge.applyTo(
        const AuthorityRefresh.unavailable(AuthorityUnavailableReason.offline),
        previous: snapshotFor('user-1', {_ccr, _hki}),
      );

      expect(result.skippedReason, isNotNull);
      expect(await browsable(), ['synced']);
    });
  });

  group('D-074 — a retained revenue entry belongs to whoever queued it', () {
    test('another user with the same scope does not get it', () async {
      await entry('unsent', actor: 'user-1', synced: false);
      await purge.purgeUnits({_ccr});
      expect(await stamped(), ['unsent']);

      // user-2 signs in and legitimately holds Crystal Canopy.
      await purge.applyTo(
        AuthorityRefresh.confirmed(snapshotFor('user-2', {_ccr})),
        previous: snapshotFor('user-2', const {}),
      );

      expect(
        await browsable(),
        isEmpty,
        reason:
            "holding the unit does not make user-2 the author of user-1's work",
      );
      expect(await stamped(), ['unsent']);
    });

    test('an org-wide holder does not inherit it either', () async {
      await entry('unsent', actor: 'user-1', synced: false);
      await purge.purgeUnits({_ccr});

      await purge.applyTo(
        AuthorityRefresh.confirmed(
          snapshotFor('user-2', const {}, orgWide: true),
        ),
        previous: snapshotFor('user-2', const {}),
      );

      expect(
        await browsable(),
        isEmpty,
        reason: 'a wider grant is no evidence of authorship (D-025, D-074)',
      );
    });

    test('its own actor signing back in does get it', () async {
      await entry('unsent', actor: 'user-1', synced: false);
      await purge.purgeUnits({_ccr});

      await purge.applyTo(
        AuthorityRefresh.confirmed(snapshotFor('user-1', {_ccr})),
        previous: snapshotFor('user-1', const {}),
      );

      expect(await browsable(), ['unsent']);
      expect(await stamped(), isEmpty);
    });

    test('an entry whose work has completed stays stamped', () async {
      // Nothing is left to reconcile, so there is nothing to un-hide it for. The server
      // re-sends it on the next pull, which is where a canonical projection comes from.
      await entry('unsent', actor: 'user-1', synced: false);
      await purge.purgeUnits({_ccr});
      await db.customStatement("UPDATE sync_outbox SET status = 'done'");
      await db.customStatement(
        'UPDATE revenue_entries SET pending_mutation_id = NULL',
      );

      await purge.applyTo(
        AuthorityRefresh.confirmed(snapshotFor('user-1', {_ccr})),
        previous: snapshotFor('user-1', const {}),
      );

      expect(await browsable(), isEmpty);
    });
  });

  group('sign-out fails closed', () {
    test(
      'quarantine hides revenue as well as expenses, destroying neither',
      () async {
        await entry('a');
        await entry('b', unit: _hki);

        final stampedCount = await purge.quarantineAllDocuments();

        expect(stampedCount, 2);
        expect(await browsable(), isEmpty);
        expect(
          await countOf('revenue_entries'),
          2,
          reason: 'nothing browsable, nothing destroyed',
        );
        expect(await countOf('revenue_components'), 2);
      },
    );
  });
}
