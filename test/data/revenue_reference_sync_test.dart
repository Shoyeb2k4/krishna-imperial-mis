/// Revenue configuration synchronisation (Slice 6).
///
/// Slice 5 taught the device how to resolve tax from a cache. This is what fills that
/// cache, and almost everything worth testing about it is a question of *honesty*: after
/// a run, does the device claim exactly what it can support?
///
/// The failures that matter are not crashes. They are the runs that half-succeed and say
/// nothing — four requests where three arrive, a scope that was never asked about,
/// another user's success being borrowed — because each of those makes the device
/// confidently tell a manager something false about their own company's tax.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/session/session_controller.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/data/sync/reference_sync.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _userA = 'user-a';
const _userB = 'user-b';
const _catRestaurant = 'cat-restaurant';
const _catNandbhog = 'cat-nandbhog';
const _catRoom = 'cat-room';
const _catBanquet = 'cat-banquet';

/// The property a category belongs to. Supplied to the resolver rather than derived,
/// because a confirmed revocation removes the category row it would be derived from.
String _unitOf(String category) => switch (category) {
  _catRoom || _catBanquet => _hki,
  _ => _ccr,
};

/// An authority answer under the caller's control.
class _FakeAuthority implements AuthoritySource {
  _FakeAuthority(this.units);

  Set<String> units;
  String userId = _userA;
  AuthorityRefresh? forced;

  @override
  Future<AuthorityRefresh> refresh() async =>
      forced ??
      AuthorityRefresh.confirmed(
        AuthoritySnapshot(
          userId: userId,
          orgId: _org,
          grants: [
            for (final unit in units)
              CapabilityGrant(Capability.mastersView, businessUnitId: unit),
          ],
          resolvedAt: DateTime.utc(2026, 6, 15, 9),
        ),
      );
}

/// A server whose answer — and whose failures — the test chooses.
class _FakePuller implements ReferencePuller {
  _FakePuller(this.units);

  Set<String> units;
  RemoteFailure? failure;

  /// Datasets the caller wants emptied, to model one request of four failing or a
  /// legitimately empty authoritative answer.
  Set<String> empty = {};

  /// Rows the caller wants injected verbatim, to model a malformed payload.
  List<Map<String, dynamic>>? overrideRules;
  List<Map<String, dynamic>>? overrideBands;

  int calls = 0;

  List<Map<String, dynamic>> get _categories => [
    for (final c in const [
      (_catRestaurant, _ccr, 'RESTAURANT'),
      (_catNandbhog, _ccr, 'NANDBHOG'),
      (_catRoom, _hki, 'ROOM'),
      (_catBanquet, _hki, 'BANQUET'),
    ])
      if (units.contains(c.$2))
        {
          'id': c.$1,
          'org_id': _org,
          'business_unit_id': c.$2,
          'code': c.$3,
          'name': c.$3,
          'sort_order': 1,
          'archived_at': null,
          'row_version': 1,
          'updated_at': '2026-04-01T00:00:00.000Z',
          'change_seq': 100,
        },
  ];

  Map<String, dynamic> _rule(
    String id,
    String category, {
    int rateBp = 500,
    String treatment = 'inclusive',
    String? basis = 'inclusive_total',
    String from = '2026-04-01',
    String? to,
    String? bandId,
    int seq = 200,
  }) => {
    'id': id,
    'org_id': _org,
    'revenue_category_id': category,
    'rate_bp': rateBp,
    'treatment': treatment,
    'effective_from': from,
    'effective_to': to,
    'input_basis': basis,
    'value_band_id': bandId,
    'supply_subtype_id': null,
    'premises_status_code': null,
    'note': null,
    'archived_at': null,
    'created_by': 'someone',
    'created_at': '2026-04-01T00:00:00.000Z',
    'row_version': 1,
    'updated_at': '2026-04-01T00:00:00.000Z',
    'change_seq': seq,
  };

  /// The verified FY 2026-27 baseline, filtered to the units in scope.
  List<Map<String, dynamic>> get baselineRules => [
    if (units.contains(_ccr)) ...[
      _rule('rule-restaurant', _catRestaurant),
      _rule('rule-nandbhog', _catNandbhog),
    ],
    if (units.contains(_hki)) ...[
      _rule('rule-room', _catRoom),
      _rule('rule-banquet', _catBanquet, rateBp: 0, treatment: 'none'),
    ],
  ];

