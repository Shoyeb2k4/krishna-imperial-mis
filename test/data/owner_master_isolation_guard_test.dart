/// D-208, resolved by option B of the project lead's OA-3 ruling: the three OA-1
/// owner-master tables stay **unwritten**, and this proves it permanently.
///
/// `owners`, `ownership_shares` and `owner_family_members` are classified
/// `organizationGlobal`, which means they **survive a user switch**. That was safe in OA-1
/// only because nothing wrote them; the moment anything does, a shared back-office
/// workstation hands the previous person's owner identities, 50:50 ratio and family links
/// to whoever signs in next. OA-2 moved the settlement onto an owner-keyed copy instead
/// (D-208), and OA-3 keeps it there.
///
/// Option A — moving the OA-1 pre-check path onto the owner-keyed cache — was not narrow:
/// the people that path serves (NC recorders holding `owner_masters.view`) are exactly the
/// people the settlement transport is now closed to, so it would need a second transport.
/// That belongs with the NC entry slice, not with OA-3.
///
/// A writer is anything that puts a row into one of the three: a Drift `into(...)` or
/// `update(...)`, a generated companion, or raw SQL. A **delete** is not a writer — the
/// purge may legitimately clear them — so it is deliberately not matched.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _masters = ['owners', 'ownershipShares', 'ownerFamilyMembers'];
const _masterTables = ['owners', 'ownership_shares', 'owner_family_members'];

/// Production Dart, with generated code excluded: `app_database.g.dart` *defines* the
/// companions and the insert helpers for every table, and a guard that read it would find
/// "writers" in a file that writes nothing.
List<File> _production() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
    .toList();

/// Source with `//` comments removed. A comment explaining that nothing writes these
/// tables must not be read as the write — the failure D-139's guard committed on its first
/// run, and which this project has repeated in its own machinery since.
String _code(String source) => source.replaceAll(RegExp(r'//[^\n]*'), '');

/// Every way a row can be put into one of the three masters.
List<RegExp> _writers() {
  final dart = _masters.join('|');
  final sql = _masterTables.join('|');
  return [
    // Drift: into(db.owners), into(_db.ownershipShares), batch.insert(db.owners, ...)
    RegExp(
      '\\b(into|update|insert|insertAll|insertOnConflictUpdate|replace)\\(\\s*'
      '[\\w.]*\\b($dart)\\b\\s*[,)]',
    ),
    // The generated companions. `\b` keeps `CanonicalOwnersCompanion` out: there is no
    // word boundary between the `l` and the `O`.
    RegExp(
      r'\b(OwnersCompanion|OwnershipSharesCompanion|OwnerFamilyMembersCompanion)\b',
    ),
    // Raw SQL.
    RegExp(
      '\\b(insert\\s+(or\\s+\\w+\\s+)?into|update|replace\\s+into)\\s+($sql)\\b',
      caseSensitive: false,
    ),
  ];
}

void main() {
  test('there is production code to scan in the first place', () {
    // A guard over an empty haystack passes perfectly and proves nothing (D-103).
    expect(_production().length, greaterThan(100));
  });

  test('the patterns recognise every shape of writer they claim to', () {
    // The guard's own control, run every time: if a pattern stops matching the shape it
    // exists for, this fails before the scan below can report a false "clean".
    const shapes = [
      'await _db.into(_db.owners).insert(row);',
      'await db.update(db.ownershipShares).write(x);',
      'batch.insert(db.ownerFamilyMembers, row);',
      'OwnersCompanion.insert(id: x)',
      "customStatement('INSERT INTO ownership_shares (id) VALUES (?)')",
      "customUpdate('UPDATE owner_family_members SET active = 0')",
      "customStatement('INSERT OR REPLACE INTO owners (id) VALUES (?)')",
    ];
    for (final shape in shapes) {
      expect(
        _writers().any((p) => p.hasMatch(shape)),
        isTrue,
        reason: 'no pattern recognises: $shape',
      );
    }

    const notWriters = [
      'await _db.into(_db.canonicalOwners).insert(row);',
      'CanonicalOwnersCompanion.insert(id: x)',
      "customStatement('DELETE FROM owners')",
      'await (_db.select(_db.owners)).get();',
      "customUpdate('UPDATE owner_ledger_entries SET x = 1')",
    ];
    for (final shape in notWriters) {
      expect(
        _writers().any((p) => p.hasMatch(shape)),
        isFalse,
        reason: 'a pattern mistakes this for a master writer: $shape',
      );
    }
  });

  test(
    'nothing in production writes an organisation-global owner master (D-208)',
    () {
      final offenders = <String>[];
      for (final file in _production()) {
        final source = _code(file.readAsStringSync());
        for (final pattern in _writers()) {
          for (final match in pattern.allMatches(source)) {
            offenders.add('${file.path}: ${match.group(0)}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these tables survive a user switch. Writing an owner identity, an ownership '
            'share or a family link into one hands it to whoever signs in next on a '
            'shared workstation. Owner data a person may read belongs in the owner-keyed '
            'canonical cache, which is purged per person (D-208, D-074)',
      );
    },
  );
}
