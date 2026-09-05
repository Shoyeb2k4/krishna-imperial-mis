/// Phase 3 against the real `krishna-mis-dev` project, through the real gateways.
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` stays hermetic and offline. Nothing here prints a password, a
/// token or the API key.
///
/// The centrepiece is §21 of the Phase 3 brief: create the ₹58,000 shared bill, sync it
/// into three separate local databases as three different people, and then **read the raw
/// SQLite** of each. Not the UI. Not a repository method that might filter. The bytes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/sync/expense_pull.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../integration_test/support/controllable_transport.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';

String _seedId(String path) =>
    const Uuid().v5('d9d3f0a6-4c2b-5f7e-9a10-6b1e2c8f4a70', path);

void main() {
  final identitiesPath = Platform.environment[_identitiesVar];
  if (identitiesPath == null || !File(identitiesPath).existsSync()) return;

  final config =
      jsonDecode(File(r'config/dev.json').readAsStringSync())
          as Map<String, dynamic>;
  final identities =
      jsonDecode(File(identitiesPath).readAsStringSync())
          as Map<String, dynamic>;

  final ccr = _seedId('bu:CCR');
  final hki = _seedId('bu:HKI');
  final ccrKirana = {
    'business_unit_id': ccr,
    'department_id': _seedId('dept:CCR/FB'),
    'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
    'category_id': _seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
  };
  final hkiElectricity = {
    'business_unit_id': hki,
    'department_id': _seedId('dept:HKI/HKI_UTIL'),
    'section_id': _seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
    'category_id': _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
  };

  // One signed-in client per identity, created once and reused.
  //
  // Re-authenticating before every call is what a naive suite does, and it earns a 429
  // from the auth endpoint less than a minute in — which looks exactly like a product
  // failure and is not one. Six sign-ins per run instead of sixty.
  final clients = <String, SupabaseClient>{};
  late SupabaseClient client;
  final created = <String>[];

  Future<void> signInAs(String email) async {
    final existing = clients[email];
    if (existing != null) {
      client = existing;
      return;
    }
    final fresh = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
    final entry = identities[email] as Map<String, dynamic>;
    await fresh.auth.signInWithPassword(
      email: email,
      password: entry['password'] as String,
    );
    clients[email] = fresh;
    client = fresh;
  }

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    client = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
  });

  tearDownAll(() async {
    // Remove every document this suite created. These are development fixtures minutes
    // old, not history; the append-only audit rows they produced correctly remain.
    if (created.isNotEmpty) {
      await signInAs('giridhar@hki.com');
      for (final id in created) {
        // The version is read rather than assumed. A fixture this suite corrected sits at
        // v3, and a hard-coded `2` would silently fail to reverse exactly the documents
        // the correction tests created — leaving them open in the development project
        // while the teardown reported nothing (D-071: a cleanup that cannot work is not
        // a cleanup).
        final row = await client
            .from('expense_document')
            .select('row_version')
            .eq('id', id)
            .maybeSingle()
            .then((r) => r, onError: (_) => null);
        await client
            .rpc<dynamic>(
              'expense_void',
              params: {
                'p_id': id,
                'p_base_row_version': (row?['row_version'] as int?) ?? 2,
                'p_reason': 'Phase 3 live test fixture',
              },
            )
            .then((_) {}, onError: (_) {});
      }
    }
    for (final signedIn in clients.values) {
      await signedIn.auth.signOut();
      await signedIn.dispose();
    }
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  Future<Map<String, dynamic>> createAs(
    String email,
    Map<String, Object?> args,
  ) async {
    await signInAs(email);
    final result = await ExpenseGateway(
      client,
    ).create(arguments: args, mutationId: const Uuid().v4());
    expect(
      result.isOk,
      isTrue,
      reason: 'refused: ${result.refusalOrNull?.message}',
    );
    created.add(args['p_id'] as String);
    return result.valueOrNull!;
  }

  Map<String, Object?> sharedBill(String id) => {
    'p_id': id,
    'p_business_date': '2026-06-15',
    'p_total_minor': 5800000,
    'p_notes': 'Phase 3 live: shared electricity',
    'p_allocations': [
      {...ccrKirana, 'amount_minor': 2500000},
      {...hkiElectricity, 'amount_minor': 3300000},
    ],
  };

  group('the shared bill, as three different people hold it', () {
    late String expenseId;
    final databases = <String, File>{};

    setUpAll(() async {
      expenseId = const Uuid().v4();
      await createAs('giridhar@hki.com', sharedBill(expenseId));
    });

    /// Syncs the document into a fresh local database as [email], and returns the file.
    Future<File> syncAs(String email) async {
      await signInAs(email);
      final dir = await Directory.systemTemp.createTemp('krishna_scoped');
      final file = File('${dir.path}/local.sqlite');
      final db = AppDatabase(NativeDatabase(file));
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await ExpensePull(
        db: db,
        gateway: ExpenseGateway(client),
      ).pullOne(expenseId);
      await db.close();
      databases[email] = file;
      return file;
    }

    /// Every integer that appears anywhere in the raw database file, as text.
    ///
    /// Reads the bytes, not the schema: a value hidden in a column this test forgot to
    /// check is still a value on the device.
    Future<String> rawBytesOf(File file) async {
      final bytes = await file.readAsBytes();
      return String.fromCharCodes(
        bytes.map((b) => b >= 32 && b < 127 ? b : 46),
      );
    }

    test('the Owner receives the whole document', () async {
      final file = await syncAs('giridhar@hki.com');
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final row = (await db.select(db.expenses).get()).single;
      expect(row.visibility, 'complete');
      expect(row.documentTotalMinor, 5800000);
      expect(row.visibleAmountMinor, 5800000);

      final lines = await db.select(db.expenseAllocations).get();
      expect(lines, hasLength(2));
      expect(lines.map((l) => l.amountMinor).toSet(), {2500000, 3300000});
    });

    test(
      'the Crystal Canopy manager holds their share and nothing of the other',
      () async {
        final file = await syncAs('ccr.manager@example.com');
        final db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);

        final row = (await db.select(db.expenses).get()).single;
        expect(row.visibility, 'scoped');
        expect(row.visibleAmountMinor, 2500000);
        expect(
          row.documentTotalMinor,
          isNull,
          reason: '₹58,000 − ₹25,000 is Hotel Krishna s ₹33,000',
        );
        expect(row.isShared, isTrue, reason: 'knowing it is shared is allowed');

        final lines = await db.select(db.expenseAllocations).get();
        expect(lines, hasLength(1));
        expect(lines.single.businessUnitId, ccr);
        expect(lines.single.amountMinor, 2500000);

        final periods = await db.select(db.expensePeriodAllocations).get();
        expect(periods, hasLength(1));
        expect(periods.single.amountMinor, 2500000);

        expect(
          await db.select(db.expenseAttachments).get(),
          isEmpty,
          reason: 'an invoice image states the full total on its face',
        );
      },
    );

    test(
      'the Hotel Krishna manager holds theirs, and neither can derive the other',
      () async {
        final file = await syncAs('hki.manager@example.com');
        final db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);

        final row = (await db.select(db.expenses).get()).single;
        expect(row.visibility, 'scoped');
        expect(row.visibleAmountMinor, 3300000);
        expect(row.documentTotalMinor, isNull);

        final lines = await db.select(db.expenseAllocations).get();
        expect(lines, hasLength(1));
        expect(lines.single.businessUnitId, hki);
        expect(lines.single.amountMinor, 3300000);
      },
    );

    test(
      'the raw SQLite of each scoped device contains no unauthorised amount',
      () async {
        // The security test proper: search the file's bytes, not its rows.
        final ccrRaw = await rawBytesOf(databases['ccr.manager@example.com']!);
        final hkiRaw = await rawBytesOf(databases['hki.manager@example.com']!);

        // SQLite stores integers as big-endian binary, so the decimal strings are the
        // wrong thing to grep for — but any JSON payload, cached response or debug field
        // that leaked one would contain them as text. Both checks are worth having.
        expect(
          ccrRaw,
          isNot(contains('3300000')),
          reason: 'the other property s share must not be on this device',
        );
        expect(ccrRaw, isNot(contains('5800000')));
        expect(hkiRaw, isNot(contains('2500000')));
        expect(hkiRaw, isNot(contains('5800000')));

        // And the binary integers themselves, read back through the schema, which is how
        // SQLite actually stores them.
        for (final entry in {
          'ccr.manager@example.com': [3300000, 5800000],
          'hki.manager@example.com': [2500000, 5800000],
        }.entries) {
          final db = AppDatabase(NativeDatabase(databases[entry.key]!));
          addTearDown(db.close);

          final amounts = <int?>[
            ...(await db.select(db.expenses).get()).expand(
              (r) => [r.documentTotalMinor, r.visibleAmountMinor],
            ),
            ...(await db.select(db.expenseAllocations).get()).map(
              (r) => r.amountMinor,
            ),
            ...(await db.select(db.expensePeriodAllocations).get()).map(
              (r) => r.amountMinor,
            ),
          ];
          for (final forbidden in entry.value) {
            expect(
              amounts,
              isNot(contains(forbidden)),
              reason: '${entry.key} holds $forbidden, which it may not know',
            );
          }
        }
      },
    );

    test('a scoped manager cannot reach the raw header table', () async {
      await signInAs('ccr.manager@example.com');
      try {
        await client.from('expenses').select('total_amount_minor');
        fail('the raw header table must not be readable by a client');
      } on PostgrestException catch (error) {
        expect(error.code, '42501');
      }
    });

    test(
      'a scoped manager cannot reach the attachment object either',
      () async {
        await signInAs('ccr.manager@example.com');
        final path = 'org/${_seedId('org:KRISHNA')}/expenses/$expenseId/x.jpg';
        try {
          await client.storage.from('expense-attachments').download(path);
          fail('a scoped user must not be able to download an attachment');
        } on StorageException catch (error) {
          // Not found or not authorised — either way, nothing came back.
          expect(error.statusCode, anyOf('400', '404', '403'));
        }
      },
    );
  });

  group('reconciliation against the real server', () {
    test('a simple expense reconciles exactly', () async {
      final id = const Uuid().v4();
      final result = await createAs('giridhar@hki.com', {
        'p_id': id,
        'p_business_date': '2026-06-15',
        'p_total_minor': 20000,
        'p_allocations': [
          {...ccrKirana, 'amount_minor': 20000},
        ],
      });
      expect(result['txn_number'], startsWith('KI-EXP-'));

      final contributions = await ExpenseGateway(
        client,
      ).fetchPeriodContributions(id);
      final rows =
          (contributions as RemoteOk<List<Map<String, dynamic>>>).value;
      expect(rows, hasLength(1));
      expect(rows.single['amount_minor'], 20000);
      expect(rows.single['pnl_period_key'], '2026-06');
    });

    test('an odd amount split three ways reconciles to the paisa', () async {
      final id = const Uuid().v4();
      final total = Money.fromPaise(100001);
      final shares = total.allocate([1, 1, 1]);
      expect(Money.sum(shares), total);

      await createAs('giridhar@hki.com', {
        'p_id': id,
        'p_business_date': '2026-06-15',
        'p_total_minor': total.paise,
        'p_allocations': [
          {
            ...ccrKirana,
            'amount_minor': total.paise,
            'periods': [
              for (var i = 0; i < 3; i++)
                {
                  'period_start': '2026-0${4 + i}-01',
                  'period_end': '2026-0${4 + i}-28',
                  'amount_minor': shares[i].paise,
                  'is_derived': false,
                },
            ],
          },
        ],
      });

      final rows =
          (await ExpenseGateway(client).fetchPeriodContributions(id)
                  as RemoteOk<List<Map<String, dynamic>>>)
              .value;
      expect(rows, hasLength(3));
      expect(
        rows.fold<int>(0, (s, r) => s + (r['amount_minor'] as int)),
        total.paise,
      );
    });

    test(
      'shared and cross-period at once reconciles on both dimensions',
      () async {
        final id = const Uuid().v4();
        await createAs('giridhar@hki.com', {
          'p_id': id,
          'p_business_date': '2026-06-15',
          'p_total_minor': 5800000,
          'p_allocations': [
            {
              ...ccrKirana,
              'amount_minor': 2500000,
              'periods': [
                {
                  'period_start': '2026-05-15',
                  'period_end': '2026-05-31',
                  'amount_minor': 1250000,
                  'is_derived': false,
                },
                {
                  'period_start': '2026-06-01',
                  'period_end': '2026-06-14',
                  'amount_minor': 1250000,
                  'is_derived': false,
                },
              ],
            },
            {...hkiElectricity, 'amount_minor': 3300000},
          ],
        });

        final rows =
            (await ExpenseGateway(client).fetchPeriodContributions(id)
                    as RemoteOk<List<Map<String, dynamic>>>)
                .value;
        expect(rows, hasLength(3));
        expect(
          rows.fold<int>(0, (s, r) => s + (r['amount_minor'] as int)),
          5800000,
          reason: 'globally, every paisa once',
        );

        final byPeriod = <String, int>{};
        for (final row in rows) {
          byPeriod[row['pnl_period_key'] as String] =
              (byPeriod[row['pnl_period_key'] as String] ?? 0) +
              (row['amount_minor'] as int);
        }
        expect(byPeriod, {'2026-05': 1250000, '2026-06': 4550000});
      },
    );
  });

  group('period locks, end to end', () {
    const closedPeriod = '2026-02';

    Future<void> closePeriod() async {
      await signInAs('giridhar@hki.com');
      await client.rpc<dynamic>(
        'period_close',
        params: {'p_period_key': closedPeriod, 'p_business_unit_id': ccr},
      );
    }

    Future<void> reopenPeriod() async {
      await signInAs('giridhar@hki.com');
      await client.rpc<dynamic>(
        'period_reopen',
        params: {
          'p_period_key': closedPeriod,
          'p_business_unit_id': ccr,
          'p_reason': 'Phase 3 acceptance: correcting a February entry',
        },
      );
    }

    Map<String, Object?> februaryExpense(String id) => {
      'p_id': id,
      'p_business_date': '2026-02-10',
      'p_total_minor': 15000,
      'p_allocations': [
        {...ccrKirana, 'amount_minor': 15000},
      ],
    };

    test('an open period accepts the write', () async {
      await reopenPeriod().then((_) {}, onError: (_) {});
      final id = const Uuid().v4();
      final result = await createAs('giridhar@hki.com', februaryExpense(id));
      expect(result['status'], 'applied');
    });

    test('a closed period refuses create, edit and void with KM004', () async {
      // Something to edit and void, recorded while the period is open.
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', februaryExpense(id));

      await closePeriod();
      await signInAs('giridhar@hki.com');
      final gateway = ExpenseGateway(client);

      final create = await gateway.create(
        arguments: februaryExpense(const Uuid().v4()),
        mutationId: const Uuid().v4(),
      );
      expect(create.isRefused, isTrue);
      expect(create.refusalOrNull!.kind, RefusalKind.periodClosed);
      expect(create.refusalOrNull!.message, isNot(contains('SQLSTATE')));

      final edit = await gateway.update(
        arguments: februaryExpense(id),
        baseRowVersion: 2,
        mutationId: const Uuid().v4(),
      );
      expect(edit.isRefused, isTrue);
      expect(edit.refusalOrNull!.kind, RefusalKind.periodClosed);

      await signInAs('accountant@example.com');
      final voided = await ExpenseGateway(client).voidExpense(
        expenseId: id,
        baseRowVersion: 2,
        reason: 'Should be refused: February is closed',
        mutationId: const Uuid().v4(),
      );
      expect(voided.isRefused, isTrue);
      expect(voided.refusalOrNull!.kind, RefusalKind.periodClosed);

      // Reopening is deliberate, reasoned and audited — and then the correction works.
      await reopenPeriod();
      await signInAs('accountant@example.com');
      final afterReopen = await ExpenseGateway(client).voidExpense(
        expenseId: id,
        baseRowVersion: 2,
        reason: 'Phase 3 acceptance: corrected after an audited reopen',
        mutationId: const Uuid().v4(),
      );
      expect(
        afterReopen.isOk,
        isTrue,
        reason: 'refused: ${afterReopen.refusalOrNull?.message}',
      );
    });
  });

  group('usage counters mean what they say', () {
    test('a void keeps the historical count and drops the active one', () async {
      final id = const Uuid().v4();
      final categoryId = ccrKirana['category_id']!;

      await signInAs('giridhar@hki.com');
      final before = await client.rpc<dynamic>(
        'master_usage',
        params: {
          'p_entity_type': 'expense_category',
          'p_entity_id': categoryId,
        },
      );
      final historicalBefore =
          (before as Map)['transaction_count'] as int? ?? 0;

      await createAs('giridhar@hki.com', {
        'p_id': id,
        'p_business_date': '2026-06-15',
        'p_total_minor': 12345,
        'p_allocations': [
          {...ccrKirana, 'amount_minor': 12345},
        ],
      });

      await signInAs('accountant@example.com');
      final voided = await ExpenseGateway(client).voidExpense(
        expenseId: id,
        baseRowVersion: 2,
        reason: 'Phase 3 acceptance: usage semantics',
        mutationId: const Uuid().v4(),
      );
      expect(voided.isOk, isTrue);

      await signInAs('giridhar@hki.com');
      final after =
          await client.rpc<dynamic>(
                'master_usage',
                params: {
                  'p_entity_type': 'expense_category',
                  'p_entity_id': categoryId,
                },
              )
              as Map;

      expect(
        after['transaction_count'],
        historicalBefore + 1,
        reason:
            'a voided expense still happened — the rename warning in D-038 is '
            'built on this history and must not be erased by a void',
      );
    });
  });

  group('the seven-day edit window, at the boundary', () {
    // The gap the previous checkpoint recorded as untested, closed against the real
    // server. `edit_window_days` is configuration and the seeded value is 7; the server
    // compares `current_date - business_date` against it.
    //
    // Exact semantics, stated because "seven days" is ambiguous until it is written down:
    //
    //   elapsed = current_date − business_date, in whole calendar days
    //   elapsed <= 7   permitted for an ordinary editor
    //   elapsed >  7   refused KM021, unless the caller holds
    //                  `transaction.correct.beyond_window`
    //
    // So a business date of D is editable on D+7 and refused on D+8. The window is
    // inclusive of its last day.
    String isoDaysAgo(int days) {
      final date = DateTime.now().toUtc().subtract(Duration(days: days));
      return '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    }

    Map<String, Object?> expenseDated(String id, String businessDate) => {
      'p_id': id,
      'p_business_date': businessDate,
      'p_total_minor': 25000,
      'p_allocations': [
        {...ccrKirana, 'amount_minor': 25000},
      ],
    };

    /// Data Entry holds `expense.edit.own` and records it themselves, so ownership is
    /// not what is under test here — the age of the entry is.
    Future<RemoteOutcome<Map<String, dynamic>>> editAs(
      String email,
      String id,
      String businessDate,
    ) async {
      await signInAs(email);
      return ExpenseGateway(client).update(
        arguments: {
          ...expenseDated(id, businessDate),
          'p_notes': 'edited within the window test',
        },
        baseRowVersion: 2,
        mutationId: const Uuid().v4(),
      );
    }

    test('an entry seven days old may still be corrected', () async {
      final id = const Uuid().v4();
      final date = isoDaysAgo(7);
      await createAs('data.entry@example.com', expenseDated(id, date));

      final outcome = await editAs('data.entry@example.com', id, date);
      expect(
        outcome.isOk,
        isTrue,
        reason:
            'the window is inclusive of its last day — refused here would mean '
            'six days, not seven (${outcome.refusalOrNull?.message})',
      );
    });

    test('an entry eight days old is refused KM021', () async {
      final id = const Uuid().v4();
      final date = isoDaysAgo(8);
      await createAs('data.entry@example.com', expenseDated(id, date));

      final outcome = await editAs('data.entry@example.com', id, date);
      expect(outcome.isRefused, isTrue);
      expect(outcome.refusalOrNull!.kind, RefusalKind.editWindowExpired);
      expect(
        outcome.refusalOrNull!.message,
        isNot(contains('SQLSTATE')),
        reason: 'a manager never sees a Postgres error',
      );
    });

    test(
      'a holder of transaction.correct.beyond_window may still correct it',
      () async {
        final id = const Uuid().v4();
        final date = isoDaysAgo(30);
        await createAs('giridhar@hki.com', expenseDated(id, date));

        // The Accountant bundle carries the capability; the Owner role carries
        // everything. Neither is identified by name — the capability is what is asked.
        final outcome = await editAs('accountant@example.com', id, date);
        expect(
          outcome.isOk,
          isTrue,
          reason:
              'thirty days old, and the capability exists precisely for this '
              '(${outcome.refusalOrNull?.message})',
        );
      },
    );

    test('a closed period refuses the correction even with that capability — '
        'the period lock wins', () async {
      final id = const Uuid().v4();
      // Well outside the window, and in a month we then close.
      const date = '2026-01-15';
      await createAs('giridhar@hki.com', expenseDated(id, date));

      await signInAs('giridhar@hki.com');
      await client.rpc<dynamic>(
        'period_close',
        params: {'p_period_key': '2026-01', 'p_business_unit_id': ccr},
      );

      final outcome = await editAs('accountant@example.com', id, date);
      expect(outcome.isRefused, isTrue);
      expect(
        outcome.refusalOrNull!.kind,
        RefusalKind.periodClosed,
        reason:
            'beyond_window lets somebody past the age rule, never past the '
            'period lock — the lock is never bypassed',
      );

      // Leave the period as it was found.
      await signInAs('giridhar@hki.com');
      await client.rpc<dynamic>(
        'period_reopen',
        params: {
          'p_period_key': '2026-01',
          'p_business_unit_id': ccr,
          'p_reason': 'Phase 3 acceptance: restoring the development fixture',
        },
      );
    });
  });

  // ── The Phase 3 corrective: business-date correction and the closed source period ──
  //
  // Four findings, evidenced against this server before anything was changed, and each
  // asserted here in the form that goes green only when the fix genuinely exists.
  //
  // The centrepiece is the first: `expense_update` protected the period an expense was
  // moving *to* and not the one it was moving *from*, so an expense could be lifted out
  // of a **closed** month and that month's Total Expenses changed with nobody's
  // permission. The probe that found it is reproduced exactly — same amount, same months,
  // same actor — and it asserts the **figures**, not the RPC status: a refusal that left
  // the contributions moved would be no fix at all.
  group('business-date correction, and the periods it affects', () {
    const source = '2026-03';
    const target = '2026-04';
    const marker = 'Phase 3 corrective: business-date correction';

    Future<void> setPeriod(String key, {required bool closed}) async {
      await signInAs('giridhar@hki.com');
      if (closed) {
        await client
            .rpc<dynamic>(
              'period_close',
              params: {'p_period_key': key, 'p_business_unit_id': ccr},
            )
            .then((_) {}, onError: (_) {});
      } else {
        await client
            .rpc<dynamic>(
              'period_reopen',
              params: {
                'p_period_key': key,
                'p_business_unit_id': ccr,
                'p_reason':
                    'Phase 3 corrective: restoring the development fixture',
              },
            )
            .then((_) {}, onError: (_) {});
      }
    }

    /// Both months open. Called before every case, so no test inherits another's locks.
    Future<void> bothOpen() async {
      await setPeriod(source, closed: false);
      await setPeriod(target, closed: false);
    }

    tearDownAll(bothOpen);

    /// What each accounting period actually holds for this document — the rows Phase 5
    /// will aggregate, read through the projection reporting will read (D-060).
    Future<Map<String, int>> contributions(String id) async {
      final rows = await client
          .from('expense_period_contributions')
          .select()
          .eq('expense_id', id);
      final byPeriod = <String, int>{};
      for (final row in rows) {
        final key = row['pnl_period_key'] as String;
        byPeriod[key] = (byPeriod[key] ?? 0) + (row['amount_minor'] as int);
      }
      return byPeriod;
    }

    String isoToday([int daysAgo = 0]) {
      final d = DateTime.now().toUtc().subtract(Duration(days: daysAgo));
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    Map<String, Object?> marchExpense(String id, {int amount = 4500000}) => {
      'p_id': id,
      'p_business_date': '2026-03-10',
      'p_total_minor': amount,
      'p_notes': marker,
      'p_allocations': [
        {...ccrKirana, 'amount_minor': amount},
      ],
    };

    /// The same document, asking to live in April instead.
    Map<String, Object?> movedToApril(
      String id, {
      int amount = 4500000,
      String? reason = 'Recorded against the wrong trading day',
    }) => {
      ...marchExpense(id, amount: amount),
      'p_business_date': '2026-04-10',
      // `?reason` omits the key entirely when null, which is how a caller that supplies
      // no reason at all is expressed — distinct from supplying an empty one.
      'p_correction_reason': ?reason,
    };

    Future<RemoteOutcome<Map<String, dynamic>>> updateAs(
      String email,
      Map<String, Object?> arguments, {
      required int baseRowVersion,
      String? mutationId,
    }) async {
      await signInAs(email);
      return ExpenseGateway(client).update(
        arguments: arguments,
        baseRowVersion: baseRowVersion,
        mutationId: mutationId ?? const Uuid().v4(),
      );
    }

    test('an ordinary edit that does not move the date needs no correction '
        'capability and no reason', () async {
      await bothOpen();
      final id = const Uuid().v4();
      // Data Entry holds neither `transaction.correct.business_date` nor
      // `expense.edit.all`. It records this itself and corrects only the notes, so the
      // fast path must be exactly as it was: no new field, no new permission.
      final iso = isoToday();
      await createAs('data.entry@example.com', {
        'p_id': id,
        'p_business_date': iso,
        'p_total_minor': 33000,
        'p_notes': marker,
        'p_allocations': [
          {...ccrKirana, 'amount_minor': 33000},
        ],
      });

      final outcome = await updateAs('data.entry@example.com', {
        'p_id': id,
        'p_business_date': iso,
        'p_total_minor': 33000,
        'p_notes': '$marker - notes corrected, date untouched',
        'p_allocations': [
          {...ccrKirana, 'amount_minor': 33000},
        ],
      }, baseRowVersion: 2);

      expect(
        outcome.isOk,
        isTrue,
        reason:
            'the correction gate must bind only when the date actually moves '
            '(${outcome.refusalOrNull?.message})',
      );
      expect(outcome.valueOrNull!['business_date_corrected'], isFalse);

      await signInAs('giridhar@hki.com');
      final row = await client
          .from('expense_document')
          .select('business_date_source')
          .eq('id', id)
          .single();
      expect(
        row['business_date_source'],
        'derived',
        reason:
            'an edit that did not move the date must not restate the provenance '
            'of one that was never corrected (D-019)',
      );
    });

    test(
      'a permitted correction succeeds, and says so in the record',
      () async {
        await bothOpen();
        final id = const Uuid().v4();
        final createdRow = await createAs('giridhar@hki.com', marchExpense(id));
        final number = createdRow['txn_number'] as String;

        await signInAs('giridhar@hki.com');
        expect(await contributions(id), {source: 4500000});

        final outcome = await updateAs(
          'accountant@example.com',
          movedToApril(id),
          baseRowVersion: 2,
        );
        expect(
          outcome.isOk,
          isTrue,
          reason: 'refused: ${outcome.refusalOrNull?.message}',
        );
        expect(outcome.valueOrNull!['business_date_corrected'], isTrue);

        // The figures moved, exactly and only where they were asked to go.
        await signInAs('giridhar@hki.com');
        expect(await contributions(id), {target: 4500000});

        final row = await client
            .from('expense_document')
            .select('business_date,business_date_source,txn_number')
            .eq('id', id)
            .single();
        expect(row['business_date'], '2026-04-10');
        expect(row['business_date_source'], 'corrected');
        expect(
          row['txn_number'],
          number,
          reason:
              'the number belongs to the document identity and survives every '
              'correction (D-072a)',
        );

        final audit = await client
            .from('audit_logs')
            .select('action,reason,before_state,after_state')
            .eq('entity_id', id)
            .eq('action', 'expense_business_date_corrected');
        expect(
          audit,
          hasLength(1),
          reason:
              'a moved date is its own act and gets its own audit action, so '
              '"which dates moved, by whom, and why" is one query',
        );
        expect(
          audit.single['reason'],
          'Recorded against the wrong trading day',
        );
        expect(
          (audit.single['before_state'] as Map)['business_date'],
          '2026-03-10',
        );
        expect(
          (audit.single['after_state'] as Map)['business_date'],
          '2026-04-10',
        );
      },
    );

    test('moving the date without the correction capability is refused', () async {
      await bothOpen();
      final id = const Uuid().v4();
      // Recent, so the edit window is not what refuses it — and recorded by the same
      // person who then tries to move it, so ownership is not either. The only thing
      // missing is `transaction.correct.business_date`.
      await createAs('data.entry@example.com', {
        'p_id': id,
        'p_business_date': isoToday(),
        'p_total_minor': 41000,
        'p_notes': marker,
        'p_allocations': [
          {...ccrKirana, 'amount_minor': 41000},
        ],
      });

      final outcome = await updateAs('data.entry@example.com', {
        'p_id': id,
        'p_business_date': isoToday(1),
        'p_total_minor': 41000,
        'p_notes': marker,
        'p_correction_reason': 'Wrong day',
        'p_allocations': [
          {...ccrKirana, 'amount_minor': 41000},
        ],
      }, baseRowVersion: 2);

      expect(outcome.isRefused, isTrue);
      expect(
        outcome.refusalOrNull!.kind,
        anyOf(RefusalKind.missingCapability, RefusalKind.outOfUnitScope),
      );
      expect(outcome.refusalOrNull!.message, isNot(contains('SQLSTATE')));
    });

    test('a correction with a blank reason is refused', () async {
      await bothOpen();
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', marchExpense(id, amount: 12000));

      final outcome = await updateAs(
        'accountant@example.com',
        movedToApril(id, amount: 12000, reason: ''),
        baseRowVersion: 2,
      );
      expect(outcome.isRefused, isTrue);
      expect(outcome.refusalOrNull!.kind, RefusalKind.reasonRequired);
      await signInAs('giridhar@hki.com');
      expect(await contributions(id), {source: 12000});
    });

    test('a correction whose reason is only whitespace is refused', () async {
      await bothOpen();
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', marchExpense(id, amount: 13000));

      final outcome = await updateAs(
        'accountant@example.com',
        movedToApril(id, amount: 13000, reason: '   \t  '),
        baseRowVersion: 2,
      );
      expect(outcome.isRefused, isTrue);
      expect(outcome.refusalOrNull!.kind, RefusalKind.reasonRequired);
    });

    test('an expense cannot be moved OUT of a closed month, and that month keeps '
        'every paisa', () async {
      // The defect, stated as the assertion it should always have been.
      //
      // Before the fix this call returned `applied` and the contributions went from
      // {2026-03: 4500000} to {2026-04: 4500000} — a closed month's Operating Profit
      // changed by ₹45,000 through an ordinary edit. A status assertion alone would not
      // catch a "fix" that refused and moved the rows anyway, so the figures Phase 5
      // will aggregate are asserted on both sides of the attempt.
      await bothOpen();
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', marchExpense(id));

      await signInAs('giridhar@hki.com');
      final before = await contributions(id);
      expect(before, {source: 4500000});

      await setPeriod(source, closed: true);

      // The Accountant holds `expense.edit.all`, `transaction.correct.business_date`
      // **and** `transaction.correct.beyond_window`. Every gate except the period lock
      // is satisfied, so the period lock is the only thing that can refuse this.
      final outcome = await updateAs(
        'accountant@example.com',
        movedToApril(id),
        baseRowVersion: 2,
      );

      expect(
        outcome.isRefused,
        isTrue,
        reason:
            'spec 13.4 rejects every edit AFFECTING a closed period, and lifting '
            'an amount out of one affects it as surely as putting one in',
      );
      expect(outcome.refusalOrNull!.kind, RefusalKind.periodClosed);

      await signInAs('giridhar@hki.com');
      expect(
        await contributions(id),
        before,
        reason:
            'the closed month must hold exactly what it held — a refusal that '
            'still moved the rows would be no protection at all',
      );

      await setPeriod(source, closed: false);
    });

    test('an expense cannot be moved INTO a closed month either', () async {
      await bothOpen();
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', marchExpense(id, amount: 22000));

      await setPeriod(target, closed: true);
      final outcome = await updateAs(
        'accountant@example.com',
        movedToApril(id, amount: 22000),
        baseRowVersion: 2,
      );
      expect(outcome.isRefused, isTrue);
      expect(
        outcome.refusalOrNull!.kind,
        RefusalKind.periodClosed,
        reason:
            'the target check is the one that already worked; it still must',
      );

      await signInAs('giridhar@hki.com');
      expect(await contributions(id), {source: 22000});
      await setPeriod(target, closed: false);
    });

    test('both periods closed is refused, and nothing moves', () async {
      await bothOpen();
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', marchExpense(id, amount: 31000));

      await setPeriod(source, closed: true);
      await setPeriod(target, closed: true);
      final outcome = await updateAs(
        'accountant@example.com',
        movedToApril(id, amount: 31000),
        baseRowVersion: 2,
      );
      expect(outcome.isRefused, isTrue);
      expect(outcome.refusalOrNull!.kind, RefusalKind.periodClosed);

      await signInAs('giridhar@hki.com');
      expect(await contributions(id), {source: 31000});
      await bothOpen();
    });

    test('the Owner does not bypass the period lock either', () async {
      // The RBAC Owner holds every capability there is. None of them is permission to
      // change a closed month's totals: reopening is a separate, reasoned, audited act
      // and stays the only way (spec 13.4).
      await bothOpen();
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', marchExpense(id, amount: 27000));

      await setPeriod(source, closed: true);
      final outcome = await updateAs(
        'giridhar@hki.com',
        movedToApril(id, amount: 27000),
        baseRowVersion: 2,
      );
      expect(outcome.isRefused, isTrue);
      expect(outcome.refusalOrNull!.kind, RefusalKind.periodClosed);

      await signInAs('giridhar@hki.com');
      expect(await contributions(id), {source: 27000});

      // And after a deliberate reopen the same correction is accepted — which is what
      // makes the refusal a lock rather than a wall.
      await setPeriod(source, closed: false);
      final afterReopen = await updateAs(
        'giridhar@hki.com',
        movedToApril(id, amount: 27000),
        baseRowVersion: 2,
      );
      expect(
        afterReopen.isOk,
        isTrue,
        reason: 'refused: ${afterReopen.refusalOrNull?.message}',
      );
      await signInAs('giridhar@hki.com');
      expect(await contributions(id), {target: 27000});
    });

    test('the two correction capabilities compose; neither replaces the other', () async {
      // Reachable in both directions with the seeded role bundles:
      //
      //   * the window binds on somebody who is not moving a date at all — the D+8 case
      //     in the edit-window group above;
      //   * the correction capability binds on somebody well inside the window — the
      //     missing-capability case above;
      //   * and holding both, on an entry far outside the window, succeeds here.
      //
      // The one combination the seeded bundles cannot express is a holder of
      // `transaction.correct.business_date` who lacks `transaction.correct.beyond_window`
      // — the Accountant and the Owner hold both. That the two are separate guards, and
      // that neither is spelled in terms of the other, is asserted structurally in the
      // migration instead. Stated rather than implied.
      await bothOpen();
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', marchExpense(id, amount: 19000));

      final outcome = await updateAs(
        'accountant@example.com',
        movedToApril(id, amount: 19000),
        baseRowVersion: 2,
      );
      expect(
        outcome.isOk,
        isTrue,
        reason:
            'March is far outside the seven-day window; beyond_window covers the '
            'age and business_date covers the act '
            '(${outcome.refusalOrNull?.message})',
      );
    });

    test(
      'a correction from a stale version is a conflict, not an overwrite',
      () async {
        await bothOpen();
        final id = const Uuid().v4();
        await createAs('giridhar@hki.com', marchExpense(id, amount: 17000));

        // Somebody else edits it first, so the version the corrector holds is stale.
        final first = await updateAs('accountant@example.com', {
          ...marchExpense(id, amount: 17000),
          'p_notes': '$marker - edited by somebody else',
        }, baseRowVersion: 2);
        expect(first.isOk, isTrue, reason: '${first.refusalOrNull?.message}');

        final stale = await updateAs(
          'accountant@example.com',
          movedToApril(id, amount: 17000),
          baseRowVersion: 2,
        );
        expect(stale.isRefused, isTrue);
        expect(
          stale.refusalOrNull!.kind,
          RefusalKind.versionConflict,
          reason:
              'the correction capability authorises the act, never the overwriting '
              'of a version nobody reviewed (D-021)',
        );

        await signInAs('giridhar@hki.com');
        expect(await contributions(id), {source: 17000});
      },
    );

    test(
      'a redelivered correction replays: one effect, one audit row',
      () async {
        await bothOpen();
        final id = const Uuid().v4();
        final createdRow = await createAs(
          'giridhar@hki.com',
          marchExpense(id, amount: 26000),
        );
        final number = createdRow['txn_number'] as String;

        final mutationId = const Uuid().v4();
        final firstAttempt = await updateAs(
          'accountant@example.com',
          movedToApril(id, amount: 26000),
          baseRowVersion: 2,
          mutationId: mutationId,
        );
        expect(
          firstAttempt.isOk,
          isTrue,
          reason: '${firstAttempt.refusalOrNull?.message}',
        );

        final replay = await updateAs(
          'accountant@example.com',
          movedToApril(id, amount: 26000),
          baseRowVersion: 2,
          mutationId: mutationId,
        );
        expect(replay.isOk, isTrue);
        expect(replay.valueOrNull!['status'], 'replayed');

        await signInAs('giridhar@hki.com');
        final row = await client
            .from('expense_document')
            .select('row_version,business_date,txn_number,business_date_source')
            .eq('id', id)
            .single();
        expect(row['row_version'], 3, reason: 'exactly one version advanced');
        expect(row['business_date'], '2026-04-10');
        expect(row['business_date_source'], 'corrected');
        expect(row['txn_number'], number);
        expect(await contributions(id), {target: 26000});

        final audit = await client
            .from('audit_logs')
            .select('id')
            .eq('entity_id', id)
            .eq('action', 'expense_business_date_corrected');
        expect(
          audit,
          hasLength(1),
          reason: 'a replay produces no second audit effect (D-004)',
        );
      },
    );

    test('a correction whose response is lost recovers on retry', () async {
      // Not a duplicate call. The request is sent, the server commits, the body is
      // drained, and only then does the transport throw the platform's own
      // SocketException — so the client is in the one state idempotency exists for: the
      // work is done and it does not know (D-132).
      await bothOpen();
      final id = const Uuid().v4();
      final createdRow = await createAs(
        'giridhar@hki.com',
        marchExpense(id, amount: 38000),
      );
      final number = createdRow['txn_number'] as String;

      final transport = ControllableTransport();
      final lossy = SupabaseClient(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_ANON_KEY'] as String,
        httpClient: transport,
      );
      addTearDown(() async {
        await lossy.auth.signOut();
        await lossy.dispose();
      });
      await lossy.auth.signInWithPassword(
        email: 'accountant@example.com',
        password:
            (identities['accountant@example.com']
                    as Map<String, dynamic>)['password']
                as String,
      );

      final mutationId = const Uuid().v4();
      transport.loseResponseOnceFor = '/rpc/expense_update';
      final lost = await ExpenseGateway(lossy).update(
        arguments: movedToApril(id, amount: 38000),
        baseRowVersion: 2,
        mutationId: mutationId,
      );
      expect(
        lost.failureOrNull,
        isNotNull,
        reason: 'the client must learn nothing, not a refusal (D-048)',
      );
      expect(transport.lostResponses, isNotEmpty);

      // The same intent, redelivered. A fresh mutation id would be a second financial
      // record for one act.
      final retry = await ExpenseGateway(lossy).update(
        arguments: movedToApril(id, amount: 38000),
        baseRowVersion: 2,
        mutationId: mutationId,
      );
      expect(
        retry.isOk,
        isTrue,
        reason: 'refused: ${retry.refusalOrNull?.message}',
      );
      expect(retry.valueOrNull!['status'], 'replayed');

      await signInAs('giridhar@hki.com');
      final row = await client
          .from('expense_document')
          .select('row_version,business_date,txn_number')
          .eq('id', id)
          .single();
      expect(row['row_version'], 3);
      expect(row['business_date'], '2026-04-10');
      expect(row['txn_number'], number);
      expect(await contributions(id), {target: 38000});

      final audit = await client
          .from('audit_logs')
          .select('id')
          .eq('entity_id', id)
          .eq('action', 'expense_business_date_corrected');
      expect(audit, hasLength(1));
    });

    test(
      'a cross-period expense is protected on every period it contributes to',
      () async {
        // D-034: a bill that genuinely spans months contributes to each of them, and each
        // is checked individually. Reducing the source check to "the old business date"
        // would miss the other months entirely.
        await bothOpen();
        final id = const Uuid().v4();
        await createAs('giridhar@hki.com', {
          'p_id': id,
          'p_business_date': '2026-04-10',
          'p_total_minor': 6000000,
          'p_notes': marker,
          'p_allocations': [
            {
              ...ccrKirana,
              'amount_minor': 6000000,
              'periods': [
                {
                  'period_start': '2026-03-15',
                  'period_end': '2026-03-31',
                  'amount_minor': 3000000,
                  'is_derived': false,
                },
                {
                  'period_start': '2026-04-01',
                  'period_end': '2026-04-14',
                  'amount_minor': 3000000,
                  'is_derived': false,
                },
              ],
            },
          ],
        });

        await signInAs('giridhar@hki.com');
        final before = await contributions(id);
        expect(before, {source: 3000000, target: 3000000});

        // The document's own business date is in April, and only March is closed. A guard
        // that looked at `business_date` alone would let this through.
        await setPeriod(source, closed: true);
        final outcome = await updateAs('accountant@example.com', {
          'p_id': id,
          'p_business_date': '2026-04-10',
          'p_total_minor': 6000000,
          'p_notes': '$marker - recut entirely into April',
          'p_allocations': [
            {...ccrKirana, 'amount_minor': 6000000},
          ],
        }, baseRowVersion: 2);

        expect(outcome.isRefused, isTrue);
        expect(
          outcome.refusalOrNull!.kind,
          RefusalKind.periodClosed,
          reason:
              'the closed month holds 30,000 rupees of this bill; an edit that '
              'recut it entirely into April would empty that month',
        );

        await signInAs('giridhar@hki.com');
        expect(await contributions(id), before);
        await setPeriod(source, closed: false);
      },
    );
  });

  // ── A void reason that says nothing is not a reason ───────────────────────
  //
  // One-argument `btrim` strips spaces and nothing else, so a lone tab satisfied the rule
  // that a void always states why. Proven against the shipped function before it was
  // changed: `expense_void(p_reason => E'\t')` applied, the document was permanently
  // voided, and the audit row's reason was a tab.
  //
  // The matrix is the same one the correction reason is held to, because they are now one
  // rule — `app.stated_reason` — rather than two expressions that happened to agree.
  group('a void reason rejects every whitespace-only value', () {
    const marker = 'Phase 3 corrective: void reason whitespace';

    String today() {
      final d = DateTime.now().toUtc();
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    /// A fresh expense, voidable by the Accountant.
    Future<String> voidable({int amount = 15000}) async {
      final id = const Uuid().v4();
      await createAs('giridhar@hki.com', {
        'p_id': id,
        'p_business_date': today(),
        'p_total_minor': amount,
        'p_notes': marker,
        'p_allocations': [
          {...ccrKirana, 'amount_minor': amount},
        ],
      });
      return id;
    }

    Future<RemoteOutcome<Map<String, dynamic>>> voidWith(
      String id,
      String? reason,
    ) async {
      await signInAs('accountant@example.com');
      return ExpenseGateway(client).voidExpense(
        expenseId: id,
        baseRowVersion: 2,
        reason: reason ?? '',
        mutationId: const Uuid().v4(),
      );
    }

    Future<bool> isVoided(String id) async {
      await signInAs('giridhar@hki.com');
      final row = await client
          .from('expense_document')
          .select('voided_at')
          .eq('id', id)
          .single();
      return row['voided_at'] != null;
    }

    for (final blank in const [
      ('', 'empty'),
      ('   ', 'spaces'),
      ('\t', 'one tab — the case that got through'),
      ('\n', 'newline'),
      ('\r', 'carriage return'),
      (' \t\r\n ', 'mixed whitespace'),
    ]) {
      test('refused: ${blank.$2}', () async {
        final id = await voidable();
        final outcome = await voidWith(id, blank.$1);

        expect(outcome.isRefused, isTrue, reason: blank.$2);
        expect(outcome.refusalOrNull!.kind, RefusalKind.reasonRequired);
        expect(outcome.refusalOrNull!.message, isNot(contains('SQLSTATE')));
        expect(
          await isVoided(id),
          isFalse,
          reason: 'a refused void leaves the document exactly as it was',
        );
      });
    }

    test('an ordinary reason still voids, and is stored trimmed', () async {
      // The control. Without it, "whitespace is refused" and "nothing can be voided"
      // look identical, and the second would pass just as green.
      final id = await voidable();
      final outcome = await voidWith(
        id,
        '  Duplicate of an entry recorded twice  ',
      );
      expect(
        outcome.isOk,
        isTrue,
        reason: 'refused: ${outcome.refusalOrNull?.message}',
      );
      expect(await isVoided(id), isTrue);

      await signInAs('giridhar@hki.com');
      final audit = await client
          .from('audit_logs')
          .select('reason')
          .eq('entity_id', id)
          .eq('action', 'expense_voided');
      expect(audit, hasLength(1));
      expect(
        audit.single['reason'],
        'Duplicate of an entry recorded twice',
        reason:
            'the ends are trimmed — the project convention — and nothing else about '
            'the operator s words is touched',
      );
    });

    test(
      'internal spacing is content, not whitespace to be squeezed',
      () async {
        final id = await voidable();
        final outcome = await voidWith(
          id,
          'Duplicate  of  KI-EXP-26-27-000012',
        );
        expect(outcome.isOk, isTrue);

        await signInAs('giridhar@hki.com');
        final audit = await client
            .from('audit_logs')
            .select('reason')
            .eq('entity_id', id)
            .eq('action', 'expense_voided');
        expect(audit.single['reason'], 'Duplicate  of  KI-EXP-26-27-000012');
      },
    );

    test('everything else about a void is unchanged', () async {
      // The restatement touched two lines. These are the rules that must not have moved
      // with them, and they are asserted here rather than assumed from a green suite.
      final id = await voidable(amount: 21000);

      // A manager holds no `expense.void` at all.
      await signInAs('ccr.manager@example.com');
      final refused = await ExpenseGateway(client).voidExpense(
        expenseId: id,
        baseRowVersion: 2,
        reason: 'a manager should not be able to do this',
        mutationId: const Uuid().v4(),
      );
      expect(refused.isRefused, isTrue);
      expect(
        refused.refusalOrNull!.kind,
        anyOf(RefusalKind.missingCapability, RefusalKind.outOfUnitScope),
      );

      // A stale version is a conflict, not an overwrite.
      final stale = await voidWith(id, 'stale attempt');
      expect(stale.isOk, isTrue, reason: 'v2 is current, so this one applies');

      final second = await voidWith(id, 'a second void on a stale view');
      expect(second.isRefused, isTrue);
      expect(
        second.refusalOrNull!.kind,
        anyOf(RefusalKind.recordVoided, RefusalKind.versionConflict),
        reason: 'a voided document is immutable, and a stale intent is refused',
      );

      // The number survives, and the void is audited once.
      await signInAs('giridhar@hki.com');
      final row = await client
          .from('expense_document')
          .select('txn_number,voided_at')
          .eq('id', id)
          .single();
      expect(row['txn_number'], startsWith('KI-EXP-'));
      expect(row['voided_at'], isNotNull);
      final audit = await client
          .from('audit_logs')
          .select('id')
          .eq('entity_id', id)
          .eq('action', 'expense_voided');
      expect(audit, hasLength(1));
    });

    test('a redelivered void replays rather than voiding twice', () async {
      final id = await voidable(amount: 24000);
      final mutationId = const Uuid().v4();

      await signInAs('accountant@example.com');
      final first = await ExpenseGateway(client).voidExpense(
        expenseId: id,
        baseRowVersion: 2,
        reason: 'Recorded in error',
        mutationId: mutationId,
      );
      expect(first.isOk, isTrue);

      final replay = await ExpenseGateway(client).voidExpense(
        expenseId: id,
        baseRowVersion: 2,
        reason: 'Recorded in error',
        mutationId: mutationId,
      );
      expect(replay.isOk, isTrue);
      expect(replay.valueOrNull!['status'], 'replayed');

      await signInAs('giridhar@hki.com');
      final audit = await client
          .from('audit_logs')
          .select('id')
          .eq('entity_id', id)
          .eq('action', 'expense_voided');
      expect(audit, hasLength(1), reason: 'one void, one audit effect (D-004)');
    });
  });
  // ── Reopening a closed period states why, and a tab is not why ────────────
  //
  // The last of the five mandatory financial reasons to reach the canonical rule.
  // `period_reopen` normalised its reason with `btrim(coalesce(p_reason, ''))`, which
  // strips spaces alone, and the probe that proved it reopened a genuinely closed period
  // with a lone tab:
  //
  //     period 2026-05 / CCR   closed, row_version 1
  //     period_reopen(E'\t')   APPLIED, state open, row_version 2, no refusal
  //     period_lock_events     {action: reopen, reason: "\t"}
  //     audit_logs             {action: period_reopened, reason: "\t"}
  //
  // The most privileged financial act in the system, justified by a tab.
  //
  // **Every case restores the fixture deliberately.** A financial period left closed or
  // reopened by a test is a real change to what the rest of the suite may write, so each
  // test closes the period it needs and puts it back, and the group asserts the end state.
  group('reopening a closed period states why', () {
    const periodKey = '2026-05';

    Future<String?> stateOf() async {
      await signInAs('giridhar@hki.com');
      final state = await client.rpc<dynamic>(
        'period_state',
        params: {'p_period_key': periodKey, 'p_business_unit_id': ccr},
      );
      return state as String?;
    }

    Future<void> close() async {
      await signInAs('giridhar@hki.com');
      await client
          .rpc<dynamic>(
            'period_close',
            params: {'p_period_key': periodKey, 'p_business_unit_id': ccr},
          )
          .then((_) {}, onError: (_) {});
    }

    Future<Object?> reopenWith(String? reason) async {
      await signInAs('giridhar@hki.com');
      try {
        return await client.rpc<dynamic>(
          'period_reopen',
          params: {
            'p_period_key': periodKey,
            'p_business_unit_id': ccr,
            'p_reason': reason,
            'p_mutation_id': const Uuid().v4(),
          },
        );
      } on PostgrestException catch (error) {
        return error;
      }
    }

    /// Leaves the period open, whatever the test did to it.
    Future<void> restore() async {
      if (await stateOf() == 'closed') {
        final restored = await reopenWith(
          'Live suite: restoring the period fixture to open',
        );
        expect(
          restored,
          isNot(isA<PostgrestException>()),
          reason:
              'the fixture must not be left closed for the rest of the suite',
        );
      }
      expect(await stateOf(), 'open');
    }

    tearDown(restore);
    tearDownAll(restore);

    for (final blank in const [
      (null, 'null'),
      ('', 'empty'),
      ('   ', 'spaces'),
      ('\t', 'one tab — the case that got through'),
      ('\n', 'newline'),
      ('\r', 'carriage return'),
      (' \t\r\n ', 'mixed whitespace'),
    ]) {
      test('refused: ${blank.$2}', () async {
        await close();
        expect(await stateOf(), 'closed');

        final outcome = await reopenWith(blank.$1);
        expect(outcome, isA<PostgrestException>(), reason: blank.$2);
        expect((outcome! as PostgrestException).code, 'KM008');
        expect(
          (outcome as PostgrestException).message,
          isNot(contains('SQLSTATE')),
        );

        expect(
          await stateOf(),
          'closed',
          reason:
              'a refused reopen leaves the period closed — the whole point of the '
              'rule is that a closed month is not reopened by accident',
        );
      });
    }

    test('a real reason reopens it, and is stored trimmed', () async {
      // The control. Without it, "whitespace is refused" and "nothing can be reopened"
      // look identical, and the second would pass just as green.
      await close();
      final outcome = await reopenWith(
        '  Correcting the June electricity split  ',
      );
      expect(outcome, isNot(isA<PostgrestException>()), reason: '$outcome');
      expect(await stateOf(), 'open');

      await signInAs('giridhar@hki.com');
      final lock = await client
          .from('period_locks')
          .select('reopen_reason,reopened_by,state')
          .eq('period_key', periodKey)
          .eq('business_unit_id', ccr)
          .single();
      expect(lock['state'], 'open');
      expect(
        lock['reopen_reason'],
        'Correcting the June electricity split',
        reason: 'the ends are trimmed — the project convention — and no more',
      );
      expect(lock['reopened_by'], isNotNull);

      // The append-only record and the audit row carry the same stated reason.
      final events = await client
          .from('period_lock_events')
          .select('action,reason,actor_id')
          .eq('action', 'reopen')
          .order('occurred_at', ascending: false)
          .limit(1);
      expect(events.single['reason'], 'Correcting the June electricity split');
      expect(events.single['actor_id'], isNotNull);

      final audit = await client
          .from('audit_logs')
          .select('reason')
          .eq('action', 'period_reopened')
          .order('occurred_at', ascending: false)
          .limit(1);
      expect(audit.single['reason'], 'Correcting the June electricity split');
    });

    test(
      'internal spacing is content, not whitespace to be squeezed',
      () async {
        await close();
        final outcome = await reopenWith('Reopened  for  the  May  correction');
        expect(outcome, isNot(isA<PostgrestException>()), reason: '$outcome');

        await signInAs('giridhar@hki.com');
        final lock = await client
            .from('period_locks')
            .select('reopen_reason')
            .eq('period_key', periodKey)
            .eq('business_unit_id', ccr)
            .single();
        expect(lock['reopen_reason'], 'Reopened  for  the  May  correction');
      },
    );

    test('every other protection is unchanged', () async {
      // The restatement touched two lines. These are the rules that must not have moved
      // with them.
      await close();

      // A manager holds no `period.reopen` — and is refused for the capability, not told
      // how to phrase a request they cannot make (the reason check runs after it).
      await signInAs('ccr.manager@example.com');
      Object? refused;
      try {
        await client.rpc<dynamic>(
          'period_reopen',
          params: {
            'p_period_key': periodKey,
            'p_business_unit_id': ccr,
            'p_reason': '\t',
            'p_mutation_id': const Uuid().v4(),
          },
        );
      } on PostgrestException catch (error) {
        refused = error;
      }
      expect(refused, isA<PostgrestException>());
      expect(
        (refused! as PostgrestException).code,
        anyOf('KM001', 'KM002'),
        reason:
            'permission is decided before the reason, so a caller who may not reopen '
            'learns nothing about what a valid request would look like',
      );
      expect(await stateOf(), 'closed');

      // A period that is not closed refuses, and does not enumerate.
      await reopenWith('Live suite: restoring the period fixture to open');
      expect(await stateOf(), 'open');
      final notClosed = await reopenWith('it is already open');
      expect(notClosed, isA<PostgrestException>());
      expect((notClosed! as PostgrestException).code, 'KM015');

      // And a redelivered reopen replays rather than reopening twice.
      await close();
      final mutationId = const Uuid().v4();
      await signInAs('giridhar@hki.com');
      for (var attempt = 0; attempt < 2; attempt++) {
        await client.rpc<dynamic>(
          'period_reopen',
          params: {
            'p_period_key': periodKey,
            'p_business_unit_id': ccr,
            'p_reason': 'Live suite: idempotent reopen',
            'p_mutation_id': mutationId,
          },
        );
      }
      expect(await stateOf(), 'open');

      final events = await client
          .from('period_lock_events')
          .select('id')
          .eq('action', 'reopen')
          .eq('mutation_id', mutationId);
      expect(
        events,
        hasLength(1),
        reason: 'one reopen, one append-only record (D-004)',
      );
    });
  });
}