  List<Map<String, dynamic>> extraRules = [];
  List<Map<String, dynamic>> bands = [];
  List<Map<String, dynamic>> subtypes = [];
  List<Map<String, dynamic>> statuses = [];

  @override
  Future<RemoteOutcome<ReferenceSnapshot>> pullAll() async {
    calls++;
    final f = failure;
    if (f != null) return RemoteOutcome.unreachable(f);

    List<Map<String, dynamic>> pick(
      String name,
      List<Map<String, dynamic>> rows,
    ) => empty.contains(name) ? const [] : rows;

    return RemoteOutcome.ok(
      ReferenceSnapshot(
        businessUnits: [
          for (final unit in units)
            {
              'id': unit,
              'org_id': _org,
              'code': unit.toUpperCase(),
              'name': unit,
              'kind': 'hotel',
              'timezone': 'Asia/Kolkata',
              'business_day_cutoff': '05:00',
              'sort_order': 1,
              'archived_at': null,
              'row_version': 1,
              'updated_at': '2026-04-01T00:00:00.000Z',
              'change_seq': 50,
            },
        ],
        departments: const [],
        sections: const [],
        expenseCategories: const [],
        revenueCategories: _categories,
        paymentMethods: const [],
        vendors: const [],
        taxRules:
            overrideRules ?? pick('rules', [...baselineRules, ...extraRules]),
        valueBands: overrideBands ?? pick('bands', bands),
        supplySubtypes: pick('subtypes', subtypes),
        premisesStatuses: pick('statuses', statuses),
        fetchedAt: DateTime.utc(2026, 6, 15, 9),
      ),
    );
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late _FakeAuthority authority;
  late _FakePuller puller;
  late ReferenceSync sync;
  late RevenueTaxRepository repository;

  void wire({Set<String> units = const {_ccr, _hki}}) {
    authority = _FakeAuthority({...units});
    puller = _FakePuller({...units});
    sync = ReferenceSync(
      db: db,
      authorityGateway: authority,
      masterGateway: puller,
      authorityStore: AuthorityStore(db),
    );
    repository = RevenueTaxRepository(db);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    wire();
  });

  tearDown(() => db.close());

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']!
          as int;

  Future<RevenueConfigCompleteness> stateFor(
    String unit, {
    String user = _userA,
  }) => repository.completenessFor(userId: user, businessUnitId: unit);

  RevenueTaxFacts facts(String category) => RevenueTaxFacts(
    revenueCategoryId: category,
    businessDate: BusinessDate.of(2026, 6, 15),
  );

  group('a first successful synchronisation', () {
    test('writes the configuration and claims completeness per unit', () async {
      final report = await sync.synchronise();

      expect(report.authorityConfirmed, isTrue);
      expect(report.rejectedSnapshotReason, isNull);
      expect(await count('revenue_tax_rates'), 4);

      for (final unit in const [_ccr, _hki]) {
        final state = await stateFor(unit);
        expect(state, isA<RevenueConfigComplete>(), reason: unit);
        expect(
          (state as RevenueConfigComplete).confirmedAt,
          DateTime.utc(2026, 6, 15, 9),
          reason:
              'server time, taken from the authority answer, never the device clock',
        );
        expect(state.generation, isNotNull);
      }
    });

    test(
      'the four v1.2 rule columns arrive, which they did not before Slice 6',
      () async {
        // The defect this pins: `ReferenceSync` wrote a rule without `input_basis`, so a
        // device whose configuration had in fact arrived intact resolved every entry as
        // `incompleteRule` and refused it. No sync error, no failed request — just a rule
        // the resolver could not use, produced by a run that reported success.
        await sync.synchronise();

        final row = await db
            .customSelect(
              "SELECT input_basis, value_band_id, supply_subtype_id, "
              "premises_status_code FROM revenue_tax_rates WHERE id = 'rule-restaurant'",
            )
            .getSingle();
        expect(row.data['input_basis'], 'inclusive_total');

        final resolved = await repository.resolve(
          facts(_catRestaurant),
          userId: _userA,
          businessUnitId: _unitOf(_catRestaurant),
        );
        expect(resolved, isA<RevenueTaxResolved>());
        expect(
          (resolved as RevenueTaxResolved).rule.inputBasis,
          EnteredBasis.inclusiveTotal,
        );
      },
    );

    test(
      'Slice 5 then resolves all four verified categories offline',
      () async {
        await sync.synchronise();
        puller.failure = RemoteFailure.serverUnreachable;

        for (final c in const [
          (_catRestaurant, 500, TaxTreatment.inclusive),
          (_catNandbhog, 500, TaxTreatment.inclusive),
          (_catRoom, 500, TaxTreatment.inclusive),
          (_catBanquet, 0, TaxTreatment.none),
        ]) {
          final outcome = await repository.resolve(
            facts(c.$1),
            userId: _userA,
            businessUnitId: _unitOf(c.$1),
          );
          expect(outcome, isA<RevenueTaxResolved>(), reason: c.$1);
          final rule = (outcome as RevenueTaxResolved).rule;
          expect(rule.rateBasisPoints, c.$2, reason: c.$1);
          expect(rule.treatment, c.$3, reason: c.$1);
        }
      },
    );
  });

