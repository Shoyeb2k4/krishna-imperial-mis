/// The parts of the Phase 9 governance record (D-334 … D-345) that a later change could
/// silently break.
///
/// Slice 1 is documentation only, so this guard reads documents and the migration folder:
/// the runbook keeps its sections and stays free of secret material; the release checklist
/// no longer claims that no tax rule is seeded; and the authoritative replay contract
/// (D-338) still names files that exist and the number of files the repository holds.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _runbook = 'docs/PRODUCTION_RUNBOOK.md';

/// The sections D-344 and the Slice 1 direction require of the runbook.
const _runbookSections = [
  'Production environment inventory',
  'Secrets register',
  'Release artefacts',
  'User provisioning',
  'Role and scope administration',
  'Password reset',
  'Period close and reopen',
  'Android deployment',
  'Windows deployment',
  'Backup',
  'Restore',
  'Lost device',
  'Local recovery and reset',
  'Server outage',
  'Rollback',
  'Contact and escalation',
  'Go-live checklist',
];

/// Shapes of secret material that must never appear in a governance document (D-345).
/// The secret scan covers the tree too; this keeps the rule next to the record it guards.
final _secretShapes = <String, RegExp>{
  'a JWT': RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'),
  'a Supabase secret key': RegExp(r'sb_secret_[A-Za-z0-9]'),
  'a Supabase publishable key': RegExp(r'sb_publishable_[A-Za-z0-9]'),
  'a database URL with a password': RegExp(
    r'postgres(ql)?://[^\s:@/]+:[^\s@]+@',
  ),
  'a private key block': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
};

List<String> _secretFindings(String text) => [
  for (final e in _secretShapes.entries)
    if (e.value.hasMatch(text)) e.key,
];

List<String> _migrationFiles() =>
    Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.sql'))
        .toList()
      ..sort();

void main() {
  group('the production runbook (D-344, D-345)', () {
    test('exists and keeps every required section', () {
      final text = File(_runbook).readAsStringSync();
      final missing = [
        for (final s in _runbookSections)
          if (!RegExp(
            '^#{2,3} .*${RegExp.escape(s)}',
            multiLine: true,
          ).hasMatch(text))
            s,
      ];
      expect(missing, isEmpty, reason: 'the runbook skeleton lost a section');
    });

    test('carries no secret material', () {
      for (final path in [
        _runbook,
        'docs/RELEASE_CHECKLIST.md',
        'docs/PROJECT_STATUS.md',
        'docs/DECISIONS.md',
      ]) {
        expect(
          _secretFindings(File(path).readAsStringSync()),
          isEmpty,
          reason:
              '$path must say where a secret lives, never what it is (D-345)',
        );
      }
    });

    test('the secret check can fail (planted violations)', () {
      // Assembled at run time, so no credential-shaped literal sits in the tree for the
      // secret scan to (rightly) refuse.
      expect(
        _secretFindings(['key: sb_', 'secret_', 'abc123'].join()),
        isNotEmpty,
      );
      expect(
        _secretFindings(['postgres', '://u:pw', '@db.example:5432/x'].join()),
        isNotEmpty,
      );
      expect(
        _secretFindings(
          [
            'token ',
            'eyJ',
            'hbGciOiJIUzI1',
            '.',
            'eyJzdWIiOiIxMjM0',
            '.sig',
          ].join(),
        ),
        isNotEmpty,
      );
      expect(
        _secretFindings('the publishable key, stored in config/prod.json'),
        isEmpty,
      );
    });
  });

  test(
    '§K.2 states the current tax configuration, not the Phase 2 one (D-345)',
    () {
      final lines = File('docs/RELEASE_CHECKLIST.md').readAsLinesSync();
      final stale = [
        for (final l in lines)
          if (l.contains('No tax rule is seeded') && !l.contains('said'))
            l.trim(),
      ];
      expect(stale, isEmpty, reason: 'D-096 seeded the four verified rules');
      expect(lines.join('\n'), contains('four verified revenue tax rules'));
    },
  );

  group('the authoritative replay contract (D-338)', () {
    test('names migration files that exist', () {
      final files = _migrationFiles();
      for (final name in const [
        '20260829090500_api_surface_invariant.sql',
        '20260829100000_usage_and_attachment_storage.sql',
        '20260901132225_revenue_verified_baseline_fy2627.sql',
      ]) {
        expect(files, contains(name), reason: 'D-338 names $name');
      }
    });

    test('records the committed file count the repository holds', () {
      // D-338 records 98 committed migration files. Adding or removing one changes what
      // the authoritative replay must apply: the contract (and, from Slice 4, the
      // manifest) has to be restated in the same change.
      expect(
        _migrationFiles(),
        hasLength(98),
        reason:
            'update D-338 and DATABASE_SCHEMA.md *Phase 9* with the new count',
      );
      expect(
        File('docs/DATABASE_SCHEMA.md').readAsStringSync(),
        contains('**98** `.sql` files'),
      );
    });

    test(
      'the anomaly runs after its anchor, which filename order does not do',
      () {
        final files = _migrationFiles();
        expect(
          files.indexOf('20260829090500_api_surface_invariant.sql') <
              files.indexOf('20260829100000_usage_and_attachment_storage.sql'),
          isTrue,
          reason:
              'if filename order ever put them right, D-338 must stop calling it an '
              'anomaly',
        );
      },
    );
  });
}
