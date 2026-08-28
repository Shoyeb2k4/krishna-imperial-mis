// secret-scan-exempt: builds deliberately fake key shapes to prove they are refused.
/// The one configuration mistake that must never ship: a privileged credential compiled
/// into an Android or Windows binary.
///
/// The naive check — `key.contains('service_role')` — passes a real service-role key
/// straight through, because the role lives inside the base64 JWT payload and never
/// appears in the string a developer pastes. These tests build genuine key *shapes* (with
/// obviously fake material) and assert the classifier decodes them.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/env/app_environment.dart';
import 'package:krishna_mis/app/env/supabase_key_inspection.dart';

/// A JWT of the shape Supabase issues, carrying [role]. The signature is nonsense —
/// nothing here verifies signatures, and no real key is ever committed (D-027).
String fakeJwt(String role) {
  String seg(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final header = seg({'alg': 'HS256', 'typ': 'JWT'});
  final payload = seg({
    'iss': 'supabase',
    'ref': 'examplerefexample',
    'role': role,
    'iat': 1750000000,
    'exp': 2050000000,
  });
  return '$header.$payload.notarealsignature_notarealsignature';
}

AppConfig configWith({
  String url = 'https://examplerefexample.supabase.co',
  required String key,
}) => AppConfig(flavor: AppFlavor.dev, supabaseUrl: url, supabaseAnonKey: key);

void main() {
  group('key classification', () {
    test('a real-shaped service-role JWT is caught even though the raw string '
        'never contains the words "service_role"', () {
      final key = fakeJwt('service_role');
      // The point of the whole exercise: the old substring check would pass this.
      expect(key.contains('service_role'), isFalse);

      expect(SupabaseKeyInspector.classify(key), SupabaseKeyKind.serviceRole);
      expect(configWith(key: key).looksLikeServiceRoleKey, isTrue);
      expect(configWith(key: key).problem, isNotNull);
    });

    test('a legacy anon JWT is accepted', () {
      final config = configWith(key: fakeJwt('anon'));
      expect(config.keyKind, SupabaseKeyKind.legacyAnon);
      expect(config.looksLikeServiceRoleKey, isFalse);
      expect(config.problem, isNull);
      expect(config.hasBackend, isTrue);
    });

    test(
      'a modern publishable key is accepted and a secret key is refused',
      () {
        expect(
          configWith(key: 'sb_publishable_ZmFrZS1ub3QtcmVhbA').keyKind,
          SupabaseKeyKind.publishable,
        );
        expect(
          configWith(key: 'sb_secret_ZmFrZS1ub3QtcmVhbA').keyKind,
          SupabaseKeyKind.secret,
        );
        expect(
          configWith(key: 'sb_secret_ZmFrZS1ub3QtcmVhbA').problem,
          isNotNull,
        );
      },
    );

    test(
      'a Postgres connection string is refused — it carries the database password',
      () {
        final config = configWith(
          key:
              'postgresql://postgres:not-a-real-password@db.example.supabase.co:5432/postgres',
        );
        expect(config.keyKind, SupabaseKeyKind.databaseUrl);
        expect(config.looksLikeServiceRoleKey, isTrue);
      },
    );

    test('an unrecognised key is refused rather than guessed at', () {
      expect(
        configWith(key: 'probably-a-password').keyKind,
        SupabaseKeyKind.unrecognised,
      );
      expect(configWith(key: 'probably-a-password').problem, isNotNull);
    });

    test('a JWT with some other role is refused', () {
      expect(
        configWith(key: fakeJwt('supabase_admin')).keyKind,
        SupabaseKeyKind.unknownJwtRole,
      );
    });

    test('no refusal message ever reproduces the key', () {
      for (final kind in SupabaseKeyKind.values) {
        final message = SupabaseKeyInspector.refusalFor(kind) ?? '';
        expect(message.contains('sb_secret_Z'), isFalse);
        expect(message.contains('eyJ'), isFalse);
      }
      final config = configWith(key: fakeJwt('service_role'));
      expect(config.toString().contains('eyJ'), isFalse);
      expect(config.problem.toString().contains('eyJ'), isFalse);
    });
  });

  group('configuration completeness', () {
    test('an entirely empty configuration is valid — the app runs offline', () {
      const config = AppConfig(
        flavor: AppFlavor.dev,
        supabaseUrl: '',
        supabaseAnonKey: '',
      );
      expect(config.hasBackend, isFalse);
      expect(config.problem, isNull);
    });

    test(
      'a half-filled configuration is refused rather than failing later',
      () {
        expect(configWith(key: '').problem, isNotNull);
        expect(configWith(url: '', key: fakeJwt('anon')).problem, isNotNull);
      },
    );

    test('the database host is refused where the API URL is expected', () {
      final config = configWith(
        url: 'https://db.examplerefexample.supabase.co',
        key: fakeJwt('anon'),
      );
      expect(config.problem, isNotNull);
      expect(config.problem!.detail, contains('Data API'));
    });

    test('a URL with embedded credentials is refused', () {
      final config = configWith(
        url: 'https://user:secret@examplerefexample.supabase.co',
        key: fakeJwt('anon'),
      );
      expect(config.problem, isNotNull);
    });

    test('http is refused; only https reaches the project', () {
      expect(
        configWith(
          url: 'http://examplerefexample.supabase.co',
          key: fakeJwt('anon'),
        ).problem,
        isNotNull,
      );
    });

    test(
      'the project ref is derived for diagnostics, and never from a db host',
      () {
        expect(
          configWith(key: fakeJwt('anon')).projectRef,
          'examplerefexample',
        );
        expect(
          configWith(
            url: 'https://db.abc.supabase.co',
            key: fakeJwt('anon'),
          ).projectRef,
          isNull,
        );
      },
    );
  });
}