  group('the snapshot is complete or it is nothing (B4)', () {
    test(
      'a failed pull leaves the previous snapshot and does not claim completeness',
      () async {
        await sync.synchronise();
        final before = await count('revenue_tax_rates');

        puller.failure = RemoteFailure.serverUnreachable;
        final report = await sync.synchronise();

        expect(report.authorityConfirmed, isTrue);
        expect(report.pullFailure, isNotNull);
        expect(await count('revenue_tax_rates'), before);
        expect(
          await stateFor(_ccr),
          isA<RevenueConfigComplete>(),
          reason:
              'the last known-good snapshot stands; a lost network is not a revocation',
        );
      },
    );

    test('a first-ever failed pull claims nothing at all', () async {
      puller.failure = RemoteFailure.serverUnreachable;

      final report = await sync.synchronise();

      expect(report.pullFailure, isNotNull);
      expect(await count('revenue_tax_rates'), 0);
      expect(await stateFor(_ccr), isA<RevenueConfigNeverSynchronised>());
      expect(
        await repository.resolve(
          facts(_catRestaurant),
          userId: _userA,
          businessUnitId: _unitOf(_catRestaurant),
        ),
        isA<RevenueConfigurationUnavailable>(),
      );
    });

    test(
      'the marker is written last, so a rejected snapshot advances nothing',
      () async {
        // The forbidden sequence, stated as a test: rules succeed, marker advanced, bands
        // fail, device claims complete configuration. It cannot happen, because the marker
        // is inside the same transaction as the writes and is the final statement in it.
        puller.overrideRules = [
          {...puller.baselineRules.first, 'input_basis': null},
        ];

        final report = await sync.synchronise();

        expect(report.rejectedSnapshotReason, contains('no input basis'));
        expect(await count('revenue_tax_rates'), 0);
        expect(await stateFor(_ccr), isA<RevenueConfigNeverSynchronised>());
      },
    );
  });

  group('a malformed authoritative payload is refused, not repaired (B18)', () {
    setUp(() async {
      await sync.synchronise();
    });

    test('a rule with no basis cannot replace a known-good snapshot', () async {
      puller.overrideRules = [
        {...puller.baselineRules.first, 'input_basis': null},
      ];

      final report = await sync.synchronise();

      expect(report.rejectedSnapshotReason, isNotNull);
      expect(
        await count('revenue_tax_rates'),
        4,
        reason: 'the previous snapshot is retained whole',
      );
      expect(await stateFor(_ccr), isA<RevenueConfigComplete>());
      expect(
        await repository.resolve(
          facts(_catRestaurant),
          userId: _userA,
          businessUnitId: _unitOf(_catRestaurant),
        ),
        isA<RevenueTaxResolved>(),
        reason:
            'yesterday\'s working configuration beats today\'s unusable one',
      );
    });

    test(
      'a rule naming a band the snapshot does not contain is refused',
      () async {
        puller.overrideRules = [
          {...puller.baselineRules.first, 'value_band_id': 'band-missing'},
        ];

        final report = await sync.synchronise();

        expect(report.rejectedSnapshotReason, contains('band-missing'));
        expect(await stateFor(_ccr), isA<RevenueConfigComplete>());
      },
    );

    test('an unrecognised treatment or basis is refused', () async {
      puller.overrideRules = [
        {...puller.baselineRules.first, 'treatment': 'reverse_charge'},
      ];
      expect(
        (await sync.synchronise()).rejectedSnapshotReason,
        contains('tax treatment'),
      );

      puller.overrideRules = [
        {...puller.baselineRules.first, 'input_basis': 'inclusiveTotal'},
      ];
      expect(
        (await sync.synchronise()).rejectedSnapshotReason,
        contains('input basis'),
        reason: 'the Dart enum name is not the stored form (D-104)',
      );
    });

    test('a band describing no range is refused', () async {
      puller.overrideBands = [
        {
          'id': 'band-empty',
          'org_id': _org,
          'revenue_category_id': _catRoom,
          'code': 'EMPTY',
          'label': 'Empty',
          'floor_minor': null,
          'ceiling_minor': null,
          'superseded_by_band_id': null,
          'archived_at': null,
          'row_version': 1,
          'updated_at': '2026-04-01T00:00:00.000Z',
        },
      ];

      expect(
        (await sync.synchronise()).rejectedSnapshotReason,
        contains('describes no range'),
      );
    });

    test('nothing is silently repaired', () async {
      // A client that filled in a missing basis, dropped an unresolvable discriminator or
      // invented a range would be deciding a tax fact on the server's behalf (D-043).
      puller.overrideRules = [
        {...puller.baselineRules.first, 'input_basis': null},
      ];
      await sync.synchronise();

      final stored = await db
          .customSelect(
            "SELECT input_basis FROM revenue_tax_rates WHERE id = 'rule-restaurant'",
          )
          .getSingle();
      expect(
        stored.data['input_basis'],
        'inclusive_total',
        reason:
            'still the previous good value — nothing was written and nothing invented',
      );
    });
  });

