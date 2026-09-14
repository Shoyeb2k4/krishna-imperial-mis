/// Report detail is read and never written (Phase 5 Slice 10, D-233).
///
/// Opening a document from a P&L must not persist it into the ordinary transaction tables,
/// fill the reporting cache, queue an outbox item or invoke a mutation. These hold for files
/// nobody has written yet, so each is a scan — first proven to catch a planted violation.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String source) =>
    source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// What the reader may not reach or call.
List<String> readerViolations(String source) {
  final code = _code(source);
  return [
    for (final (pattern, what) in [
      (RegExp(r'data/local/'), 'imports local storage'),
      (RegExp(r'data/repositories/'), 'imports a repository'),
      (RegExp(r'data/sync/'), 'imports the sync layer'),
      (
        RegExp(
          r'\b(AppDatabase|ReportingCache|OutboxRepository|ExpensePull)\b',
        ),
        'holds a writer',
      ),
      (
        RegExp(
          r'\b(pullOne|applyServerDocument|createLocally|updateLocally|voidLocally)\b',
        ),
        'persists a document',
      ),
      (
        RegExp(r'\.(create|update|voidEntry|voidExpense|callRpc|rpc)\s*\('),
        'invokes a mutation',
      ),
      (RegExp(r'\.(insert|upsert|delete)\s*\('), 'writes a row'),
      (
        RegExp(r'\b(customStatement|customUpdate|customInsert)\b'),
        'writes SQL',
      ),
    ])
      if (pattern.hasMatch(code)) what,
  ];
}

String _method(String source, String name) {
  final start = source.indexOf('Future<List<');
  expect(start, isNonNegative);
  final at = source.indexOf(' $name({');
  expect(at, isNonNegative, reason: '$name exists');
  final end = source.indexOf('\n  }\n', at);
  expect(end, greaterThan(at));
  return source.substring(at, end);
}

void main() {
  const readerPath = 'lib/data/remote/report_document_reader.dart';
  const sourcePath = 'lib/data/reporting/cached_drilldown_source.dart';

  test('the guard catches what it claims to', () {
    for (final planted in [
      "import 'package:krishna_mis/data/local/app_database.dart';",
      "import 'package:krishna_mis/data/sync/expense_pull.dart';",
      "await pull.pullOne(id);",
      "await repo.applyServerDocument(header: h, components: c, orgId: o);",
      "await revenue.update(arguments: a, baseRowVersion: 1, mutationId: m);",
      "await expenses.voidExpense(expenseId: id, baseRowVersion: 1, reason: r, mutationId: m);",
      "await client.rpc('expense_update');",
      "await client.from('expenses').insert(row);",
      "await db.customStatement('INSERT INTO sync_outbox VALUES (?)');",
    ]) {
      expect(readerViolations(planted), isNotEmpty, reason: planted);
    }
    expect(
      readerViolations("final header = await revenue.fetchDocument(id);"),
      isEmpty,
    );
  });

  test('the report document reader writes nothing and invokes nothing', () {
    expect(readerViolations(File(readerPath).readAsStringSync()), isEmpty);
  });

  test('the reader reads only the authorised projections', () {
    final code = _code(File(readerPath).readAsStringSync());
    final calls = RegExp(
      r'(expenses|revenue)\.(\w+)\(',
    ).allMatches(code).map((m) => m.group(2)!).toSet();
    expect(calls, isNotEmpty);
    expect(
      calls.every((c) => c.startsWith('fetch')),
      isTrue,
      reason: 'only fetch* reads: $calls',
    );
  });

  test('the drill-down source writes nothing', () {
    final code = _code(File(sourcePath).readAsStringSync());
    for (final forbidden in [
      'applyYear(',
      'applySnapshot(',
      'pruneYear(',
      'customStatement',
      'ReportingSync',
    ]) {
      expect(code.contains(forbidden), isFalse, reason: forbidden);
    }
  });

  test('the document-row queries are reads', () {
    final cache = File(
      'lib/data/repositories/reporting_cache.dart',
    ).readAsStringSync();
    for (final name in ['revenueDocuments', 'expenseDocuments']) {
      final body = _method(cache, name);
      expect(body, contains('customSelect'));
      for (final forbidden in [
        'INSERT',
        'UPDATE ',
        'DELETE',
        'customStatement',
      ]) {
        expect(body.contains(forbidden), isFalse, reason: '$name: $forbidden');
      }
      // Membership is the stored P&L date and the exact bucket, nothing else.
      expect(body, contains('pnl_date >= ?'));
      expect(body, contains('owner_user_id = ?'));
      for (final forbidden in [
        'captured_at',
        'payment_date',
        'created_at',
        "date('now')",
        'CURRENT_DATE',
      ]) {
        expect(body.contains(forbidden), isFalse, reason: '$name: $forbidden');
      }
    }
  });

  test('nothing on the report path uses the ordinary transaction pull', () {
    final files = [
      ...Directory('lib/features/profit_and_loss')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      File(readerPath),
      File(sourcePath),
    ];
    for (final file in files) {
      final code = _code(file.readAsStringSync());
      expect(code.contains('pullOne'), isFalse, reason: file.path);
      expect(code.contains('expense_pull'), isFalse, reason: file.path);
      expect(code.contains('applyServerDocument'), isFalse, reason: file.path);
    }
  });
}
