/// Phase 8 Slice 2 — the D-186 profiling harness cannot reach anything but itself.
///
/// `tool/perf/` builds a throwaway PostgreSQL cluster and loads hundreds of thousands of
/// synthetic financial rows into it. D-312 (D3) is explicit that none of that may reach
/// krishna-mis-dev, and D-313 that the harness must never touch the machine's installed
/// PostgreSQL service. Those are properties of the scripts, so they are asserted over the
/// scripts rather than remembered: a later edit that opens a TCP listener, drops a
/// refusal guard, or names a hosted project fails here, on any host, without a database.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String name) =>
    File('tool/perf/$name').readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('the local cluster opens no TCP port and uses its own socket', () {
    final sh = _read('localpg.sh');
    expect(sh, contains("listen_addresses = ''"));
    expect(sh, contains('unix_socket_directories'));
    expect(sh, isNot(contains('127.0.0.1')));
    expect(sh, isNot(contains('0.0.0.0')));
    expect(sh, contains('initdb'), reason: 'it must create its own cluster');
  });

  test('the generator and the self-test refuse to run outside the harness', () {
    for (final name in ['synth.sql', 'selftest.sql']) {
      final sql = _read(name);
      expect(
        sql,
        contains("current_database() <> 'krishna_perf'"),
        reason: name,
      );
      expect(
        sql,
        contains("current_setting('listen_addresses') <> ''"),
        reason: name,
      );
      expect(sql, contains('raise exception'), reason: name);
    }
  });

  test(
    'the driver connects only to the harness socket, never to a network host',
    () {
      final py = _read('d186.py');
      expect(py, contains('LOCAL_SOCKET_DIR'));
      expect(
        py,
        contains("refuses a parameter file whose target is not 'local'"),
      );
      expect(RegExp(r'"-h",\s*LOCAL_SOCKET_DIR').hasMatch(py), isTrue);
    },
  );

  test('every probe batch is one transaction that ends in ROLLBACK', () {
    final py = _read('d186.py');
    final probe = _read('d186_probe.sql');
    expect(py, contains('out = ["begin;"'));
    expect(py, contains('"rollback;"]'));
    expect(
      probe,
      contains('create function pg_temp.d186_probe'),
      reason: 'the probe is a temporary function, not a schema change',
    );
    expect(probe, isNot(contains('create function public.')));
    expect(probe, isNot(contains('alter system')));
  });

  test(
    'no harness file names a hosted Supabase project or its credentials',
    () {
      for (final entity in Directory('tool/perf').listSync()) {
        if (entity is! File) continue;
        final text = entity.readAsStringSync();
        final name = entity.path.replaceAll(r'\', '/');
        expect(text, isNot(contains('supabase.co')), reason: name);
        expect(text, isNot(contains('loratzmactetjbqolwri')), reason: name);
        expect(text, isNot(contains('sb_secret_')), reason: name);
        expect(text, isNot(contains('service_role_key')), reason: name);
      }
    },
  );

  test('synthetic principals can never resolve to a real mailbox', () {
    final ids = _read('bootstrap_identities.sql');
    final emails = RegExp(
      r'[\w.]+@[\w.-]+',
    ).allMatches(ids).map((m) => m[0]!).toSet();
    expect(emails, isNotEmpty);
    for (final email in emails) {
      expect(
        email,
        endsWith('.invalid'),
        reason: '$email is not an RFC 2606 name',
      );
    }
  });

  test('the self-test carries a positive control that is rolled back', () {
    final sql = _read('selftest.sql');
    expect(
      sql,
      contains(r'$$ select true $$'),
      reason: 'the control disables the predicate to prove the checks can fail',
    );
    expect(sql, contains('rollback;'));
    expect(sql, contains('before_md5'));
    expect(sql, contains('after_md5'));
  });
}