  group('per-scope completeness (B7)', () {
    test('Crystal Canopy alone leaves Hotel Krishna unsynchronised', () async {
      wire(units: {_ccr});

      await sync.synchronise();

      expect(await stateFor(_ccr), isA<RevenueConfigComplete>());
      expect(await stateFor(_hki), isA<RevenueConfigNeverSynchronised>());
      expect(
        await repository.resolve(
          facts(_catRoom),
          userId: _userA,
          businessUnitId: _unitOf(_catRoom),
        ),
        isA<RevenueConfigurationUnavailable>(),
        reason: 'nothing has been established about Hotel Krishna here',
      );
    });

    test('Hotel Krishna alone leaves Crystal Canopy unsynchronised', () async {
      wire(units: {_hki});

      await sync.synchronise();

      expect(await stateFor(_hki), isA<RevenueConfigComplete>());
      expect(await stateFor(_ccr), isA<RevenueConfigNeverSynchronised>());
    });

    test('a multi-scope user synchronises both', () async {
      await sync.synchronise();

      expect(await stateFor(_ccr), isA<RevenueConfigComplete>());
      expect(await stateFor(_hki), isA<RevenueConfigComplete>());
    });

    test('one user syncing does not vouch for another (D-074)', () async {
      await sync.synchronise();

      expect(await stateFor(_ccr, user: _userA), isA<RevenueConfigComplete>());
      expect(
        await stateFor(_ccr, user: _userB),
        isA<RevenueConfigNeverSynchronised>(),
        reason:
            'reference configuration is shared; the claim that it arrived for somebody '
            'is not',
      );
    });
  });

  group('an empty authoritative dataset is a synchronised answer (B10, B11)', () {
    test('zero subtypes and zero statuses still mean complete', () async {
      // The verified baseline has none of either. "The Owner configured no subtypes" and
      // "this device never asked about subtypes" produce identical row counts and are
      // entirely different facts — which is precisely why completeness is recorded as a
      // dataset list rather than inferred from counts.
      await sync.synchronise();

      expect(await count('revenue_supply_subtypes'), 0);
      expect(await count('business_unit_tax_statuses'), 0);
      expect(await count('revenue_value_bands'), 0);

      expect(await stateFor(_ccr), isA<RevenueConfigComplete>());
      expect(await stateFor(_hki), isA<RevenueConfigComplete>());

      // And Slice 5 may therefore give the configuration answer rather than the device
      // answer: Room resolves generically, with no band required.
      final room = await repository.resolve(
        facts(_catRoom),
        userId: _userA,
        businessUnitId: _unitOf(_catRoom),
      );
      expect(room, isA<RevenueTaxResolved>());
      expect((room as RevenueTaxResolved).rule.valueBandId, isNull);
    });

    test(
      'an unsynchronised device says something different about the same zero',
      () async {
        expect(await count('revenue_supply_subtypes'), 0);
        expect(await stateFor(_ccr), isA<RevenueConfigNeverSynchronised>());
      },
    );
  });

