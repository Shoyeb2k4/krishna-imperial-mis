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
        await client
            .rpc<dynamic>(
              'expense_void',
              params: {
                'p_id': id,
                'p_base_row_version': 2,
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
}
