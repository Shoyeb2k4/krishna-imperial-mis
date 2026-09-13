/// D-070 and D-074 applied to the owner domain, including the case a unit purge cannot
/// see: **a capability withdrawn while every property is kept.**
///
/// Phase 5 OA-3, by the project lead's approval of the gap the OA-3 audit found. Until
/// now the owner caches were only ever purged through a *business unit* revocation, and
/// `unitsRevokedSince` is empty for an org-wide holder by construction — so somebody who
/// kept Crystal Canopy and Hotel Krishna but lost `owner_settlement.view` kept the owners'
/// private position on the device indefinitely.
///
/// The rules proven here:
///
/// * a **confirmed** authority lacking the settlement capabilities removes this person's
///   canonical owner cache — coverage first — whatever their units;
/// * a failed or unavailable refresh removes nothing (D-048 section 1);
/// * the OA-1 operational ledger is purged on unit revocation, on confirmed loss of
///   `owner_ledger.view`, and on a user switch, **sparing the actor's own unsent work**,
///   which is stamped and taken out of every canonical read (D-070);
/// * a retained movement is restored only to the actor who queued it (D-074).
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import '../support/cache_principal.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';

/// Every capability the settlement surface composes (OA-3 contract).
const _settlementCapabilities = {
  Capability.ownerSettlementView,
  Capability.ownerLedgerView,
  Capability.reportsView,
};

class _Source implements OwnerSnapshotSource {
  @override
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot() async =>
      RemoteOk({
        'snapshot_id': 'snap-1',
        'server_time': '2026-07-01T09:00:00.000Z',
        'settlement_authorised': true,
        'ownership_start_date': '2026-04-01',
        'movements': [
          {
            'id': 'canon-1',
            'org_id': 'org-1',
            'business_unit_id': _hki,
            'owner_id': 'owner-a',
            'txn_number': 'KI-OWN-26-27-000001',
            'financial_year': '26-27',
            'business_date': '2026-06-15',
            'business_date_source': 'derived',
            'pnl_period_key': '2026-06',
            'movement_type': 'withdrawal',
            'direction': 'debit',
            'amount_minor': 100000,
            'family_member_id': null,
            'collected_by_family_member_id': null,
            'nc_bill_reference': null,
            'reference_number': null,
            'remarks': null,
            'reason': null,
            'created_by': 'someone',
            'captured_at': '2026-06-15T10:00:00.000Z',
            'row_version': 1,
            'change_seq': 1,
            'voided_at': null,
            'void_reason': null,
          },
        ],
        'owners': [
          {
            'id': 'owner-a',
            'org_id': 'org-1',
            'code': 'A',
            'display_name': 'Owner A',
            'active': true,
            'archived_at': null,
            'row_version': 1,
            'change_seq': 1,
          },
        ],
        'ownership_shares': [
          {
            'id': 'share-a',
            'org_id': 'org-1',
            'owner_id': 'owner-a',
            'share_basis_points': 5000,
            'effective_from': '2026-04-01',
            'effective_to': null,
            'note': null,
            'row_version': 1,
            'change_seq': 1,
          },
        ],
        'family_members': const [],
      });
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ScopeCachePurge purge;
  final now = DateTime.utc(2026, 7, 2, 9);

  /// Authority holding [capabilities] either org-wide or over [units].
  AuthoritySnapshot authority(
    String userId, {
    Set<Capability> capabilities = const {},
    Set<String> units = const {},
    bool orgWide = false,
  }) => AuthoritySnapshot(
    userId: userId,
    orgId: 'org-1',
    resolvedAt: now,
    grants: [
      // Something property-scoped is always held, so "units unchanged" is a real
      // statement in every case below rather than an empty set.
      for (final unit in units)
        CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
      for (final capability in capabilities)
        if (orgWide)
          CapabilityGrant(capability)
        else
          for (final unit in units)
            CapabilityGrant(capability, businessUnitId: unit),
      if (orgWide) const CapabilityGrant(Capability.expenseViewAll),
    ],
  );

  Future<void> synchroniseFor(String userId) async {
    final result = await OwnerSettlementSync(
      database: db,
      gateway: _Source(),
      ownerUserId: userId,
    ).synchronise();
    expect(result, isA<OwnerSettlementSynchronised>());
  }