  group('idempotent resync (B15)', () {
    test(
      'three identical runs across a restart leave one representation',
      () async {
        await sync.synchronise();
        await sync.synchronise();

        // A restart: the database file persists, the objects do not.
        final generationBefore =
            ((await stateFor(_ccr)) as RevenueConfigComplete).generation;
        wire();
        await sync.synchronise();

        expect(await count('revenue_tax_rates'), 4);
        expect(await count('revenue_config_snapshots'), 2);
        expect(
          puller.calls,
          1,
          reason: 'the third run is this instance\'s first',
        );
        expect(
          ((await stateFor(_ccr)) as RevenueConfigComplete).generation,
          generationBefore,
          reason: 'the same snapshot has the same generation',
        );
      },
    );

    test('a rule keeps its identity across resyncs', () async {
      await sync.synchronise();
      await sync.synchronise();

      final ids = await db
          .customSelect('SELECT id FROM revenue_tax_rates ORDER BY id')
          .get();
      expect(ids.map((r) => r.data['id']), [
        'rule-banquet',
        'rule-nandbhog',
        'rule-restaurant',
        'rule-room',
      ]);
    });
  });

  group('server-side change (B16)', () {
    test('an end-dated rule and its successor are both represented', () async {
      await sync.synchronise();

      // The server end-dates the open rule and starts a successor from the same date.
      puller.extraRules = [
        puller._rule(
          'rule-restaurant-2',
          _catRestaurant,
          rateBp: 1200,
          from: '2027-04-01',
          seq: 900,
        ),
      ];
      puller.overrideRules = [
        for (final r in puller.baselineRules)
          if (r['id'] == 'rule-restaurant')
            {...r, 'effective_to': '2027-04-01'}
          else
            r,
        ...puller.extraRules,
      ];

      await sync.synchronise();

      final rows = await db
          .customSelect(
            'SELECT id, effective_from, effective_to, rate_basis_points '
            "FROM revenue_tax_rates WHERE revenue_category_id = '$_catRestaurant' "
            'ORDER BY effective_from',
          )
          .get();
      expect(rows, hasLength(2), reason: 'history is kept, not flattened');
      expect(rows.first.data['effective_to'], '2027-04-01');
      expect(rows.last.data['rate_basis_points'], 1200);

      // And both dates resolve to the rule that governed them.
      final june = await repository.resolve(
        facts(_catRestaurant),
        userId: _userA,
        businessUnitId: _unitOf(_catRestaurant),
      );
      expect((june as RevenueTaxResolved).rule.rateBasisPoints, 500);

      final later = await repository.resolve(
        RevenueTaxFacts(
          revenueCategoryId: _catRestaurant,
          businessDate: BusinessDate.of(2027, 6, 15),
        ),
        userId: _userA,
        businessUnitId: _unitOf(_catRestaurant),
      );
      expect((later as RevenueTaxResolved).rule.rateBasisPoints, 1200);
    });

    test(
      'a superseded band keeps its own bounds, and the successor is separate',
      () async {
        // D-100 on the wire. If sync ever updated band A's bounds to band B's, every rule
        // that referenced A would silently start applying to a different range of tariffs,
        // for dates already recorded.
        Map<String, dynamic> band(
          String id,
          int? floor,
          int? ceiling, {
          String? supersededBy,
        }) => {
          'id': id,
          'org_id': _org,
          'revenue_category_id': _catRoom,
          'code': id.toUpperCase(),
          'label': id,
          'floor_minor': floor,
          'ceiling_minor': ceiling,
          'superseded_by_band_id': supersededBy,
          'archived_at': null,
          'row_version': 1,
          'updated_at': '2026-04-01T00:00:00.000Z',
        };

        puller.bands = [band('band-a', 0, 750000)];
        await sync.synchronise();

        puller.bands = [
          band('band-a', 0, 750000, supersededBy: 'band-b'),
          band('band-b', 0, 900000),
        ];
        await sync.synchronise();

        final rows = await db
            .customSelect(
              'SELECT id, floor_minor, ceiling_minor, superseded_by_band_id '
              'FROM revenue_value_bands ORDER BY id',
            )
            .get();
        expect(rows, hasLength(2));
        expect(
          rows.first.data['ceiling_minor'],
          750000,
          reason: 'A is unchanged',
        );
        expect(rows.first.data['superseded_by_band_id'], 'band-b');
        expect(rows.last.data['ceiling_minor'], 900000);

        // Only the live band is offered for a new entry; both remain explainable.
        final selectable = await repository.selectableBands(_catRoom);
        expect(selectable.map((b) => b.id), ['band-b']);
        expect((await repository.bandById('band-a'))!.ceilingMinor, 750000);
      },
    );

    test('a row the snapshot no longer contains is removed', () async {
      puller.bands = [
        {
          'id': 'band-gone',
          'org_id': _org,
          'revenue_category_id': _catRoom,
          'code': 'GONE',
          'label': 'Gone',
          'floor_minor': 0,
          'ceiling_minor': 500000,
          'superseded_by_band_id': null,
          'archived_at': null,
          'row_version': 1,
          'updated_at': '2026-04-01T00:00:00.000Z',
        },
      ];
      await sync.synchronise();
      expect(await count('revenue_value_bands'), 1);

      puller.bands = [];
      await sync.synchronise();

      expect(
        await count('revenue_value_bands'),
        0,
        reason:
            'a band absent from the authoritative dataset must stop being selectable',
      );
    });

    test('a unit absent from a confirmed snapshot loses its claim', () async {
      await sync.synchronise();
      expect(await stateFor(_hki), isA<RevenueConfigComplete>());

      // `pullAll` asks for everything and RLS decides, so the units a confirmed snapshot
      // contains *are* the current scope. A unit missing from it is one the server no
      // longer returns for this user, and continuing to resolve new revenue against
      // yesterday's copy of its configuration would be resolving without authority.
      puller.units = {_ccr};
      authority.units = {_ccr};
      await sync.synchronise();

      expect(await stateFor(_hki), isA<RevenueConfigRevoked>());
      expect(await stateFor(_ccr), isA<RevenueConfigComplete>());
    });

    test('a failed pull withdraws nothing', () async {
      // The counterpart, and the distinction that matters: an answer that did not arrive
      // is not an answer that said no (D-048 §1).
      await sync.synchronise();

      puller.failure = RemoteFailure.serverUnreachable;
      await sync.synchronise();

      expect(await stateFor(_ccr), isA<RevenueConfigComplete>());
      expect(await stateFor(_hki), isA<RevenueConfigComplete>());
    });
  });

