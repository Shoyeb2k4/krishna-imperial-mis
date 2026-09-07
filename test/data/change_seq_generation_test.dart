/// Every table carrying `change_seq` advances it on UPDATE (Phase 5 Slice 4, D-177).
///
/// `change_seq` is the project's one observable mutation generation — a single sequence
/// stamped onto every synced row so a client can ask *"what changed since?"*
/// (`ARCHITECTURE.md` §5.2). A table that carries the column and never advances it looks
/// correct at every glance: the `default nextval(...)` fires on INSERT, so the value is
/// present, plausible, and frozen for ever.
///
/// That is what `revenue_entries` and `revenue_attachments` did for a whole phase, and it
/// would have made a reporting delta miss every edit, every business-date correction and
/// every void. The live suite proves the behaviour against the real server; this asserts
/// the rule over the committed migrations, so a table added between live runs cannot slip
/// through.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every committed migration, oldest first.
List<({String name, String sql})> _migrations() {
  final files =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      (
        name: f.path.replaceAll(r'\', '/').split('/').last,
        sql: f.readAsStringSync(),
      ),
  ];
}

void main() {
  final migrations = _migrations();
  final all = migrations.map((m) => m.sql).join('\n');

  test('the corrective is committed, and says what it fixed', () {
    final corrective = migrations.where(
      (m) => m.name.contains('revenue_change_seq_advances_on_update'),
    );
    expect(
      corrective,
      hasLength(1),
      reason:
          'the D-172 corrective must exist as its own committed migration (D-056)',
    );

    final sql = corrective.single.sql;
    expect(
      sql,
      contains('app.stamp_change_seq'),
      reason: 'the narrow trigger function that stamps only the generation',
    );
    for (final table in const ['revenue_entries', 'revenue_attachments']) {
      expect(
        sql,
        contains('before update on public.$table'),
        reason: '$table carried change_seq and never advanced it',
      );
    }
  });

  test('the fix does not double-increment the concurrency token', () {
    // `app.touch_row` also does `row_version := old.row_version + 1`, and the revenue RPCs
    // already do that themselves. Attaching it would refuse every client's next correction
    // as a version conflict (D-021, KM003), so the corrective must NOT use it.
    final corrective = migrations
        .firstWhere(
          (m) => m.name.contains('revenue_change_seq_advances_on_update'),
        )
        .sql;
    final triggerBodies = RegExp(
      r'create trigger[\s\S]{0,400}?execute function ([\w.]+)\(\)',
    ).allMatches(corrective).map((m) => m.group(1)).toList();

    expect(triggerBodies, isNotEmpty);
    expect(
      triggerBodies,
      everyElement(isNot('app.touch_row')),
      reason:
          'a revenue trigger using touch_row would bump row_version a second time and '
          'every correction would be refused KM003',
    );
  });

  test(
    'the invariant is general, not a list of the two tables that were wrong',
    () {
      // A check that named `revenue_entries` and `revenue_attachments` would pass for ever
      // and catch nothing new. It has to search the catalogue, or the next table to carry
      // the column arrives exactly as these two did (D-068, D-071, D-077).
      final corrective = migrations
          .firstWhere(
            (m) => m.name.contains('revenue_change_seq_advances_on_update'),
          )
          .sql;
      expect(corrective, contains("col.column_name = 'change_seq'"));
      expect(corrective, contains('pg_trigger'));
      expect(
        corrective,
        contains('global_change_seq'),
        reason: 'it looks for a trigger that actually stamps the sequence',
      );
    },
  );

  test('no later migration removes the stamping triggers', () {
    // Cheap, and it is the shape of regression this project keeps finding: a policy or
    // trigger restored from a superseded version of itself (D-174).
    final afterCorrective = migrations
        .skipWhile(
          (m) => !m.name.contains('revenue_change_seq_advances_on_update'),
        )
        .skip(1)
        .map((m) => m.sql)
        .join('\n');
    for (final trigger in const [
      'revenue_entries_change_seq',
      'revenue_attachments_change_seq',
    ]) {
      expect(
        RegExp('drop\\s+trigger[^;]*$trigger').hasMatch(afterCorrective),
        isFalse,
        reason: '$trigger is dropped by a later migration and not recreated',
      );
    }
  });

  test('the expense side already stamped, and still does', () {
    // The audit that made the corrective necessary also confirmed the expense engine is
    // sound. `app.touch_row` is attached to all three expense tables, and that is what
    // makes the effective document generation computable there.
    for (final trigger in const [
      'expenses_touch',
      'expense_allocations_touch',
      'expense_period_allocations_touch',
    ]) {
      expect(
        all,
        contains(trigger),
        reason: '$trigger is what advances the expense reporting generation',
      );
    }
  });
}
