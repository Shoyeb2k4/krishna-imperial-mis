/// **Phase 5 OA-3 — the Owner Settlement security surface, against the real backend.**
///
/// Four questions the host suite cannot answer, because each is about what Postgres
/// actually decides:
///
/// 1. **The snapshot gate.** Does `owner_ledger_snapshot()` withhold every owner dataset
///    from a reader without `owner_settlement.view`, while RLS still lets the Accountant read
///    the ledger it records into? Seeing the ledger and seeing a settlement are different
///    permissions, and the distinction has to survive on the server (OA-3 Q2).
/// 2. **The start date.** Is `owner_settlement_start_set` the one writer, gated by
///    `owner_masters.manage`, audited, concurrency-checked, and refusing a mid-month date
///    with a sentence (OA-3 Q1)? And is the settings row readable only by the two
///    capabilities that need it?
/// 3. **End to end.** Through the real gateway, the real owner pull, the real reporting
///    delta, the real local engine and the real preview service: does the settlement
///    consume **exactly** the Operating Profit the server's own reporting boundary states,
///    and does a canonical sale, withdrawal and void reach it through both caches?
/// 4. **A shared workstation.** Does one person's owner history stay out of the next
///    person's reach on the same database (D-074, D-208)?
///
/// ## The start date this suite sets is a development fixture
///
/// It sets **2026-05-01** on `krishna-mis-dev`, because a settlement cannot be exercised
/// without one. That is **not** the production 50:50 start date, which is still outstanding
/// and is never guessed. It is chosen to be obviously unlike a real answer — not the
/// financial-year start, not the tax configuration's 2026-04-01 — and to fall inside the
/// development ownership history's 50:50 window (the earlier OA-1 runs left 60/40 months
/// from July 2026, which this suite uses as its live D-204 refusal).
///
/// No client RPC removes a configured start date, deliberately, so the suite cannot put the
/// development project back to "not configured" itself. The run is written to work from
/// either state (D-076), and restoring the baseline afterwards is an administrative act,
/// recorded where it is done.
///
/// ## Run it on its own, or with `--concurrency=1`
///
/// Group 3 asserts deltas — *this* sale moved Operating Profit by exactly its Net Sales,
/// *this* withdrawal moved Owner A's withdrawals by exactly its amount — and an organisation
/// has one owner ledger. Run beside `owner_accounts_live_test.dart`, which records and voids
/// its own Owner A withdrawals, the second read legitimately saw another suite's movements
/// and the delta was ₹-1,45,000 instead of ₹12,345 (OA-3, D-217). The product was right each
/// time; two writers were sharing one fixture. Weakening the assertion to tolerate another
/// writer would stop it proving "exactly once", so the suites run serially instead.
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` run stays hermetic and offline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/sync/canonical_cache_lock.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/authority_gateway.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_reporting_source.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/reporting/remote_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_preview.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/owner_settlement_refresh.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/owner_accounts/settlement/owner_settlement.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:uuid/uuid.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';

/// Found by the teardown across process boundaries — the one identifier that survives
/// one (D-071).
const _marker = 'OA3-LIVE';

/// The development fixture date. See the library comment: not the production answer.
const _fixtureStart = '2026-05-01';

const _owner = 'giridhar@hki.com';
const _accountant = 'accountant@example.com';
const _ccrManager = 'ccr.manager@example.com';
const _dataEntry = 'data.entry@example.com';

String? refusalOf(Object? error) =>
    error is PostgrestException ? error.code : null;

void main() {
  final identitiesPath = Platform.environment[_identitiesVar];
  if (identitiesPath == null || !File(identitiesPath).existsSync()) return;

  final config =
      jsonDecode(File(r'config/dev.json').readAsStringSync())
          as Map<String, dynamic>;
  final identities =
      jsonDecode(File(identitiesPath).readAsStringSync())
          as Map<String, dynamic>;

  final clients = <String, SupabaseClient>{};

  Future<SupabaseClient> sessionFor(String email) async {
    final existing = clients[email];
    if (existing != null) return existing;
    final fresh = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
    await fresh.auth.signInWithPassword(
      email: email,
      password:
          (identities[email] as Map<String, dynamic>)['password'] as String,
    );
    clients[email] = fresh;
    return fresh;
  }

  SupabaseClient anonymous() => SupabaseClient(
    config['SUPABASE_URL'] as String,
    config['SUPABASE_ANON_KEY'] as String,
  );

  Future<Map<String, dynamic>> snapshotAs(String email) async {
    final client = await sessionFor(email);
    return ((await client.rpc<dynamic>('owner_ledger_snapshot')) as Map)
        .cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> settingsRow() async {
    final owner = await sessionFor(_owner);
    final rows = await owner
        .from('owner_settlement_settings')
        .select('ownership_start_date, row_version');
    return rows.isEmpty ? null : rows.single;
  }

  Future<AuthoritySnapshot> authorityOf(String email) async {
    final refresh = await AuthorityGateway(await sessionFor(email)).refresh();
    return (refresh as AuthorityConfirmed).snapshot;
  }

  late SupabaseClient owner;
  late String ccr;
  late String ownerAId;
  late Set<String> allUnits;

  /// Everything this run created that is still open, voided through the real APIs.
  /// Never a delete (D-006).
  Future<int> sweep() async {
    var reversed = 0;
    final sales = await owner
        .from('revenue_document')
        .select('id, row_version')
        .isFilter('voided_at', null)
        .like('notes', '%$_marker%');
    for (final row in sales) {
      await owner.rpc<dynamic>(
        'revenue_void',
        params: {
          'p_id': row['id'],
          'p_reason': 'Reversing an OA-3 live fixture ($_marker)',
          'p_base_row_version': row['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );
      reversed++;
    }
    final movements = await owner
        .from('owner_ledger_entries')
        .select('id, row_version')
        .isFilter('voided_at', null)
        .like('remarks', '%$_marker%');
    for (final row in movements) {
      await owner.rpc<dynamic>(
        'owner_movement_void',
        params: {
          'p_id': row['id'],
          'p_reason': 'Reversing an OA-3 live fixture ($_marker)',
          'p_base_row_version': row['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );
      reversed++;
    }
    return reversed;
  }

  setUpAll(() async {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    owner = await sessionFor(_owner);
    ccr =
        (await owner
                .from('business_units')
                .select('id')
                .eq('code', 'CCR')
                .single())['id']
            as String;
    ownerAId =
        (await owner
                .from('owners')
                .select('id')
                .eq('code', 'OA1_TEST_OWNER_A')
                .single())['id']
            as String;
    allUnits = {
      for (final row in await owner.from('business_units').select('id'))
        row['id'] as String,
    };
    // Before as well as after: a suite that depends on its own teardown can pass once
    // (D-076).
    await sweep();
  });

  tearDownAll(() async {
    await sweep();
    expect(
      await sweep(),
      0,
      reason: 'the run leaves no OA-3 sale or owner movement open',
    );
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('1 · the snapshot gate (OA-3 Q2)', () {
    test('the Owner is authorised, and handed every owner dataset', () async {
      final snapshot = await snapshotAs(_owner);
      expect(snapshot['settlement_authorised'], isTrue);
      for (final dataset in const [
        'movements',
        'owners',
        'ownership_shares',
        'family_members',
      ]) {
        expect(
          snapshot[dataset],
          isA<List<dynamic>>(),
          reason:
              '$dataset is present for the one holder of owner_settlement.view',
        );
      }
      expect(snapshot['snapshot_id'], isA<String>());
      expect(snapshot['server_time'], isA<String>());
    });

    test(
      'the Accountant is refused the settlement and keeps the ledger it records into',
      () async {
        // The RED this migration was written against: before it, this principal received
        // 159 movements, 3 owners, 34 shares and 2 family links.
        final snapshot = await snapshotAs(_accountant);
        expect(snapshot['settlement_authorised'], isFalse);
        for (final dataset in const [
          'movements',
          'owners',
          'ownership_shares',
          'family_members',
          'ownership_start_date',
        ]) {
          expect(
            snapshot[dataset],
            isNull,
            reason:
                '$dataset is withheld, never an empty list: an empty list would be a '
                'claim that the owners hold nothing (D-163)',
          );
        }

        // And the distinction the ruling preserves: recording authority still reads the
        // ledger, through RLS, exactly as OA-1 shipped it.
        final accountant = await sessionFor(_accountant);
        expect(
          await accountant.from('owner_ledger_entries').select('id').limit(1),
          isNotEmpty,
          reason:
              'seeing the ledger and seeing a settlement are different permissions',
        );
      },
    );

    test('a Manager and a Data Entry principal are refused as well', () async {
      for (final email in const [_ccrManager, _dataEntry]) {
        final snapshot = await snapshotAs(email);
        expect(snapshot['settlement_authorised'], isFalse, reason: email);
        expect(snapshot['movements'], isNull, reason: email);
        expect(snapshot['ownership_shares'], isNull, reason: email);
      }
    });

    test('an anonymous caller cannot call the snapshot at all', () async {
      final anon = anonymous();
      await expectLater(
        anon.rpc<dynamic>('owner_ledger_snapshot'),
        throwsA(isA<PostgrestException>()),
      );
      await anon.dispose();
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('2 · the settlement start date (OA-3 Q1)', () {
    // Decided once, from the live state, so the run works from either starting point.
    Map<String, dynamic>? initial;

    setUpAll(() async {
      initial = await settingsRow();
    });

    test(
      'while nothing is configured, the Owner is told so and no default appears',
      () async {
        if (initial != null) {
          markTestSkipped(
            'a start date is already configured on this project (a previous run\'s '
            'fixture); the not-configured state is proven by the host suite',
          );
          return;
        }
        final snapshot = await snapshotAs(_owner);
        expect(snapshot['settlement_authorised'], isTrue);
        expect(
          snapshot['ownership_start_date'],
          isNull,
          reason: 'absent means not configured; nothing is defaulted (Q1)',
        );
      },
    );

    test('a caller without owner_masters.manage cannot set it', () async {
      for (final email in const [_accountant, _ccrManager, _dataEntry]) {
        final client = await sessionFor(email);
        try {
          await client.rpc<dynamic>(
            'owner_settlement_start_set',
            params: {
              'p_ownership_start_date': _fixtureStart,
              'p_mutation_id': const Uuid().v4(),
            },
          );
          fail('$email configured the settlement start date');
        } catch (e) {
          expect(refusalOf(e), anyOf('KM001', 'KM002'), reason: email);
        }
      }
      expect(
        await settingsRow(),
        initial,
        reason: 'and nothing changed on the way to the refusal',
      );
    });

    test('an anonymous caller cannot reach the RPC', () async {
      final anon = anonymous();
      await expectLater(
        anon.rpc<dynamic>(
          'owner_settlement_start_set',
          params: {'p_ownership_start_date': _fixtureStart},
        ),
        throwsA(isA<PostgrestException>()),
      );
      await anon.dispose();
    });

    test('a mid-month or missing date is refused with a sentence', () async {
      for (final date in const ['2026-05-15', null]) {
        try {
          await owner.rpc<dynamic>(
            'owner_settlement_start_set',
            params: {
              'p_ownership_start_date': date,
              'p_base_row_version': initial?['row_version'],
              'p_mutation_id': const Uuid().v4(),
            },
          );
          fail('the start date $date was accepted');
        } on PostgrestException catch (e) {
          expect(e.code, 'KM031', reason: 'date $date');
          expect(
            e.message,
            anyOf(contains('start of a month'), contains('Choose the date')),
            reason: 'a refusal a person can act on, not a constraint name',
          );
          expect(e.message, isNot(contains('owner_settlement_start_first')));
        }
      }
    });

    test(
      'the Owner sets it; a replay changes nothing; a stale base is a conflict',
      () async {
        final mutation = const Uuid().v4();
        final base = initial?['row_version'] as int?;

        final first =
            ((await owner.rpc<dynamic>(
                      'owner_settlement_start_set',
                      params: {
                        'p_ownership_start_date': _fixtureStart,
                        'p_base_row_version': base,
                        'p_mutation_id': mutation,
                      },
                    ))
                    as Map)
                .cast<String, dynamic>();
        expect(first['status'], base == null ? 'created' : 'updated');
        expect(first['ownership_start_date'], _fixtureStart);
        final version = first['row_version'] as int;
        expect(version, (base ?? 0) + 1);

        // Redelivery of the same intent replays the stored answer (D-004).
        final replay =
            ((await owner.rpc<dynamic>(
                      'owner_settlement_start_set',
                      params: {
                        'p_ownership_start_date': _fixtureStart,
                        'p_base_row_version': base,
                        'p_mutation_id': mutation,
                      },
                    ))
                    as Map)
                .cast<String, dynamic>();
        expect(replay['status'], 'replayed');
        expect(replay['row_version'], version);
        expect((await settingsRow())!['row_version'], version);

        // A different intent based on a state that no longer exists is refused (D-021).
        for (final stale in <int?>[null, version - 1]) {
          try {
            await owner.rpc<dynamic>(
              'owner_settlement_start_set',
              params: {
                'p_ownership_start_date': '2026-06-01',
                'p_base_row_version': stale,
                'p_mutation_id': const Uuid().v4(),
              },
            );
            fail('a stale base ($stale) overwrote the start date');
          } catch (e) {
            expect(refusalOf(e), 'KM003', reason: 'base $stale');
          }
        }
        final after = await settingsRow();
        expect(after!['ownership_start_date'], _fixtureStart);
        expect(after['row_version'], version);
      },
    );

    test('every change is audited with its before and after values', () async {
      final audits = await owner
          .from('audit_logs')
          .select('action, before_state, after_state, actor_id, mutation_id')
          .eq('entity_type', 'owner_settlement_settings')
          .eq('action', 'ownership_start_set')
          .order('occurred_at', ascending: false)
          .limit(1);
      expect(audits, hasLength(1));
      final latest = audits.single;
      expect(
        (latest['after_state'] as Map)['ownership_start_date'],
        _fixtureStart,
      );
      expect(latest['actor_id'], owner.auth.currentUser!.id);
      expect(latest['mutation_id'], isNotNull);
    });

    test(
      'the settings row is readable only by the capabilities that need it',
      () async {
        expect(await settingsRow(), isNotNull, reason: 'the Owner reads it');
        for (final email in const [_accountant, _ccrManager, _dataEntry]) {
          final client = await sessionFor(email);
          expect(
            await client.from('owner_settlement_settings').select('org_id'),
            isEmpty,
            reason:
                '$email holds neither owner_settlement.view nor owner_masters.manage',
          );
        }
        final anon = anonymous();
        await expectLater(
          anon.from('owner_settlement_settings').select('org_id'),
          throwsA(isA<PostgrestException>()),
          reason: 'anon holds no SELECT on the table at all',
        );
        await anon.dispose();

        await expectLater(
          owner
              .from('owner_settlement_settings')
              .update({'ownership_start_date': '2026-06-01'})
              .eq('ownership_start_date', _fixtureStart),
          throwsA(isA<PostgrestException>()),
          reason:
              'no client role writes the table; the RPC is the one writer (D-162)',
        );
      },
    );

    test(
      'and the snapshot states it, to the Owner and to nobody else',
      () async {
        expect(
          (await snapshotAs(_owner))['ownership_start_date'],
          _fixtureStart,
        );
        expect((await snapshotAs(_accountant))['ownership_start_date'], isNull);
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('3 · the preview, end to end through the real composition', () {
    late AppDatabase db;
    late AuthoritySnapshot authority;
    late OwnerSettlementRepository repository;
    late OwnerSettlementRefresher refresher;
    final today = BusinessDate.of(2026, 9, 11);
    final june = BusinessDate.of(2026, 6, 30);

    setUpAll(() async {
      db = AppDatabase(NativeDatabase.memory());
      authority = await authorityOf(_owner);
      final userId = authority.userId;
      repository = OwnerSettlementRepository(
        db,
        principal: authority.principal,
      );
      refresher = OwnerSettlementRefresher(
        lock: CanonicalCacheLock(),
        ownerSync: OwnerSettlementSync(
          database: db,
          gateway: OwnerLedgerGateway(owner),
          ownerUserId: userId,
        ),
        reportingSync: ReportingSync(
          cache: ReportingCache(db),
          gateway: ReportingGateway(owner),
          ownerUserId: userId,
          orgId: authority.orgId,
        ),
        repository: repository,
      );
    });

    tearDownAll(() => db.close());

    /// A fresh engine each time, because coverage markers are loaded once per source —
    /// exactly why the page invalidates its source after a refresh.
    Future<OwnerSettlementPreview> previewOf(int year, int month) async {
      final cache = ReportingCache(db);
      final engine = LocalReportingEngine(
        CachedReportingSource(
          cache: cache,
          principal: authority.principal,
          coverage: await MarkerCoverage.load(cache, authority.userId),
        ),
      );
      return OwnerSettlementPreviewService(
        lock: CanonicalCacheLock(),
        repository: repository,
        reporting: engine,
        principal: authority.principal,
      ).preview(year: year, month: month, businessUnitIds: allUnits);
    }

    Future<Money> serverProfit(BusinessDate from, BusinessDate to) async {
      final remote = RemoteReportingEngine(
        RemoteReportingSource(ReportingGateway(owner)),
      );
      final envelope = await remote.report(
        ReportRequest(
          period: CustomRangePeriod(from: from, to: to),
          scope: ReportingScope(allUnits),
        ),
      );
      return envelope.resultOrNull!.operatingProfit;
    }

    Future<OwnerSettlementPreviewReady> refreshedJune() async {
      final report = await refresher.refresh(
        businessUnitIds: allUnits,
        periodEnd: june,
        today: today,
      );
      expect(
        report.succeeded,
        isTrue,
        reason: 'both pulls arrived: owner ${report.owner}',
      );
      final preview = await previewOf(2026, 6);
      expect(preview, isA<OwnerSettlementPreviewReady>(), reason: '$preview');
      return preview as OwnerSettlementPreviewReady;
    }

    OwnerSettlementLine lineOf(OwnerSettlementPreviewReady ready, String id) =>
        ready.statement.lines.singleWhere((l) => l.ownerId == id);

    late OwnerSettlementPreviewReady baseline;

    test(
      'before any pull there is no figure, and the reason is the missing history',
      () async {
        final preview = await previewOf(2026, 6);
        expect(
          (preview as OwnerSettlementPreviewUnavailable).reason,
          OwnerSettlementUnavailableReason.ownerHistoryNotDownloaded,
        );
      },
    );

    test(
      'after both pulls, the settlement consumes exactly the server Operating Profit',
      () async {
        baseline = await refreshedJune();
        final start = BusinessDate.of(2026, 5, 1);

        expect(baseline.ownershipStartDate, start);
        expect(
          baseline.statement.cumulativeOperatingProfit,
          await serverProfit(start, june),
          reason:
              'the local engine over the synchronised cache and the server boundary '
              'agree to the paisa, and the settlement allocates that figure — one P&L '
              'specification, no second calculation (D-020)',
        );
        expect(
          baseline.statement.operatingProfit,
          await serverProfit(BusinessDate.of(2026, 6, 1), june),
        );

        // OA-2 section 9, over live data: nothing is lost and nothing invented.
        expect(
          baseline.statement.totalEntitlementAllocated.paise +
              baseline.statement.undistributedRemainder.paise,
          baseline.statement.cumulativeOperatingProfit.paise,
        );
        expect(baseline.statement.lines, hasLength(2));

        // Each dataset carries its own evidence, and no combined "as of" exists.
        expect(baseline.ownerHistory.snapshotId, isNotEmpty);
        expect(baseline.reportingFreshness, isNotNull);
        expect(baseline.ownerNames, isNotEmpty);
      },
    );

    test(
      'a sale and a withdrawal reach the settlement through both caches, exactly once',
      () async {
        // ₹1,00,000 billed at Restaurant, 5% inclusive: net 9523810 paise.
        final saleId = const Uuid().v7();
        await owner.rpc<dynamic>(
          'revenue_create',
          params: {
            'p_id': saleId,
            'p_business_unit_id': ccr,
            'p_revenue_category_id':
                (await owner
                        .from('revenue_categories')
                        .select('id')
                        .eq('code', 'RESTAURANT')
                        .eq('business_unit_id', ccr)
                        .single())['id']
                    as String,
            'p_business_date': '2026-06-10',
            'p_notes': _marker,
            'p_components': [
              {'entered_amount_minor': 10000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        await owner.rpc<dynamic>(
          'owner_movement_create',
          params: {
            'p_id': const Uuid().v4(),
            'p_business_unit_id': ccr,
            'p_business_date': '2026-06-12',
            'p_movement_type': 'withdrawal',
            'p_amount_minor': 1234500,
            'p_owner_id': ownerAId,
            'p_remarks': 'OA-3 live preview $_marker',
            'p_mutation_id': const Uuid().v4(),
          },
        );

        final after = await refreshedJune();

        expect(
          after.statement.cumulativeOperatingProfit.paise -
              baseline.statement.cumulativeOperatingProfit.paise,
          9523810,
          reason: 'the sale Net Sales, once — never the gross, never twice',
        );
        expect(
          after.statement.operatingProfit.paise -
              baseline.statement.operatingProfit.paise,
          9523810,
        );
        expect(
          lineOf(after, ownerAId).withdrawals.paise -
              lineOf(baseline, ownerAId).withdrawals.paise,
          1234500,
          reason: 'the withdrawal is Owner A\'s, and nobody else\'s',
        );

        // The closing position is the OA-2 identity over the result's own fields.
        for (final line in after.statement.lines) {
          expect(
            line.closingPosition.paise,
            line.openingPosition.paise +
                line.profitEntitlement.paise -
                line.withdrawals.paise -
                line.ncConsumption.paise -
                line.settlementPaid.paise +
                line.adjustmentCredits.paise -
                line.adjustmentDebits.paise,
            reason: line.ownerId,
          );
        }
        expect(
          after.statement.cumulativeOperatingProfit,
          await serverProfit(BusinessDate.of(2026, 5, 1), june),
        );
      },
    );

    test(
      'voiding both returns every figure to the baseline, to the paisa',
      () async {
        expect(await sweep(), 2);
        final restored = await refreshedJune();

        expect(
          restored.statement.cumulativeOperatingProfit,
          baseline.statement.cumulativeOperatingProfit,
        );
        expect(
          restored.statement.operatingProfit,
          baseline.statement.operatingProfit,
        );
        for (final line in restored.statement.lines) {
          final before = lineOf(baseline, line.ownerId);
          expect(line.withdrawals, before.withdrawals, reason: line.ownerId);
          expect(
            line.closingPosition,
            before.closingPosition,
            reason: line.ownerId,
          );
        }
      },
    );

    test('a month before the start date refuses, never ₹0', () async {
      expect(
        ((await previewOf(2026, 4)) as OwnerSettlementPreviewUnavailable)
            .reason,
        OwnerSettlementUnavailableReason.beforeStartDate,
      );
    });

    test(
      'a month whose live ownership is not 50:50 refuses (D-204, over real history)',
      () async {
        // July 2026 on this project holds OA-1's pre-ruling 6000/5000 rows.
        expect(
          ((await previewOf(2026, 7)) as OwnerSettlementPreviewUnavailable)
              .reason,
          OwnerSettlementUnavailableReason.ownershipUnavailable,
        );
      },
    );

    test(
      'the Accountant and a Manager are refused the preview by the service itself',
      () async {
        for (final email in const [_accountant, _ccrManager]) {
          final other = await authorityOf(email);
          final preview = await OwnerSettlementPreviewService(
            lock: CanonicalCacheLock(),
            repository: OwnerSettlementRepository(
              db,
              principal: other.principal,
            ),
            reporting: LocalReportingEngine(
              CachedReportingSource(
                cache: ReportingCache(db),
                principal: other.principal,
                coverage: await MarkerCoverage.load(
                  ReportingCache(db),
                  other.userId,
                ),
              ),
            ),
            principal: other.principal,
          ).preview(year: 2026, month: 6, businessUnitIds: allUnits);
          expect(
            (preview as OwnerSettlementPreviewUnavailable).reason,
            OwnerSettlementUnavailableReason.notAuthorised,
            reason: email,
          );
        }
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('4 · a shared workstation (D-074, D-208)', () {
    test(
      'the next person on the same database reaches none of the owner history',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final ownerAuthority = await authorityOf(_owner);
        final ownerResult = await OwnerSettlementSync(
          database: db,
          gateway: OwnerLedgerGateway(owner),
          ownerUserId: ownerAuthority.userId,
        ).synchronise();
        expect(ownerResult, isA<OwnerSettlementSynchronised>());
        final ownerRepository = OwnerSettlementRepository(
          db,
          principal: ownerAuthority.principal,
        );
        expect(await ownerRepository.coverage(), isNotNull);

        // D-208: nothing writes the organisation-global OA-1 masters, so they carry no
        // ratio or name across a user switch.
        expect(await db.select(db.owners).get(), isEmpty);
        expect(await db.select(db.ownershipShares).get(), isEmpty);
        expect(await db.select(db.ownerFamilyMembers).get(), isEmpty);

        // The Accountant signs in on the same installation.
        final accountant = await sessionFor(_accountant);
        final accountantAuthority = await authorityOf(_accountant);
        final accountantResult = await OwnerSettlementSync(
          database: db,
          gateway: OwnerLedgerGateway(accountant),
          ownerUserId: accountantAuthority.userId,
        ).synchronise();
        expect(
          accountantResult,
          isA<OwnerSettlementSyncNotAuthorised>(),
          reason:
              'the server withheld it, and the client says so rather than zero',
        );
        final accountantRepository = OwnerSettlementRepository(
          db,
          principal: accountantAuthority.principal,
        );
        expect(await accountantRepository.coverage(), isNull);
        expect(await accountantRepository.ownerNames(), isEmpty);
        expect(
          (await accountantRepository.ownershipShares()).shares,
          isEmpty,
          reason:
              'the Owner\'s rows are keyed to the Owner, not to the installation',
        );

        // And signing out takes the previous person's canonical cache with it (D-053).
        await ScopeCachePurge(db).purgeAllScopedCache();
        expect(await ownerRepository.coverage(), isNull);
        expect(await db.select(db.canonicalOwnerMovements).get(), isEmpty);
        expect(await db.select(db.canonicalOwners).get(), isEmpty);
        expect(await db.select(db.canonicalOwnershipShares).get(), isEmpty);
      },
    );
  });
}