  group('authority changes (B13, B14)', () {
    test(
      'a confirmed revocation downgrades the claim and purges the data',
      () async {
        await sync.synchronise();
        expect(await stateFor(_ccr), isA<RevenueConfigComplete>());

        authority.units = {_hki};
        puller.units = {_hki};
        final report = await sync.synchronise();

        expect(report.purge?.didPurge, isTrue);
        expect(report.purge?.revokedUnits, {_ccr});

        final state = await stateFor(_ccr);
        expect(
          state,
          isA<RevenueConfigRevoked>(),
          reason:
              'not merely absent: the device can still say which silence this is',
        );

        final outcome = await repository.resolve(
          facts(_catRestaurant),
          userId: _userA,
          businessUnitId: _unitOf(_catRestaurant),
        );
        expect(
          (outcome as RevenueConfigurationUnavailable).gap,
          RevenueConfigurationGap.revoked,
        );

        // Hotel Krishna is untouched. Losing one property is not losing them all.
        expect(await stateFor(_hki), isA<RevenueConfigComplete>());
      },
    );

    test('a network failure is not a revocation', () async {
      await sync.synchronise();

      authority.forced = AuthorityRefresh.unavailable(
        AuthorityUnavailableReason.offline,
      );
      final report = await sync.synchronise();

      expect(report.authorityConfirmed, isFalse);
      expect(report.purge?.didPurge, isNot(isTrue));
      expect(
        await stateFor(_ccr),
        isA<RevenueConfigComplete>(),
        reason:
            'unknown is not revoked — the cache stands and is shown as stale',
      );
    });

    test('a revocation belongs to the user it happened to', () async {
      await sync.synchronise();

      // A second person has their own successful sync on this installation.
      authority.userId = _userB;
      await sync.synchronise();
      expect(await stateFor(_ccr, user: _userB), isA<RevenueConfigComplete>());

      // User A loses Crystal Canopy. B's claim is not A's to withdraw.
      authority.userId = _userA;
      authority.units = {_hki};
      puller.units = {_hki};
      await sync.synchronise();

      expect(await stateFor(_ccr, user: _userA), isA<RevenueConfigRevoked>());
      expect(
        await stateFor(_ccr, user: _userB),
        isA<RevenueConfigComplete>(),
        reason: 'authority answers are per person (D-051, D-074)',
      );
    });
  });
}
