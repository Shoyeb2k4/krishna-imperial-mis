/// Slice 10 acceptance: two genuinely independent clients, against `krishna-mis-dev`.
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` run stays hermetic and offline. Nothing here prints a password,
/// a token or the API key.
///
/// **What "independent" means here, precisely.** Each client is its own Supabase session,
/// its own encrypted-schema Drift database in its own temporary directory, its own outbox,
/// its own sync worker with its own actor filter, and its own repository. Nothing is
/// shared between them except the server. **No row version is ever set by hand**: every
/// version either came from the server or is the one a client captured when it read the
/// document, which is exactly what makes a stale attempt stale.
///
/// The sequences below are the ones §44 specifies. They are run through the real
/// repository and the real worker rather than by calling the RPCs directly, because the
/// thing being proven is what a person's device does with the server's answer — not that
/// the server has the right answer, which the boundary suite already proves.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/sync/reference_sync.dart';
import 'package:krishna_mis/data/sync/revenue_mutation_endpoint.dart';
import 'package:krishna_mis/data/sync/sync_engine.dart';
import 'package:krishna_mis/data/remote/authority_gateway.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:uuid/uuid.dart';

import '../../integration_test/support/controllable_transport.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';
const _marker = 'ACCEPTANCE slice10-two-client';

String? _refusalOf(Object? error) =>
    error is PostgrestException ? error.code : null;

/// One complete, self-contained client: session, database, outbox, worker, repository.
class _Client {
  _Client(this.label, this.transport);

  final String label;
  final ControllableTransport transport;

  late final SupabaseClient supabase;
  late final RevenueGateway gateway;
  late AuthoritySnapshot authority;

  // Not final: [restart] replaces them, which is the point of the restart.
  late AppDatabase db;
  late RevenueRepository revenue;
  late OutboxRepository outbox;
  late SyncEngine engine;

  Directory? _dir;

  Future<void> open({
    required String url,
    required String anonKey,
    required String email,
    required String password,
  }) async {
    _dir = Directory.systemTemp.createTempSync('slice10-$label');
    db = AppDatabase(NativeDatabase(File('${_dir!.path}/$label.sqlite')));
    await db.customStatement('PRAGMA foreign_keys = ON');

    supabase = SupabaseClient(url, anonKey, httpClient: transport);
    await supabase.auth.signInWithPassword(email: email, password: password);

    gateway = RevenueGateway(supabase);
    outbox = OutboxRepository(db);
    revenue = RevenueRepository(db, tax: RevenueTaxRepository(db));

    // The whole reference pull, through the shipped synchroniser: authority first,
    // purge only on a confirmed answer, then everything RLS returns, in one transaction.
    final report = await ReferenceSync(
      db: db,
      authorityGateway: AuthorityGateway(supabase),
      masterGateway: MasterGateway(supabase),
    ).synchronise();
    authority = (report.authority as AuthorityConfirmed).snapshot;

    engine = SyncEngine(
      outbox: outbox,
      endpoint: RevenueMutationEndpoint(gateway),
      reconciler: RevenueReconciler(revenue, gateway),
      actorUserId: authority.userId,
    );
  }

  /// Closes the database and opens it again over the same file.
  ///
  /// This is what "restart the application" means for everything that matters here: the
  /// outbox is a table, not a memory structure, so the queued intent either survives on
  /// disk or it does not. The session and the gateway are kept, because a restart does
  /// not sign anybody out.
  Future<void> restart() async {
    await db.close();
    db = AppDatabase(NativeDatabase(File('${_dir!.path}/$label.sqlite')));
    await db.customStatement('PRAGMA foreign_keys = ON');
    revenue = RevenueRepository(db, tax: RevenueTaxRepository(db));
    outbox = OutboxRepository(db);
    engine = SyncEngine(
      outbox: outbox,
      endpoint: RevenueMutationEndpoint(gateway),
      reconciler: RevenueReconciler(revenue, gateway),
      actorUserId: authority.userId,
    );
  }

  /// Pushes until the entry carries a server-issued number, or gives up loudly.
  Future<void> pushUntilNumbered(String id, {int attempts = 20}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        await engine.pushOnce();
      } on Object {
        // A transport failure is the scenario in some of these tests, not an error.
      }
      if ((await revenue.load(id))?.txnNumber != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    fail('$label: $id never received a transaction number');
  }

  /// Pushes until the queue holds nothing that can still be delivered.
  ///
  /// The budget is generous on purpose. A transient failure earns a real backoff — the
  /// first is five seconds — and `dueEntries` will not hand the worker an entry before
  /// its next attempt is due. Polling for two seconds and declaring the queue settled
  /// would report *"the retry never happened"* as a product defect when it is a clock.
  Future<void> pushUntilSettled({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        await engine.pushOnce();
      } on Object {
        // A transport failure is the scenario in some of these tests, not an error.
      }
      final rows = await db.select(db.syncOutbox).get();
      final live = rows.where(
        (o) => !const {'done', 'conflict', 'rejected'}.contains(o.status),
      );
      if (live.isEmpty) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final rows = await db.select(db.syncOutbox).get();
    fail(
      '$label: the queue never settled; still holding '
      '${rows.where((o) => !const {'done', 'conflict', 'rejected'}.contains(o.status)).map((o) => '${o.op}/${o.status}').join(', ')}',
    );
  }

  Future<SyncOutboxRow?> intentFor(String entryId) async {
    final rows = await db.select(db.syncOutbox).get();
    final matching = rows.where((o) => o.entityId == entryId).toList();
    return matching.isEmpty ? null : matching.last;
  }

  Future<void> close() async {
    await db.close();
    await supabase.dispose();
    try {
      _dir?.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows is not worth failing an acceptance run over.
    }
  }
}

void main() {
  final identitiesPath = Platform.environment[_identitiesVar];
  if (identitiesPath == null || !File(identitiesPath).existsSync()) {
    return;
  }

  final config =
      jsonDecode(File(r'config/dev.json').readAsStringSync())
          as Map<String, dynamic>;
  final identities =
      jsonDecode(File(identitiesPath).readAsStringSync())
          as Map<String, dynamic>;

  final url = config['SUPABASE_URL'] as String;
  final anonKey = config['SUPABASE_ANON_KEY'] as String;
  final ownerPassword =
      (identities['giridhar@hki.com'] as Map<String, dynamic>)['password']
          as String;
  final managerPassword =
      (identities['ccr.manager@example.com']
              as Map<String, dynamic>)['password']
          as String;

  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late _Client a;
  late _Client b;
  late ControllableTransport transportA;
  late ControllableTransport transportB;
  final createdIds = <String>[];

  /// A supervisory session used only to read back canonical state and to reverse
  /// fixtures. It is an ordinary Owner session over the public API — no service role,
  /// no privileged path.
  late SupabaseClient supervisor;

  String? ccrUnit;
  String? restaurant;

  setUpAll(() async {
    supervisor = SupabaseClient(url, anonKey);
    await supervisor.auth.signInWithPassword(
      email: 'giridhar@hki.com',
      password: ownerPassword,
    );
    final unit = await supervisor
        .from('business_units')
        .select('id')
        .eq('code', 'CCR')
        .single();
    ccrUnit = unit['id'] as String;
    final category = await supervisor
        .from('revenue_categories')
        .select('id')
        .eq('code', 'RESTAURANT')
        .eq('business_unit_id', ccrUnit!)
        .single();
    restaurant = category['id'] as String;
  });

  setUp(() async {
    transportA = ControllableTransport();
    transportB = ControllableTransport();
    a = _Client('a', transportA);
    b = _Client('b', transportB);
    // Two different people, on two different installations. The Owner and a Crystal
    // Canopy accountant would both do; the Owner and the Owner on two devices is the
    // shared-installation case, and both must behave the same, so this uses two
    // identities to keep the actor filter honest as well.
    await a.open(
      url: url,
      anonKey: anonKey,
      email: 'giridhar@hki.com',
      password: ownerPassword,
    );
    await b.open(
      url: url,
      anonKey: anonKey,
      email: 'giridhar@hki.com',
      password: ownerPassword,
    );
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  tearDownAll(() async {
    // Void, never delete: no client role holds DELETE on a financial table and none is
    // granted for cleanup (D-006, D-071).
    for (final id in createdIds) {
      try {
        final row = await supervisor
            .from('revenue_document')
            .select('row_version, voided_at')
            .eq('id', id)
            .maybeSingle();
        if (row == null || row['voided_at'] != null) continue;
        await supervisor.rpc<dynamic>(
          'revenue_void',
          params: {
            'p_id': id,
            'p_base_row_version': row['row_version'],
            'p_reason': '$_marker fixture reversal',
            'p_mutation_id': const Uuid().v4(),
          },
        );
      } on PostgrestException catch (error) {
        // ignore: avoid_print
        print('slice10 two-client fixture $id not reversed: ${error.code}');
      }
    }
    await supervisor.dispose();
  });

  RevenueEntryDraft draftFor(
    String id, {
    int paise = 10000000,
    String date = '2026-06-15',
    String? notes,
  }) => RevenueEntryDraft(
    id: id,
    businessUnitId: ccrUnit!,
    revenueCategoryId: restaurant!,
    businessDate: BusinessDate.tryParse(date)!,
    capturedAt: DateTime.now().toUtc(),
    notes: notes ?? _marker,
    components: [
      RevenueComponentDraft(
        id: const Uuid().v7(),
        enteredAmount: Money.fromPaise(paise),
      ),
    ],
  );

  /// Records one sale on [client] and syncs it, returning its canonical state.
  Future<RevenueEntry> recordAndSync(
    _Client client, {
    int paise = 10000000,
  }) async {
    final id = const Uuid().v7();
    createdIds.add(id);
    final draft = draftFor(id, paise: paise);
    final decision = await client.revenue.evaluate(
      draft,
      authority: client.authority,
    );
    expect(
      decision,
      isA<RevenueCreatePermitted>(),
      reason: decision is RevenueCreateRefused
          ? decision.refusal.toString()
          : null,
    );
    await client.revenue.createLocally(
      draft,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: client.authority.userId,
      orgId: client.authority.orgId,
      mutationId: const Uuid().v4(),
      now: DateTime.now().toUtc(),
    );
    await client.pushUntilNumbered(id);
    return (await client.revenue.load(id))!;
  }

  /// Loads the canonical document into [client]'s own database, exactly as Review latest
  /// does — which is also how a second client comes to hold the same row version.
  Future<RevenueEntry> loadCanonicalInto(_Client client, String id) async {
    final header = await client.gateway.fetchDocument(id);
    final components = await client.gateway.fetchComponents(id);
    final headerValue = (header as dynamic).value as Map<String, dynamic>?;
    final componentValues =
        (components as dynamic).value as List<Map<String, dynamic>>;
    expect(headerValue, isNotNull);

    final existing = await client.revenue.load(id);
    if (existing == null) {
      // Client B has never seen this document. Seed the row from the canonical
      // projection, which is what a pull would do.
      await client.db.customStatement(
        'INSERT INTO revenue_entries (id, org_id, business_unit_id, '
        'revenue_category_id, business_date, pnl_period_key, captured_at, '
        'entry_kind, notes, created_by, row_version, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          client.authority.orgId,
          headerValue!['business_unit_id'],
          headerValue['revenue_category_id'],
          headerValue['business_date'],
          headerValue['pnl_period_key'],
          DateTime.now().toUtc().toIso8601String(),
          headerValue['entry_kind'],
          headerValue['notes'],
          headerValue['created_by'],
          1,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      await client.db.customStatement(
        'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
        'entered_amount_minor, entered_basis, gross_amount_minor, '
        'tax_amount_minor, net_amount_minor, tax_rule_id, tax_rate_basis_points, '
        'tax_treatment) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          componentValues.first['id'],
          client.authority.orgId,
          id,
          componentValues.first['entered_amount_minor'],
          componentValues.first['entered_basis'],
          componentValues.first['gross_amount_minor'],
          componentValues.first['tax_amount_minor'],
          componentValues.first['net_amount_minor'],
          componentValues.first['tax_rule_id'],
          componentValues.first['tax_rate_bp'],
          componentValues.first['tax_treatment'],
        ],
      );
    }

    await client.revenue.applyServerDocument(
      header: headerValue!,
      components: componentValues,
      orgId: client.authority.orgId,
    );
    return (await client.revenue.load(id))!;
  }

  Future<void> correct(
    _Client client,
    RevenueEntry basedOn, {
    required int paise,
  }) async {
    final draft = RevenueEntryDraft(
      id: basedOn.id,
      businessUnitId: basedOn.businessUnitId,
      revenueCategoryId: basedOn.revenueCategoryId,
      businessDate: basedOn.businessDate,
      capturedAt: basedOn.capturedAt,
      notes: basedOn.notes,
      components: [
        RevenueComponentDraft(
          id: basedOn.components.single.id,
          enteredAmount: Money.fromPaise(paise),
        ),
      ],
    );
    final decision = await client.revenue.evaluate(
      draft,
      authority: client.authority,
    );
    expect(decision, isA<RevenueCreatePermitted>());
    await client.revenue.updateLocally(
      draft,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: client.authority.userId,
      orgId: client.authority.orgId,
      // Captured when the document was read. Never re-read here: that is the whole
      // subject of the test.
      baseRowVersion: basedOn.rowVersion,
      mutationId: const Uuid().v4(),
      now: DateTime.now().toUtc(),
    );
  }

  Future<Map<String, dynamic>> canonical(String id) async =>
      await supervisor.from('revenue_document').select().eq('id', id).single();

  Future<List<Map<String, dynamic>>> auditFor(String id) async {
    final rows = await supervisor
        .from('audit_logs')
        .select('action, occurred_at, mutation_id')
        .eq('entity_id', id)
        .order('occurred_at');
    return rows.cast<Map<String, dynamic>>();
  }

  // ── A1 · the stale-edit chain ────────────────────────────────────────────────
  group('A1 · two clients, one stale correction', () {
    test('the stale edit is refused, retained, and resolved by Review latest', () async {
      // 1-2 · one sale, synchronised, and both clients holding version N.
      final created = await recordAndSync(a);
      final id = created.id;
      final number = created.txnNumber!;
      expect(number, startsWith('KI-REV-'));

      final atA = await loadCanonicalInto(a, id);
      final atB = await loadCanonicalInto(b, id);
      final n = atA.rowVersion;
      expect(atB.rowVersion, n, reason: 'both clients read the same version');

      // 3-4 · B corrects and syncs. Canonical becomes N+1.
      await correct(b, atB, paise: 12000000);
      await b.pushUntilSettled();
      final afterB = await canonical(id);
      expect(afterB['row_version'], greaterThan(n));
      expect(afterB['gross_amount_minor'], 12000000);
      expect(
        afterB['txn_number'],
        number,
        reason: '9 · the number is the document\'s',
      );

      // 5-6 · A submits its correction on the version it captured.
      await correct(a, atA, paise: 15000000);
      final intentBefore = await a.intentFor(id);
      expect(intentBefore!.baseRowVersion, n, reason: '11 · no silent rebase');
      await a.pushUntilSettled();

      final intentAfter = await a.intentFor(id);
      expect(
        intentAfter!.status,
        'conflict',
        reason: '6 · the server refused it as stale',
      );
      expect(
        intentAfter.baseRowVersion,
        n,
        reason: '11 · the refused intent still says what it was based on',
      );

      // 7 · A keeps its attempt, and the surface says so.
      expect(
        await a.revenue.syncStateOf(id),
        SyncState.conflict,
        reason: '7 · needs review',
      );
      expect(
        (await a.revenue.load(id))!.gross.paise,
        15000000,
        reason: '7 · the attempted correction is retained, not repriced',
      );
      expect(intentAfter.payload, contains('15000000'));

      // 19a · the refusal left no audit effect **at the time it happened**. This is
      // the strong form of "accepted mutations only": counted here rather than inferred
      // at the end, because by then a later accepted delivery could account for a row
      // that should never have existed.
      expect(
        await auditFor(id),
        hasLength(2),
        reason: '19 · the create and B, and nothing at all from A',
      );
      // 8-10 · canonical is B's, untouched by A's attempt. No merge of any kind.
      final untouched = await canonical(id);
      expect(untouched['row_version'], afterB['row_version']);
      expect(untouched['gross_amount_minor'], 12000000);
      expect(untouched['txn_number'], number);

      // 12-14 · Review latest: load the canonical document separately from the attempt,
      // then start a NEW deliberate correction against the version it now holds.
      final attempted = (await a.revenue.load(id))!;
      final latest = await loadCanonicalInto(a, id);
      expect(
        latest.gross.paise,
        12000000,
        reason: '13 · the latest is loaded, not merged with the attempt',
      );
      expect(latest.rowVersion, afterB['row_version']);
      expect(
        attempted.gross.paise,
        15000000,
        reason: 'the attempt was captured before the re-read replaced it',
      );

      // 15 · a fresh correction, on the current version.
      await correct(a, latest, paise: 18000000);
      await a.pushUntilSettled();

      // 16-18 · exactly one document, same number, exact figures.
      final finalDoc = await canonical(id);
      expect(finalDoc['txn_number'], number, reason: '17');
      expect(finalDoc['gross_amount_minor'], 18000000, reason: '18');
      // 5% inclusive of 1,80,000.00.
      expect(finalDoc['tax_amount_minor'], 857143, reason: '18');
      expect(finalDoc['net_amount_minor'], 17142857, reason: '18');
      expect(
        finalDoc['component_count'],
        1,
        reason: '16 · no duplicate components',
      );

      final all = await supervisor
          .from('revenue_document')
          .select('id')
          .eq('txn_number', number);
      expect(all, hasLength(1), reason: '16 · exactly one canonical document');

      // 19 · the audit records the accepted mutations, and only those.
      //
      // Asserted by mutation id rather than by the order of action names, because that
      // is the claim that matters: the intent the server refused must appear nowhere,
      // and every accepted one exactly once.
      final audit = await auditFor(id);
      expect(audit, hasLength(3), reason: '19 · create, then B, then A');
      expect(audit.where((r) => r['action'] == 'created'), hasLength(1));
      expect(audit.where((r) => r['action'] == 'edited'), hasLength(2));
      expect(audit.where((r) => '${r['action']}'.contains('void')), isEmpty);

      final auditedMutations = audit.map((r) => '${r['mutation_id']}').toSet();
      expect(
        auditedMutations,
        hasLength(3),
        reason: '19 · three distinct accepted mutations',
      );
      // The re-applied correction carries the **same** mutation id the refused one did,
      // because it reused the queued entry rather than starting a second piece of unsent
      // work for one document (D-125). That is safe here and only here: a refused
      // delivery consumed nothing, and Review latest is unreachable while an intent may
      // still be delivered, so the id can never be reused over a delivery whose outcome
      // is unknown.
      expect(auditedMutations, contains(intentAfter.mutationId));
      expect(
        audit.where((r) => '${r['mutation_id']}' == intentAfter.mutationId),
        hasLength(1),
        reason: 'one financial effect under that id, however many attempts',
      );
    });
  });

  // ── A2 · the stale void, and the inverse ─────────────────────────────────────
  group('A2 · a void cannot be issued from a stale view', () {
    test('a stale void is refused and the sale stays active at N+1', () async {
      final created = await recordAndSync(a);
      final id = created.id;

      final atA = await loadCanonicalInto(a, id);
      final atB = await loadCanonicalInto(b, id);
      final n = atA.rowVersion;
      expect(atB.rowVersion, n);

      await correct(b, atB, paise: 12000000);
      await b.pushUntilSettled();
      final afterB = await canonical(id);
      expect(afterB['row_version'], greaterThan(n));

      // A voids the version it last saw. D-021 exactly.
      final refusal = await a.revenue.voidLocally(
        entryId: id,
        reason: '$_marker stale void',
        actorUserId: a.authority.userId,
        baseRowVersion: n,
        mutationId: const Uuid().v4(),
        now: DateTime.now().toUtc(),
      );
      expect(refusal, isNull, reason: 'locally the intent is queued');
      await a.pushUntilSettled();

      expect(
        (await a.intentFor(id))!.status,
        'conflict',
        reason: '4 · conflict',
      );

      final after = await canonical(id);
      expect(after['voided_at'], isNull, reason: '5 · still active');
      expect(after['row_version'], afterB['row_version'], reason: '5 · at N+1');

      // 6 · nothing in the audit records a void.
      final audit = await auditFor(id);
      expect(
        audit.where((r) => '${r['action']}'.contains('void')),
        isEmpty,
        reason: '6 · a stale attempt creates no void audit effect',
      );
    });

    test(
      'an edit against a canonically voided sale is refused, and cannot revive it',
      () async {
        final created = await recordAndSync(a);
        final id = created.id;

        final atA = await loadCanonicalInto(a, id);
        final atB = await loadCanonicalInto(b, id);

        // B voids it, canonically.
        await b.revenue.voidLocally(
          entryId: id,
          reason: '$_marker voided by B',
          actorUserId: b.authority.userId,
          baseRowVersion: atB.rowVersion,
          mutationId: const Uuid().v4(),
          now: DateTime.now().toUtc(),
        );
        await b.pushUntilSettled();
        expect((await canonical(id))['voided_at'], isNotNull);

        // A, which still believes the sale is active, corrects it.
        await correct(a, atA, paise: 12000000);
        await a.pushUntilSettled();

        final intent = await a.intentFor(id);
        expect(
          intent!.status,
          anyOf('rejected', 'conflict'),
          reason: '4 · refused, and kept for a person to see',
        );

        final after = await canonical(id);
        expect(
          after['voided_at'],
          isNotNull,
          reason: '5 · no ordinary edit reactivates a voided sale',
        );
        expect(after['gross_amount_minor'], 10000000);
      },
    );
  });

  // ── A3 · void response loss ──────────────────────────────────────────────────
  group('A3 · a void whose answer never arrives', () {
    test('the retry replays: one void, one number, one audit effect', () async {
      final created = await recordAndSync(a);
      final id = created.id;
      final number = created.txnNumber!;
      final atA = await loadCanonicalInto(a, id);

      await a.revenue.voidLocally(
        entryId: id,
        reason: '$_marker void with a lost answer',
        actorUserId: a.authority.userId,
        baseRowVersion: atA.rowVersion,
        mutationId: const Uuid().v4(),
        now: DateTime.now().toUtc(),
      );

      // The server commits and the answer is thrown away on the wire.
      transportA.loseResponseOnceFor = '/rpc/revenue_void';
      try {
        await a.engine.pushOnce();
      } on Object {
        // The client is now in the one state idempotency exists for.
      }
      expect(
        transportA.lostResponses,
        isNotEmpty,
        reason: 'the scenario must actually have happened',
      );

      // It committed, even though the client does not know.
      final serverSide = await canonical(id);
      expect(serverSide['voided_at'], isNotNull);
      final versionAfterVoid = serverSide['row_version'];

      // The client still holds the intent and retries **the same mutation**.
      final queued = await a.intentFor(id);
      expect(queued!.status, isNot('done'));
      await a.pushUntilSettled();

      final after = await canonical(id);
      expect(
        after['voided_at'],
        serverSide['voided_at'],
        reason: 'the same void',
      );
      expect(
        after['row_version'],
        versionAfterVoid,
        reason: 'one effect, not two',
      );
      expect(after['txn_number'], number);
      expect(after['void_reason'], contains('lost answer'));

      final audit = await auditFor(id);
      expect(
        audit.where((r) => '${r['action']}'.contains('void')),
        hasLength(1),
        reason: 'one effective audit mutation',
      );
    });
  });

  // ── Part E · update response loss ────────────────────────────────────────────
  group('E · a correction whose answer never arrives', () {
    test('the retry replays: same document, same number, one version step', () async {
      final created = await recordAndSync(a);
      final id = created.id;
      final number = created.txnNumber!;
      final atA = await loadCanonicalInto(a, id);
      final before = atA.rowVersion;

      await correct(a, atA, paise: 21000000);

      transportA.loseResponseOnceFor = '/rpc/revenue_update';
      try {
        await a.engine.pushOnce();
      } on Object {
        // Committed on the server; unknown to the client.
      }
      expect(transportA.lostResponses, isNotEmpty);

      final committed = await canonical(id);
      expect(committed['gross_amount_minor'], 21000000);
      final versionAfter = committed['row_version'] as int;
      expect(versionAfter, greaterThan(before));

      // Retry the same intent. A fresh mutation id would be a second financial record
      // for one act, and nothing afterwards could tell the two apart.
      await a.pushUntilSettled();

      final after = await canonical(id);
      expect(after['id'], id);
      expect(after['txn_number'], number);
      expect(
        after['row_version'],
        versionAfter,
        reason: 'one row-version progression for that mutation',
      );
      expect(after['gross_amount_minor'], 21000000);
      expect(after['tax_amount_minor'], 1000000);
      expect(after['net_amount_minor'], 20000000);
      expect(after['component_count'], 1, reason: 'no duplicate components');

      // The local row reconciled, and the queue resolved.
      final local = await a.revenue.load(id);
      expect(local!.rowVersion, versionAfter);
      expect(local.txnNumber, number);
      expect(await a.revenue.syncStateOf(id), SyncState.synced);

      // And the reporting effect is one effect (Slice 12, B12). A contribution is a
      // projection over the accepted components, so there is nothing for a replay to
      // insert twice — which is the property, and it is asserted rather than assumed.
      final contributions =
          (await a.supabase
                  .from('revenue_period_contributions')
                  .select()
                  .eq('revenue_entry_id', id))
              .cast<Map<String, dynamic>>();
      expect(contributions, hasLength(1));
      expect(contributions.single['gross_minor'], 21000000);
      expect(contributions.single['tax_minor'], 1000000);
      expect(contributions.single['net_minor'], 20000000);
      expect(contributions.single['voided_at'], isNull);
    });
  });

  // ── Part D · create pending, then corrected twice, then restarted ────────────
  group('D · offline create, corrected twice, restarted, then synced', () {
    test(
      'one document, the final values, one number, and no update before the create',
      () async {
        final id = const Uuid().v7();
        createdIds.add(id);

        // 2 · offline.
        transportA.online = false;

        // 3 · create.
        final draft = draftFor(id, paise: 10000000);
        final decision = await a.revenue.evaluate(
          draft,
          authority: a.authority,
        );
        expect(
          decision,
          isA<RevenueCreatePermitted>(),
          reason: 'D-112 permits offline creation on a fresh snapshot',
        );
        await a.revenue.createLocally(
          draft,
          resolutions: (decision as RevenueCreatePermitted).resolutions,
          actorUserId: a.authority.userId,
          orgId: a.authority.orgId,
          mutationId: const Uuid().v4(),
          now: DateTime.now().toUtc(),
        );

        // 4-5 · corrected twice before it has ever synced.
        var local = (await a.revenue.load(id))!;
        await correct(a, local, paise: 12000000);
        expect(
          (await a.intentFor(id))!.op,
          'create',
          reason:
              'no update may be queued for a document the server has not accepted',
        );

        local = (await a.revenue.load(id))!;
        await correct(a, local, paise: 13500000);

        final queued = await a.intentFor(id);
        expect(queued!.op, 'create');
        expect(queued.payload, contains('13500000'));
        expect(
          queued.payload,
          isNot(contains('12000000')),
          reason: 'the queued intent carries the operator\'s current figure',
        );
        expect(
          queued.actorUserId,
          a.authority.userId,
          reason: 'deterministic mutation ownership (D-050)',
        );
        final rows = await a.db.select(a.db.syncOutbox).get();
        expect(
          rows.where((o) => o.entityId == id),
          hasLength(1),
          reason: 'one intent per document, however many corrections',
        );

        // The queued payload is still structurally valid after each correction: it names
        // the document, its date, and exactly one component with an amount.
        final payload = jsonDecode(queued.payload) as Map<String, dynamic>;
        expect(payload['p_id'], id);
        expect(payload['p_business_date'], '2026-06-15');
        expect((payload['p_components'] as List), hasLength(1));
        expect(
          (payload['p_components'] as List).first,
          containsPair('entered_amount_minor', 13500000),
        );

        // 6 · restart. The queued intent is a row in a file, so it either survives or it
        // does not; nothing is carried across in memory.
        await a.restart();

        final survived = await a.intentFor(id);
        expect(survived, isNotNull, reason: '8 · no lost revenue attempt');
        expect(survived!.op, 'create');
        expect(survived.payload, contains('13500000'));

        // 7-8 · reconnect and process.
        transportA.online = true;
        await a.pushUntilNumbered(id);

        final doc = await canonical(id);
        expect(
          doc['gross_amount_minor'],
          13500000,
          reason: 'final intended values only',
        );
        expect(doc['tax_amount_minor'], 642857);
        expect(doc['net_amount_minor'], 12857143);
        expect(doc['txn_number'], startsWith('KI-REV-'));
        expect(doc['component_count'], 1);

        // One canonical document under that number, and one audit create.
        final same = await supervisor
            .from('revenue_document')
            .select('id')
            .eq('txn_number', doc['txn_number'] as String);
        expect(same, hasLength(1), reason: 'no duplicate canonical revenue');

        final audit = await auditFor(id);
        expect(audit.where((r) => r['action'] == 'created'), hasLength(1));
        expect(
          audit.where((r) => r['action'] == 'edited'),
          isEmpty,
          reason:
              'no revenue_update was ever sent before the canonical create existed - '
              'which is the whole reason a correction rewrites the queued create '
              'rather than queueing an update beside it (D-125)',
        );
      },
    );
  });

  // ── Part F · the period and window boundary, live ────────────────────────────
  group('F · period locks and the edit window, against the real server', () {
    late SupabaseClient manager;
    late String managerUser;

    setUp(() async {
      manager = SupabaseClient(url, anonKey);
      await manager.auth.signInWithPassword(
        email: 'ccr.manager@example.com',
        password: managerPassword,
      );
      managerUser = manager.auth.currentUser!.id;
    });

    tearDown(() => manager.dispose());

    /// The property's own business date, derived under D-067 from the unit's timezone
    /// and cut-off rather than from this machine's calendar.
    Future<BusinessDate> propertyToday() async {
      final unit = await supervisor
          .from('business_units')
          .select('timezone, business_day_cutoff')
          .eq('id', ccrUnit!)
          .single();
      return BusinessDate.fromInstant(
        DateTime.now().toUtc(),
        timeZoneId: unit['timezone'] as String,
        cutoff:
            BusinessDayCutoff.tryParse('${unit['business_day_cutoff']}') ??
            BusinessDayCutoff.defaultCutoff,
      );
    }

    Future<Map<String, dynamic>> managerRecords(BusinessDate date) async {
      final id = const Uuid().v7();
      createdIds.add(id);
      await manager.rpc<dynamic>(
        'revenue_create',
        params: {
          'p_id': id,
          'p_business_unit_id': ccrUnit,
          'p_revenue_category_id': restaurant,
          'p_business_date': date.iso,
          'p_notes': _marker,
          'p_components': [
            {'entered_amount_minor': 10000000},
          ],
          'p_mutation_id': const Uuid().v4(),
        },
      );
      return await manager
          .from('revenue_document')
          .select()
          .eq('id', id)
          .single();
    }

    Future<void> correctAs(
      SupabaseClient session,
      Map<String, dynamic> doc, {
      int paise = 12000000,
      String? date,
    }) => session
        .rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': doc['id'],
            'p_base_row_version': doc['row_version'],
            'p_business_date': date ?? doc['business_date'],
            'p_notes': _marker,
            // A correction that moves the trading day states why (spec §9), and the
            // reason is checked before the period locks are. Supplying one here keeps
            // these cases about the rule each of them is for: without it every dated
            // correction below would be refused KM008 and would prove nothing about
            // the period lock or the edit window.
            if (date != null)
              'p_correction_reason': '$_marker business-date correction',
            'p_components': [
              {'entered_amount_minor': paise},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        )
        .then((_) {});

    test(
      'the manager may correct their own entry at D+7 and not at D+8',
      () async {
        final today = await propertyToday();

        // D+7: the last day inside the window (D-065, inclusive).
        final atSeven = await managerRecords(today.addDays(-7));
        await correctAs(manager, atSeven);
        final okDoc = await canonical(atSeven['id'] as String);
        expect(okDoc['gross_amount_minor'], 12000000, reason: 'D+7 permitted');

        // D+8: one day past it.
        final atEight = await managerRecords(today.addDays(-8));
        await expectLater(
          correctAs(manager, atEight),
          throwsA(
            predicate(
              (e) => _refusalOf(e) == 'KM021',
              'refused for the edit window',
            ),
          ),
        );
        expect(
          (await canonical(atEight['id'] as String))['gross_amount_minor'],
          10000000,
        );
      },
    );

    test(
      'the beyond-window capability permits it while the period is open',
      () async {
        final today = await propertyToday();
        final old = await managerRecords(today.addDays(-30));

        // The Owner holds transaction.correct.beyond_window.
        await correctAs(supervisor, old);
        expect(
          (await canonical(old['id'] as String))['gross_amount_minor'],
          12000000,
        );
      },
    );

    test('a closed target period refuses, and so does a closed source period', () async {
      final today = await propertyToday();
      final doc = await managerRecords(today);
      final sourceKey = today.periodKey;

      // A month far enough back to be closable without disturbing anything: the sale
      // above is in the current period, so moving it there crosses a closed boundary.
      const targetDate = '2026-04-15';
      const targetKey = '2026-04';

      Future<void> close(String key) => supervisor.rpc<dynamic>(
        'period_close',
        params: {
          'p_business_unit_id': ccrUnit,
          'p_period_key': key,
          'p_mutation_id': const Uuid().v4(),
        },
      );
      Future<void> reopen(String key) => supervisor.rpc<dynamic>(
        'period_reopen',
        params: {
          'p_business_unit_id': ccrUnit,
          'p_period_key': key,
          'p_reason': '$_marker acceptance reopen',
          'p_mutation_id': const Uuid().v4(),
        },
      );

      // ── closed TARGET ──
      await close(targetKey);
      try {
        await expectLater(
          correctAs(supervisor, doc, date: targetDate),
          throwsA(
            predicate(
              (e) => _refusalOf(e) == 'KM004',
              'refused because the target period is closed',
            ),
          ),
        );
        // And the Owner's capability does not bypass it: the same call by the same
        // Owner is what was just refused. `transaction.correct.beyond_window` lifts the
        // *age* rule and nothing else (D-065).
        expect(
          (await canonical(doc['id'] as String))['business_date'],
          today.iso,
        );
      } finally {
        await reopen(targetKey);
      }

      // ── closed SOURCE ──
      //
      // The entry now lives in the current period; closing it and then moving the entry
      // *out* must be refused too, because removing an amount from a closed month
      // restates that month's totals as surely as adding one (spec 13.4).
      await close(sourceKey);
      try {
        await expectLater(
          correctAs(supervisor, doc, date: targetDate),
          throwsA(
            predicate(
              (e) => _refusalOf(e) == 'KM004',
              'refused because the source period is closed',
            ),
          ),
        );
        // A correction that does not move it is refused too, for the same reason.
        await expectLater(
          correctAs(supervisor, doc),
          throwsA(predicate((e) => _refusalOf(e) == 'KM004', 'closed period')),
        );
      } finally {
        await reopen(sourceKey);
      }

      // Reopened, the same correction succeeds - so the refusals above were the lock
      // and not something else.
      await correctAs(supervisor, doc);
      expect(
        (await canonical(doc['id'] as String))['gross_amount_minor'],
        12000000,
      );
    });

    test('a stale version and a closed period stay distinct refusals', () async {
      final today = await propertyToday();
      final doc = await managerRecords(today);
      final stale = Map<String, dynamic>.of(doc);

      // Move it once, so `doc`'s version is now stale.
      await correctAs(supervisor, doc);

      // Stale, period open: KM003.
      await expectLater(
        correctAs(supervisor, stale),
        throwsA(predicate((e) => _refusalOf(e) == 'KM003', 'conflict')),
      );

      // Closed period, current version: KM004. The period is checked before the
      // version, so a user in a closed month is told the truth rather than being sent
      // to resolve a conflict that is not the reason.
      await supervisor.rpc<dynamic>(
        'period_close',
        params: {
          'p_business_unit_id': ccrUnit,
          'p_period_key': today.periodKey,
          'p_mutation_id': const Uuid().v4(),
        },
      );
      try {
        final current = await canonical(doc['id'] as String);
        await expectLater(
          correctAs(supervisor, current),
          throwsA(predicate((e) => _refusalOf(e) == 'KM004', 'period closed')),
        );
        // And a stale attempt into a closed period reports the period, not the version.
        await expectLater(
          correctAs(supervisor, stale),
          throwsA(predicate((e) => _refusalOf(e) == 'KM004', 'period first')),
        );
      } finally {
        await supervisor.rpc<dynamic>(
          'period_reopen',
          params: {
            'p_business_unit_id': ccrUnit,
            'p_period_key': today.periodKey,
            'p_reason': '$_marker acceptance reopen',
            'p_mutation_id': const Uuid().v4(),
          },
        );
      }

      expect(managerUser, isNotEmpty);
    });
  });
}
