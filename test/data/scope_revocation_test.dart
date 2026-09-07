/// D-048 — what happens locally when the server confirms a business unit has been taken
/// away.
///
/// The dangerous half of this feature is not the deletion; it is deciding *when* to
/// delete. A purge triggered by a lost signal would make a tunnel indistinguishable from
/// a dismissal, and would quietly destroy a manager's cached working set every time the
/// lift doors closed. So the first group here is about refusing to act, and only the
/// second is about acting.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/vendor_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/cache_classification.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

/// Mutation ids are UUIDs — the server stores `mutation_id` as `uuid`, so a fixture
/// using a short label would be refused as a malformed argument before any business rule
/// ran. Derived from a name to stay readable and deterministic.
String mid(String name) =>
    const Uuid().v5('c0ffee00-0000-4000-8000-000000000000', name);

void main() {
  final ccr = seedId('bu:CCR');
  final hki = seedId('bu:HKI');
  final at = DateTime.utc(2026, 8, 28, 9);

  AuthoritySnapshot snapshot(Set<String> units, {bool orgWide = false}) =>
      AuthoritySnapshot(
        userId: 'manager',
        orgId: seedOrgId,
        resolvedAt: at,
        grants: [
          if (orgWide)
            const CapabilityGrant(Capability.mastersView)
          else
            for (final unit in units)
              CapabilityGrant(Capability.mastersView, businessUnitId: unit),
        ],
      );

  group('unknown is not revoked', () {
    for (final reason in AuthorityUnavailableReason.values) {
      test('a refresh that failed with ${reason.name} establishes nothing', () {
        final refresh = AuthorityRefresh.unavailable(reason);
        expect(refresh.establishesAuthority, isFalse);
        expect(refresh.snapshotOrNull, isNull);
      });
    }

    test('only a confirmed refresh establishes authority', () {
      expect(
        AuthorityRefresh.confirmed(snapshot({ccr})).establishesAuthority,
        isTrue,
      );
    });

    test('a first sign-in is not a mass revocation', () {
      // Nothing to compare against. Treating "I have never checked" as "everything was
      // taken away" would wipe the cache of every new installation.
      expect(snapshot({ccr}).unitsRevokedSince(null), isEmpty);
    });

    test('gaining an org-wide grant revokes nothing', () {
      // Widening authority must never look like losing it. An Owner grant names no
      // unit at all, so a naive set difference would report every previously-scoped
      // unit as revoked and purge the entire cache of a promoted user.
      final promoted = snapshot(const {}, orgWide: true);
      expect(promoted.unitsRevokedSince(snapshot({ccr, hki})), isEmpty);
      expect(promoted.holdsOrgWideGrant, isTrue);
    });

    test('losing one unit of two reports exactly that one', () {
      expect(snapshot({hki}).unitsRevokedSince(snapshot({ccr, hki})), {ccr});
    });

    test(
      'gaining a unit is reported separately, and drives a pull not a purge',
      () {
        expect(snapshot({ccr, hki}).unitsGrantedSince(snapshot({ccr})), {hki});
        expect(
          snapshot({ccr, hki}).unitsRevokedSince(snapshot({ccr})),
          isEmpty,
        );
      },
    );
  });

  group('cache classification', () {
    test('every table in the real schema has an explicit owner', () async {
      // Against the **database**, not against the list itself.
      //
      // This assertion used to iterate `CacheClassification.tables` and check that each
      // of them was in `CacheClassification.tables`, which is true by construction and
      // therefore proved nothing. Phase 3 added four expense tables, none of them was
      // classified, and this test went on passing — until sign-out threw a foreign-key
      // error on a real device, because the purge deleted a business unit that a synced
      // expense line still pointed at.
      //
      // D-048's promise was that "a new table forces a decision about what an authority
      // change does to it". A promise nothing evaluates is a comment. This evaluates it.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final actual = db.allTables.map((t) => t.actualTableName).toSet();
      final classified = CacheClassification.tables.map((t) => t.name).toSet();

      expect(
        actual.difference(classified),
        isEmpty,
        reason:
            'these tables exist in the local database and no one has said what a '
            'revocation does to them — classify them in CacheClassification',
      );
      expect(
        classified.difference(actual),
        isEmpty,
        reason:
            'these tables are classified but no longer exist; a stale entry makes the '
            'list look more complete than it is',
      );
    });

    test('the classification list agrees with itself', () {
      for (final table in CacheClassification.tables) {
        expect(
          () => CacheClassification.ownershipOf(table.name),
          returnsNormally,
        );
      }
      expect(
        () => CacheClassification.ownershipOf('some_future_table'),
        throwsArgumentError,
        reason: 'a new table must be classified before it can be cached',
      );
    });

    test('financial documents are purged, sparing unsynced work', () {
      // D-068, the project lead's final policy, reversing what the Phase 3 checkpoint
      // shipped. A confirmed revocation must not leave the revoked property's figures
      // in a browsable cache; what it must not destroy is the actor's own unsent work.
      final purged = CacheClassification.purgedOnRevocation.map((t) => t.name);
      for (final table in const [
        'expenses',
        'expense_allocations',
        'expense_period_allocations',
        'expense_attachments',
      ]) {
        expect(
          CacheClassification.ownershipOf(table),
          CacheOwnership.scopedFinancialHistory,
          reason: '$table holds documents, not reference data',
        );
        expect(
          purged,
          contains(table),
          reason: 'a revoked unit\'s synced financial cache goes (D-068)',
        );
      }

      // The exception is a property of the *kind*, so it cannot be lost by editing one
      // row of the table list.
      for (final table in CacheClassification.tables) {
        expect(
          table.retainsUnsyncedWork,
          table.ownership == CacheOwnership.scopedFinancialHistory,
          reason:
              'only financial documents have unsent work to spare; reference data '
              'has none, and nothing else is purged at all',
        );
      }
    });

    test('financial tables are deleted children-first, expenses last', () {
      // The purge deletes explicitly at every level rather than leaning on the cascade,
      // so the order in this list is the order it runs in and has to be safe on its own.
      final order = [
        for (final t in CacheClassification.purgedOnRevocation) t.name,
      ];
      expect(
        order.indexOf('expense_period_allocations'),
        lessThan(order.indexOf('expense_allocations')),
      );
      expect(
        order.indexOf('expense_allocations'),
        lessThan(order.indexOf('expenses')),
      );
      expect(
        order.indexOf('expense_attachments'),
        lessThan(order.indexOf('expenses')),
      );
    });

    test('the outbox is never in the purged set', () {
      final purged = CacheClassification.purgedOnRevocation.map((t) => t.name);
      expect(purged, isNot(contains('sync_outbox')));
      expect(purged, isNot(contains('app_meta')));
      expect(
        CacheClassification.ownershipOf('sync_outbox'),
        CacheOwnership.userLocal,
      );
    });

    test('vendors and payment methods are organisation-owned, not unit-owned', () {
      // A supplier serves the company. The server returns every vendor to anyone with
      // masters.view anywhere, so purging one locally would delete a row the next pull
      // restores — churn dressed up as security.
      expect(
        CacheClassification.ownershipOf('vendors'),
        CacheOwnership.organizationGlobal,
      );
      expect(
        CacheClassification.ownershipOf('payment_methods'),
        CacheOwnership.organizationGlobal,
      );
    });

    test(
      'children are listed before their parents, so a purge cannot orphan',
      () {
        final order = [
          for (final t in CacheClassification.purgedOnRevocation) t.name,
        ];
        expect(
          order.indexOf('expense_categories'),
          lessThan(order.indexOf('sections')),
        );
        expect(
          order.indexOf('sections'),
          lessThan(order.indexOf('departments')),
        );
        expect(
          order.indexOf('departments'),
          lessThan(order.indexOf('business_units')),
        );
        expect(
          order.indexOf('revenue_tax_rates'),
          lessThan(order.indexOf('revenue_categories')),
        );
        expect(
          order.indexOf('revenue_categories'),
          lessThan(order.indexOf('business_units')),
        );
      },
    );
  });

  group('the purge itself', () {
    late AppDatabase db;
    late ScopeCachePurge purge;
    late OutboxRepository outbox;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      purge = ScopeCachePurge(db);
      outbox = OutboxRepository(db);
      await seedMasterData(db, now: at);

      // Work the manager did before losing the property. It must survive all of this.
      await outbox.enqueue(
        PendingMutation(
          mutationId: mid('mut-1'),
          entityType: 'expense_category',
          entityId: seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
          op: MutationOp.update,
          payload: const {'name': 'Renamed while authorised'},
          baseRowVersion: 1,
          createdAt: at,
        ),
        now: at,
      );
    });

    tearDown(() => db.close());

    Future<int> count(String table) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM $table')
          .getSingle();
      return row.data['c'] as int;
    }

    test('a failed refresh purges nothing at all', () async {
      final before = await count('departments');
      final result = await purge.applyTo(
        const AuthorityRefresh.unavailable(AuthorityUnavailableReason.offline),
        previous: snapshot({ccr, hki}),
      );

      expect(result.didPurge, isFalse);
      expect(result.skippedReason, contains('authority was not confirmed'));
      expect(await count('departments'), before);
    });

    test('a confirmed refresh with no change purges nothing', () async {
      final before = await count('departments');
      final result = await purge.applyTo(
        AuthorityRefresh.confirmed(snapshot({ccr, hki})),
        previous: snapshot({ccr, hki}),
      );

      expect(result.didPurge, isFalse);
      expect(await count('departments'), before);
    });

    test(
      'losing Crystal Canopy removes its data and keeps Hotel Krishna',
      () async {
        final result = await purge.applyTo(
          AuthorityRefresh.confirmed(snapshot({hki})),
          previous: snapshot({ccr, hki}),
        );

        expect(result.didPurge, isTrue);
        expect(result.revokedUnits, {ccr});

        final units = await db.select(db.businessUnits).get();
        expect(units.map((u) => u.code), ['HKI']);

        final departments = await db.select(db.departments).get();
        expect(departments.every((d) => d.businessUnitId == hki), isTrue);
        expect(departments, hasLength(6));

        final revenue = await db.select(db.revenueCategories).get();
        expect(revenue.map((r) => r.code), containsAll(['ROOM', 'BANQUET']));
        expect(revenue.map((r) => r.code), isNot(contains('NANDBHOG')));
      },
    );

    test('no orphan survives the purge', () async {
      await purge.purgeUnits({ccr});
      await db.customStatement('PRAGMA foreign_keys = ON');
      final violations = await db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      expect(violations, isEmpty);
    });

    test('the outbox is untouched, whatever else happens', () async {
      final result = await purge.purgeUnits({ccr});

      expect(result.outboxEntriesPreserved, 1);
      final rows = await db.select(db.syncOutbox).get();
      expect(rows, hasLength(1));
      expect(rows.single.mutationId, mid('mut-1'));
      expect(
        rows.single.entityId,
        seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
        reason:
            'the attempt keeps pointing at what the user actually tried to change',
      );
    });

    test('organisation-owned reference data is retained', () async {
      final before = await count('payment_methods');
      await purge.purgeUnits({ccr});
      expect(await count('payment_methods'), before);
    });

    test('a vendor pinned to the revoked unit survives entirely untouched', () async {
      // D-049 §2. One user losing a property is not an edit to a company-wide supplier.
      await db.customStatement(
        "INSERT INTO vendors (id, org_id, code, name, default_business_unit_id, "
        "sort_order, row_version, updated_at) VALUES "
        "('v1', ?, 'SHARMA', 'Sharma Traders', ?, 0, 1, '2026-08-28T09:00:00.000Z')",
        [seedOrgId, ccr],
      );

      await purge.purgeUnits({ccr});

      final vendors = await db.select(db.vendors).get();
      expect(
        vendors,
        hasLength(1),
        reason: 'a supplier belongs to the company',
      );
      expect(
        vendors.single.defaultBusinessUnitId,
        ccr,
        reason:
            'the canonical value must not be rewritten because one user lost scope — '
            'the next pull would only put it straight back',
      );
      expect(
        vendors.single.rowVersion,
        1,
        reason: 'no row version moves, so no spurious conflict is manufactured',
      );
    });

    test('the vendor default is filtered per user, never erased', () {
      const vendor = Vendor(
        id: 'v1',
        code: 'SHARMA',
        name: 'Sharma Traders',
        defaultBusinessUnitId: 'unit-ccr',
      );

      // Inside scope: usable.
      expect(vendor.effectiveDefaultBusinessUnitId({'unit-ccr'}), 'unit-ccr');
      expect(vendor.hasUnreachableDefault({'unit-ccr'}), isFalse);

      // Outside scope: unavailable to this user, while the record still says what it says.
      expect(vendor.effectiveDefaultBusinessUnitId({'unit-hki'}), isNull);
      expect(vendor.hasUnreachableDefault({'unit-hki'}), isTrue);
      expect(vendor.defaultBusinessUnitId, 'unit-ccr');

      // Scope restored: usable again, with nothing written to make it so.
      expect(
        vendor.effectiveDefaultBusinessUnitId({'unit-ccr', 'unit-hki'}),
        'unit-ccr',
      );

      // An org-wide holder is unrestricted: null means "no restriction", not "no units".
      expect(vendor.effectiveDefaultBusinessUnitId(null), 'unit-ccr');
    });

    test(
      'purging both units empties the hierarchy but not the queue',
      () async {
        final result = await purge.purgeUnits({ccr, hki});
        expect(await count('business_units'), 0);
        expect(await count('departments'), 0);
        expect(await count('expense_categories'), 0);
        expect(result.outboxEntriesPreserved, 1);
      },
    );

    test(
      're-granting the unit lets the seed restore it without duplicates',
      () async {
        await purge.purgeUnits({ccr});
        expect(await count('business_units'), 1);

        // Canonical state wins on re-grant: the same derived ids come back, so nothing
        // duplicates (D-048 §5).
        await seedMasterData(db, now: at);
        await seedMasterData(db, now: at);

        final units = await db.select(db.businessUnits).get();
        expect(units, hasLength(2));
        expect(units.map((u) => u.code).toSet(), {'CCR', 'HKI'});
        expect(units.map((u) => u.id), containsAll([ccr, hki]));
      },
    );

    test('a rejected attempt is not resurrected by the re-grant', () async {
      // The queue entry survives, but nothing about restoring authority re-runs it.
      await purge.purgeUnits({ccr});
      await seedMasterData(db, now: at);
      final rows = await db.select(db.syncOutbox).get();
      expect(rows, hasLength(1));
      expect(rows.single.status, 'pending');
    });
  });

  group('a refusal is not a conflict', () {
    test('a withdrawn permission is terminal and never auto-retried', () {
      expect(OutboxStatus.rejected.isAutomaticallyRetryable, isFalse);
      expect(OutboxStatus.rejected.userVisibleState, SyncState.rejected);
      expect(SyncState.rejected.needsAttention, isTrue);
      expect(
        SyncState.rejected.isOnServer,
        isFalse,
        reason: 'a refused attempt must never be presented as synchronised',
      );
    });

    test('the two are distinct states, because they are distinct problems', () {
      expect(OutboxStatus.rejected, isNot(OutboxStatus.conflict));
      expect(SyncState.rejected.label, isNot(SyncState.conflict.label));
    });

    test('server codes map to the reason the user is actually given', () {
      expect(
        ServerRefusal.fromCode('out_of_unit_scope').kind,
        RefusalKind.outOfUnitScope,
      );
      expect(
        ServerRefusal.fromCode('out_of_unit_scope').kind.isAuthorityRefusal,
        isTrue,
      );
      expect(
        ServerRefusal.fromCode('version_conflict').kind.isAuthorityRefusal,
        isFalse,
        reason: 'a stale version is about the record, not about who you are',
      );
      expect(
        ServerRefusal.fromCode('period_closed').message,
        contains('closed'),
      );
    });

    test('a structured refusal keeps the numbers the screen needs', () {
      final refusal = ServerRefusal.fromCode(
        'has_active_children',
        detail: const {
          'child_count': 4,
          'child_kind': 'expense categories',
          'entity_type': 'section',
        },
      );
      expect(refusal.kind, RefusalKind.hasActiveChildren);
      expect(refusal.childCount, 4);
      expect(
        refusal.message,
        'Archive the 4 expense categories underneath this one first.',
      );
      expect(refusal.entityType, 'section');
    });

    test(
      'the D-038 acknowledgement refusal states the real transaction count',
      () {
        final refusal = ServerRefusal.fromCode(
          'acknowledgement_required',
          detail: const {'transaction_count': 42},
        );
        expect(refusal.transactionCount, 42);
        expect(refusal.message, contains('42 recorded transactions'));
      },
    );

    test('an unknown code is surfaced, not guessed at', () {
      final refusal = ServerRefusal.fromCode(
        'KM999_something_new',
        serverMessage: 'a newer rule refused this',
      );
      expect(refusal.kind, RefusalKind.unrecognised);
      expect(refusal.code, 'KM999_something_new');
      expect(refusal.message, 'a newer rule refused this');
      expect(refusal.kind.isAutomaticallyRetryable, isFalse);
    });

    test('no refusal is ever automatically retryable', () {
      for (final kind in RefusalKind.values) {
        expect(kind.isAutomaticallyRetryable, isFalse, reason: kind.name);
      }
    });
  });

  group('the canonical reporting cache goes with the property', () {
    late AppDatabase db;
    late ScopeCachePurge purge;

    Future<void> cache(String owner, String unit, int year) async {
      await db.customStatement(
        "INSERT INTO reporting_coverage_markers (owner_user_id, org_id, "
        "business_unit_id, dataset, financial_year, generation, on_demand, updated_at) "
        "VALUES (?, ?, ?, 'revenue', ?, 40, 0, '2026-08-28T09:00:00.000Z')",
        [owner, seedOrgId, unit, year],
      );
      await db.customStatement(
        "INSERT INTO reporting_revenue_contributions (owner_user_id, org_id, "
        "contribution_id, revenue_entry_id, business_unit_id, revenue_category_id, "
        "pnl_date, pnl_period_key, gross_minor, tax_minor, net_minor, tax_treatment, "
        "tax_rate_basis_points, entered_basis, financial_year, document_generation, "
        "synced_at) VALUES (?, ?, ?, ?, ?, 'cat-rest', '2026-06-15', '2026-06', "
        "10000000, 476190, 9523810, 'inclusive', 500, 'inclusive_total', ?, 40, "
        "'2026-08-28T09:00:00.000Z')",
        [owner, seedOrgId, 'c-$owner-$unit', 'r-$owner-$unit', unit, year],
      );
      await db.customStatement(
        "INSERT INTO reporting_expense_contributions (owner_user_id, org_id, "
        "contribution_id, expense_id, allocation_id, business_unit_id, department_id, "
        "section_id, category_id, pnl_date, pnl_period_key, amount_minor, "
        "financial_year, document_generation, synced_at) "
        "VALUES (?, ?, ?, ?, ?, ?, 'dept-1', 'sec-1', 'cat-1', '2026-06-30', '2026-06', "
        "500000, ?, 40, '2026-08-28T09:00:00.000Z')",
        [
          owner,
          seedOrgId,
          'ce-$owner-$unit',
          'e-$owner-$unit',
          'a-$owner-$unit',
          unit,
          year,
        ],
      );
    }

    Future<List<String>> unitsIn(String table) async {
      final rows = await db
          .customSelect('SELECT business_unit_id AS u FROM $table ORDER BY u')
          .get();
      return [for (final row in rows) row.read<String>('u')];
    }

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      purge = ScopeCachePurge(db);
      await seedMasterData(db, now: at);
      await cache('manager', ccr, 2026);
      await cache('manager', hki, 2026);
      await cache('accountant', ccr, 2026);
    });
    tearDown(() => db.close());

    test('a confirmed revocation removes the revoked property outright', () async {
      final result = await purge.applyTo(
        AuthorityRefresh.confirmed(snapshot({hki})),
        previous: snapshot({ccr, hki}),
      );
      expect(result.didPurge, isTrue);

      for (final table in const [
        'reporting_coverage_markers',
        'reporting_revenue_contributions',
        'reporting_expense_contributions',
      ]) {
        expect(
          await unitsIn(table),
          [hki],
          reason:
              'unlike a financial document, nothing here is anybody unsent work: every '
              'row came from the server and the server hands it back when authority '
              'returns, so it goes whole rather than being retained (D-070, D-171). '
              '$table',
        );
      }
    });

    test('the claim goes even where a colleague made it', () async {
      await purge.applyTo(
        AuthorityRefresh.confirmed(snapshot({hki})),
        previous: snapshot({ccr, hki}),
      );

      final owners = await db
          .customSelect(
            'SELECT owner_user_id AS o FROM reporting_coverage_markers ORDER BY o',
          )
          .get();
      expect(
        [for (final row in owners) row.read<String>('o')],
        ['manager'],
        reason:
            'the accountant Crystal Canopy claim is removed with the property. A '
            'coverage marker is a statement about a scope, and this installation no '
            'longer holds the rows behind it',
      );
    });

    test('a failed refresh keeps every cached figure', () async {
      final result = await purge.applyTo(
        const AuthorityRefresh.unavailable(AuthorityUnavailableReason.offline),
        previous: snapshot({ccr, hki}),
      );

      expect(result.didPurge, isFalse);
      expect(
        (await unitsIn('reporting_revenue_contributions')).length,
        3,
        reason:
            'unknown is not revoked. A network failure says nothing about authority, '
            'and purging a P&L on one would be the destructive reading (D-048)',
      );
    });
  });
}
