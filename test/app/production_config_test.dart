// secret-scan-exempt: builds deliberately fake key shapes to prove they are refused.
/// Production fails closed (Phase 9 Slice 2, D-346).
///
/// A production build with no backend used to start in offline mode and seed the shipped
/// demonstration masters — looking operational while connected to nothing. These tests
/// pin the rules that stop it, and that the environment a build belongs to comes from the
/// build itself and is never defaulted when it is unknown or contradictory.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/env/app_environment.dart';

String _fakeAnonJwt() {
  String seg(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${seg({'iss': 'supabase', 'ref': 'prodrefexample', 'role': 'anon', 'iat': 1750000000, 'exp': 2050000000})}'
      '.notarealsignature_notarealsignature';
}

const _prodUrl = 'https://prodrefexampleabc.supabase.co';
const _devUrl = 'https://loratzmactetjbqolwri.supabase.co';

AppConfig _config(
  AppFlavor flavor, {
  String url = _prodUrl,
  String? key,
  String? declared,
  bool useDeclared = true,
  String? built,
  bool release = false,
}) => AppConfig(
  flavor: flavor,
  supabaseUrl: url,
  supabaseAnonKey: key ?? _fakeAnonJwt(),
  declaredFlavor: useDeclared ? (declared ?? flavor.name) : null,
  buildFlavor: built,
  releaseBuild: release,
);

void main() {
  group('production refuses to start without its backend', () {
    for (final (name, url, key) in [
      ('no URL and no key', '', ''),
      ('no URL', '', null),
      ('no key', _prodUrl, ''),
      ('whitespace only', '   ', '  '),
    ]) {
      test(name, () {
        final config = _config(AppFlavor.prod, url: url, key: key);
        final problem = config.problem;
        expect(problem, isNotNull);
        expect(problem!.summary, contains('production build'));
        expect(config.permitsOfflineSeed, isFalse);
      });
    }

    test('it never treats a missing backend as offline mode', () {
      final config = _config(AppFlavor.prod, url: '', key: '');
      expect(config.hasBackend, isFalse);
      expect(config.permitsOfflineSeed, isFalse, reason: 'no demo masters');
      expect(config.problem, isNotNull, reason: 'start-up stops instead');
    });

    test('a development backend is refused for production', () {
      final problem = _config(AppFlavor.prod, url: _devUrl).problem;
      expect(problem, isNotNull);
      expect(problem!.summary, contains('development backend'));
    });

    test('a complete production configuration is accepted', () {
      final config = _config(AppFlavor.prod, release: true);
      expect(config.problem, isNull);
      expect(config.isProduction, isTrue);
      expect(config.permitsOfflineSeed, isFalse);
    });

    test('no refusal repeats a configuration value', () {
      final key = _fakeAnonJwt();
      for (final config in [
        _config(AppFlavor.prod, url: '', key: key),
        _config(AppFlavor.prod, url: _devUrl, key: key),
        _config(AppFlavor.prod, url: _prodUrl, key: ''),
      ]) {
        final text = config.problem.toString();
        expect(text.contains(key), isFalse);
        expect(text.contains('loratzmactetjbqolwri'), isFalse);
        expect(text.contains('prodrefexampleabc'), isFalse);
      }
    });
  });

  group('development and staging keep their offline mode', () {
    for (final flavor in [AppFlavor.dev, AppFlavor.staging]) {
      test('${flavor.name} with no backend starts offline with the seed', () {
        final config = _config(flavor, url: '', key: '');
        expect(config.problem, isNull);
        expect(config.permitsOfflineSeed, isTrue);
      });
    }

    test('staging may point at the development backend (rehearsal)', () {
      expect(_config(AppFlavor.staging, url: _devUrl).problem, isNull);
    });

    test('a configured backend is never seeded over', () {
      expect(_config(AppFlavor.dev).permitsOfflineSeed, isFalse);
    });
  });

  group('the environment comes from the build and is never defaulted', () {
    test('an unknown environment name is refused, not read as dev', () {
      final config = AppConfig(
        flavor: AppFlavor.fromName('production'),
        supabaseUrl: '',
        supabaseAnonKey: '',
        declaredFlavor: 'production',
      );
      expect(AppFlavor.tryParse('production'), isNull);
      expect(config.problem, isNotNull);
      expect(config.problem!.summary, contains('does not know'));
    });

    test(
      'an Android prod flavour built with a dev configuration is refused',
      () {
        final config = _config(AppFlavor.dev, url: '', key: '', built: 'prod');
        expect(config.problem, isNotNull);
        expect(config.problem!.summary, contains('different environments'));
      },
    );

    test('an Android prod flavour with no APP_FLAVOR is refused', () {
      final config = _config(
        AppFlavor.dev,
        url: '',
        key: '',
        useDeclared: false,
        built: 'prod',
      );
      expect(config.problem, isNotNull);
    });

    test('a matching flavour and configuration are accepted', () {
      expect(_config(AppFlavor.prod, built: 'prod').problem, isNull);
      expect(_config(AppFlavor.dev, built: 'dev').problem, isNull);
    });

    test('a release build that names no environment is refused', () {
      final config = _config(
        AppFlavor.dev,
        url: '',
        key: '',
        useDeclared: false,
        release: true,
      );
      expect(config.problem, isNotNull);
      expect(config.problem!.summary, contains('release build'));
    });

    test('a debug build with no declaration stays development', () {
      final config = _config(
        AppFlavor.dev,
        url: '',
        key: '',
        useDeclared: false,
      );
      expect(config.problem, isNull);
      expect(config.isProduction, isFalse);
    });

    test('host tests compile no environment, so they are development', () {
      final config = AppConfig.fromEnvironment();
      expect(config.isProduction, isFalse);
      expect(config.releaseBuild, isFalse);
      expect(config.buildFlavor, isNull);
    });
  });
}
