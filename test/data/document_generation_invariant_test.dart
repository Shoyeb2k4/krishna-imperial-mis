// Phase 8 · D-320. The paged reporting delta lists a document when the document's OWN
// generation (`expenses.change_seq`, `revenue_entries.change_seq`) passes the cursor. That
// is complete only because no server path changes a document's reporting rows without
// stamping its header in the same transaction (D-177). This holds that property over the
// latest definition of every function the migrations leave in place, so a future writer
// that forgets the header fails here rather than going silently missing from a device's
// P&L.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Latest body of every function, after replaying [migrations] in filename order and
/// honouring `DROP FUNCTION`.
Map<String, String> latestBodies(List<String> migrations) {
  final create = RegExp(
    r'create or replace function\s+([\w.]+)\s*\([\s\S]*?\)\s*returns[\s\S]*?as (\$\w*\$)([\s\S]*?)\2',
    caseSensitive: false,
  );
  final drop = RegExp(
    r'drop function(?: if exists)?\s+([\w.]+)\s*\(',
    caseSensitive: false,
  );
  final bodies = <String, String>{};
  for (final sql in migrations) {
    final events = <({int at, String name, String? body})>[
      for (final m in create.allMatches(sql))
        (at: m.start, name: m.group(1)!.toLowerCase(), body: m.group(3)!),
      for (final m in drop.allMatches(sql))
        (at: m.start, name: m.group(1)!.toLowerCase(), body: null),
    ]..sort((a, b) => a.at.compareTo(b.at));
    for (final e in events) {
      if (e.body == null) {
        bodies.remove(e.name);
      } else {
        bodies[e.name] = e.body!;
      }
    }
  }
  return bodies;
}

String _code(String body) =>
    body.replaceAll(RegExp(r'--[^\n]*'), '').toLowerCase();

bool _writes(String code, String table) => RegExp(
  r'(insert\s+into|update|delete\s+from)\s+(public\.)?' + table + r'\b',
).hasMatch(code);

/// Functions that write a document's reporting rows without writing its header.
///
/// `app.write_expense_allocations` is a helper that only writes lines; it is allowed on
/// its own, and every function that calls it must stamp the header instead.
List<String> headerlessWriters(Map<String, String> bodies) {
  final offenders = <String>[];
  for (final entry in bodies.entries) {
    final code = _code(entry.value);
    final writesExpenseLines =
        _writes(code, 'expense_allocations') ||
        _writes(code, 'expense_period_allocations') ||
        code.contains('app.write_expense_allocations(');
    if (writesExpenseLines &&
        entry.key != 'app.write_expense_allocations' &&
        !RegExp(r'update\s+(public\.)?expenses\b').hasMatch(code)) {
      offenders.add(
        '${entry.key}: writes expense lines without stamping the expense',
      );
    }
    if (_writes(code, 'revenue_components') &&
        !_writes(code, 'revenue_entries')) {
      offenders.add(
        '${entry.key}: writes components without writing the entry',
      );
    }
  }
  return offenders;
}

void main() {
  final migrations = [
    for (final f
        in (Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path))))
      f.readAsStringSync(),
  ];

  test('every writer of an expense\'s lines or a sale\'s components stamps the '
      'document in the same function', () {
    final bodies = latestBodies(migrations);
    // The scan has to be looking at the real writers, or it proves nothing.
    expect(
      bodies.keys,
      containsAll(<String>[
        'public.expense_create',
        'public.expense_update',
        'public.expense_void',
        'app.write_expense_allocations',
        'public.revenue_create',
        'public.revenue_update',
      ]),
    );
    expect(headerlessWriters(bodies), isEmpty);
  });

  test('self-check: a planted headerless writer is caught', () {
    final planted = [
      ...migrations,
      r'''
create or replace function public.expense_reapportion(p_id uuid) returns void
language sql as $$
  delete from public.expense_period_allocations where expense_id = p_id;
$$;
create or replace function public.expense_relines(p_id uuid) returns void
language plpgsql as $fn$ begin
  perform app.write_expense_allocations(null, p_id, null, null, null, null);
end $fn$;
create or replace function public.revenue_recomponent(p_id uuid) returns void
language sql as $$
  update public.revenue_components set net_minor = net_minor where revenue_entry_id = p_id;
$$;
''',
    ];
    final offenders = headerlessWriters(latestBodies(planted));
    expect(offenders, hasLength(3));
    expect(offenders.join('\n'), contains('public.expense_reapportion'));
    expect(offenders.join('\n'), contains('public.expense_relines'));
    expect(offenders.join('\n'), contains('public.revenue_recomponent'));
  });
}