  Future<int> countFor(String table, String userId) async =>
      (await db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM $table WHERE owner_user_id = ?',
                    variables: [Variable<String>(userId)],
                  )
                  .getSingle())
              .data['n']!
          as int;

  Future<Map<String, int>> canonicalCacheOf(String userId) async => {
    for (final table in const [
      'owner_settlement_coverage',
      'canonical_owner_movements',
      'canonical_ownership_shares',
      'canonical_owners',
    ])
      table: await countFor(table, userId),
  };

  /// An OA-1 operational movement: synced, or carrying [actor]'s unsent intent.
  Future<void> ledgerEntry(
    String id, {
    String unit = _ccr,
    String actor = 'user-1',
    bool synced = true,
  }) async {
    await db.customStatement(
      'INSERT INTO owner_ledger_entries (id, org_id, txn_number, financial_year, '
      'owner_id, business_unit_id, business_date, pnl_period_key, movement_type, '
      'direction, amount_minor, created_by, captured_at, pending_mutation_id, '
      'row_version, updated_at) '
      "VALUES (?, 'org-1', ?, ?, 'owner-a', ?, '2026-06-15', '2026-06', "
      "'withdrawal', 'debit', 100000, ?, '2026-06-15T09:00:00.000Z', ?, 1, "
      "'2026-06-15T09:00:00.000Z')",
      [
        id,
        synced ? 'KI-OWN-$id' : null,
        synced ? '26-27' : null,
        unit,
        actor,
        synced ? null : 'mut-$id',
      ],
    );
    if (!synced) {
      await db.customStatement(
        'INSERT INTO sync_outbox (mutation_id, entity_type, entity_id, op, '
        'payload, status, attempt_count, next_attempt_at, created_at, '
        'actor_user_id) '
        "VALUES (?, 'owner_ledger_entry', ?, 'create', '{}', 'pending', 0, "
        "'2026-06-15T09:00:00.000Z', '2026-06-15T09:00:00.000Z', ?)",
        ['mut-$id', id, actor],
      );
    }
  }

  Future<List<String>> ledgerIds({required bool stamped}) async => [
    for (final r
        in await db
            .customSelect(
              'SELECT id FROM owner_ledger_entries WHERE scope_revoked_at IS '
              '${stamped ? 'NOT NULL' : 'NULL'} ORDER BY id',
            )
            .get())
      r.data['id'] as String,
  ];

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

  // ═══════════════════════════════════════════════════════════════════════════
  group('the canonical owner cache on confirmed capability loss', () {
    test(
      'an org-wide holder who loses owner_settlement.view keeps no owner cache',
      () async {
        // The exact case a unit purge cannot see: org-wide, so no unit is ever
        // "revoked", and every property is still held.
        await synchroniseFor('user-1');
        final before = authority(
          'user-1',
          capabilities: _settlementCapabilities,
          orgWide: true,
        );
        final after = authority(
          'user-1',
          capabilities: {Capability.ownerLedgerView, Capability.reportsView},
          orgWide: true,
        );

        await purge.applyTo(
          AuthorityRefresh.confirmed(after),
          previous: before,
        );

        expect(await canonicalCacheOf('user-1'), {
          'owner_settlement_coverage': 0,
          'canonical_owner_movements': 0,
          'canonical_ownership_shares': 0,
          'canonical_owners': 0,
        });
        expect(
          await OwnerSettlementRepository(
            db,
            principal: canonicalCachePrincipal('user-1'),
          ).coverage(),
          isNull,
          reason:
              'no settlement may be certified from history this reader was just told '
              'they may not read',
        );
      },
    );

    for (final lost in _settlementCapabilities) {
      test(
        'losing ${lost.code} while keeping both properties removes it too',
        () async {
          await synchroniseFor('user-1');
          await purge.applyTo(
            AuthorityRefresh.confirmed(
              authority(
                'user-1',
                capabilities: {..._settlementCapabilities}..remove(lost),
                units: {_ccr, _hki},
              ),
            ),
            previous: authority(
              'user-1',
              capabilities: _settlementCapabilities,
              units: {_ccr, _hki},
            ),
          );
          expect(await countFor('owner_settlement_coverage', 'user-1'), 0);
          expect(await countFor('canonical_ownership_shares', 'user-1'), 0);
        },
      );
    }

    test(
      'a confirmed authority that still holds all three removes nothing',
      () async {
        await synchroniseFor('user-1');
        final held = authority(
          'user-1',
          capabilities: _settlementCapabilities,
          orgWide: true,
        );
        await purge.applyTo(AuthorityRefresh.confirmed(held), previous: held);

        expect(await canonicalCacheOf('user-1'), {
          'owner_settlement_coverage': 1,
          'canonical_owner_movements': 1,
          'canonical_ownership_shares': 1,
          'canonical_owners': 1,
        });
      },
    );

    for (final reason in AuthorityUnavailableReason.values) {
      test('an unavailable refresh (${reason.name}) removes nothing', () async {
        await synchroniseFor('user-1');
        await purge.applyTo(
          AuthorityRefresh.unavailable(reason),
          previous: authority(
            'user-1',
            capabilities: _settlementCapabilities,
            orgWide: true,
          ),
        );
        expect(
          await countFor('owner_settlement_coverage', 'user-1'),
          1,
          reason: 'unknown is not revoked (D-048 section 1)',
        );
      });
    }

    test('only this person cache goes; another person keeps theirs', () async {
      await synchroniseFor('user-1');
      await synchroniseFor('user-2');

      await purge.applyTo(
        AuthorityRefresh.confirmed(authority('user-1', units: {_ccr, _hki})),
        previous: null,
      );

      expect(await countFor('owner_settlement_coverage', 'user-1'), 0);
      expect(
        await countFor('owner_settlement_coverage', 'user-2'),
        1,
        reason:
            'one person losing a capability is not evidence about another person '
            '(D-074)',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the OA-1 operational ledger follows D-070 like every financial table', () {
    test(
      'a unit revocation purges synced movements and stamps unsent ones',
      () async {
        await ledgerEntry('synced-ccr');
        await ledgerEntry('synced-hki', unit: _hki);
        await ledgerEntry('unsent-ccr', synced: false);

        final result = await purge.purgeUnits({_ccr}, actorUserId: 'user-1');

        expect(
          await ledgerIds(stamped: false),
          ['synced-hki'],
          reason:
              'the classification has always said this table is purged per unit',
        );
        expect(await ledgerIds(stamped: true), ['unsent-ccr']);
        expect(result.rowsRemoved['owner_ledger_entries'], 1);
        expect(
          result.documentsRetainedForUnsyncedWork,
          contains('unsent-ccr'),
          reason:
              'an unsent movement exists nowhere else, and losing a property is not a '
              'reason to destroy it (D-070)',
        );
      },
    );

    test(
      'confirmed loss of owner_ledger.view purges synced movements on every unit',
      () async {
        await ledgerEntry('synced-ccr');
        await ledgerEntry('synced-hki', unit: _hki);
        await ledgerEntry('unsent-hki', unit: _hki, synced: false);

        await purge.applyTo(
          AuthorityRefresh.confirmed(authority('user-1', units: {_ccr, _hki})),
          previous: authority(
            'user-1',
            capabilities: {Capability.ownerLedgerView},
            units: {_ccr, _hki},
          ),
        );

        expect(await ledgerIds(stamped: false), isEmpty);
        expect(await ledgerIds(stamped: true), ['unsent-hki']);
      },
    );

    test(
      'a user switch takes synced movements and keeps unsent ones, unbrowsable',
      () async {
        await ledgerEntry('synced-ccr');
        await ledgerEntry('unsent-ccr', synced: false);

        await purge.purgeAllScopedCache();

        expect(await ledgerIds(stamped: false), isEmpty);
        expect(await ledgerIds(stamped: true), ['unsent-ccr']);
      },
    );

    test(
      'a retained movement is restored to the actor who queued it, and no one else',
      () async {
        await ledgerEntry('mine', synced: false);
        await ledgerEntry('theirs', actor: 'user-2', synced: false);
        await purge.purgeAllScopedCache();
        expect(await ledgerIds(stamped: true), ['mine', 'theirs']);

        await purge.applyTo(
          AuthorityRefresh.confirmed(
            authority(
              'user-1',
              capabilities: {Capability.ownerLedgerView},
              units: {_ccr, _hki},
            ),
          ),
          previous: null,
        );

        expect(await ledgerIds(stamped: false), ['mine']);
        expect(
          await ledgerIds(stamped: true),
          ['theirs'],
          reason:
              'holding the property does not make somebody the author of another '
              'person queued intent (D-074)',
        );
      },
    );

    test(
      'and is not restored while the reader lacks owner_ledger.view',
      () async {
        await ledgerEntry('mine', synced: false);
        await purge.purgeAllScopedCache();

        await purge.applyTo(
          AuthorityRefresh.confirmed(authority('user-1', units: {_ccr, _hki})),
          previous: null,
        );
        expect(await ledgerIds(stamped: true), ['mine']);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group(
    'sign-out takes the canonical owner cache even with no unit cached',
    () {
      test(
        'no business unit cached is not a reason to leave owner data behind',
        () async {
          await synchroniseFor('user-1');
          await db.customStatement('DELETE FROM business_units');

          await purge.purgeAllScopedCache();

          expect(await canonicalCacheOf('user-1'), {
            'owner_settlement_coverage': 0,
            'canonical_owner_movements': 0,
            'canonical_ownership_shares': 0,
            'canonical_owners': 0,
          });
        },
      );

      test('the owner-keyed start date goes with it (D-208)', () async {
        await synchroniseFor('user-1');
        expect(
          (await OwnerSettlementRepository(
            db,
            principal: canonicalCachePrincipal('user-1'),
          ).coverage())!.ownershipStartDate,
          BusinessDate.of(2026, 4, 1),
        );
        await purge.purgeAllScopedCache();
        expect(
          await OwnerSettlementRepository(
            db,
            principal: canonicalCachePrincipal('user-1'),
          ).coverage(),
          isNull,
        );
      });
    },
  );
}
