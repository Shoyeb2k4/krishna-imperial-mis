/// The release build stays hardened (Phase 9 Slice 2, D-346).
///
/// Every blocker the Phase 9 audit found (D-335) was a configuration line nothing checked:
/// a permission only the debug overlay declared, a release build signed with the debug
/// key, a rules file named and never created, a production build that would run offline
/// on demonstration data, and a production install that would have shared the D-247
/// folder. Each is held here as a property of the files, with planted violations proving
/// the checks can fail.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Source with `//` and `///` comment lines and XML comments removed, so prose that names a
/// thing is never mistaken for the thing.
String _code(String source) {
  final noXml = source.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  return [
    for (final line in noXml.split('\n'))
      if (!line.trimLeft().startsWith('//')) line,
  ].join('\n');
}

bool _manifestDeclaresInternet(String manifest) => _code(
  manifest,
).contains('<uses-permission android:name="android.permission.INTERNET"');

/// The release build type's block of `build.gradle.kts`.
String _releaseBlock(String gradle) {
  final code = _code(gradle);
  final start = code.indexOf('release {', code.indexOf('buildTypes {'));
  expect(start, greaterThan(0), reason: 'the release build type exists');
  final end = code.indexOf('debug {', start);
  return code.substring(start, end < 0 ? code.length : end);
}

List<String> _signingViolations(String gradle) {
  final release = _releaseBlock(gradle);
  final code = _code(gradle);
  return [
    if (release.contains('getByName("debug")')) 'release signed with debug',
    if (!release.contains(
      'signingConfig = signingConfigs.findByName("release")',
    ))
      'release not signed with the upload key',
    if (!release.contains('isMinifyEnabled = true')) 'R8 off',
    if (!release.contains('"proguard-rules.pro"')) 'rules file not named',
    if (!code.contains('rootProject.file("key.properties")'))
      'signing not read from android/key.properties',
    if (!code.contains('throw GradleException('))
      'missing signing does not stop',
    if (!RegExp(
      r'name\.startsWith\("pre"\) && name\.endsWith\("ReleaseBuild"\)',
    ).hasMatch(code))
      'the stop is not wired to every release variant',
  ];
}

/// Every place `lib/` asks path_provider for the application support folder, outside the
/// one module allowed to (D-346).
List<String> _supportDirectoryCallers(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    if (!path.endsWith('local_storage_location.dart') &&
        _code(source).contains('getApplicationSupportDirectory'))
      path,
];

void main() {
  group('A · Android INTERNET permission', () {
    test('the main manifest declares it, so every release build has it', () {
      expect(
        _manifestDeclaresInternet(
          _read('android/app/src/main/AndroidManifest.xml'),
        ),
        isTrue,
      );
    });

    test('the guard fails when only the debug overlay declares it', () {
      expect(
        _manifestDeclaresInternet(
          '<manifest>\n'
          '  <!-- <uses-permission android:name="android.permission.INTERNET"/> -->\n'
          '  <application/>\n</manifest>',
        ),
        isFalse,
      );
    });

    test('the main manifest asks for nothing else', () {
      final permissions = RegExp(
        r'<uses-permission android:name="([^"]+)"',
      ).allMatches(_code(_read('android/app/src/main/AndroidManifest.xml')));
      expect(permissions.map((m) => m.group(1)), [
        'android.permission.INTERNET',
      ]);
    });
  });

  group('B, C · release signing and R8', () {
    test('release is signed with the upload key or not at all, with R8 on', () {
      expect(
        _signingViolations(_read('android/app/build.gradle.kts')),
        isEmpty,
      );
    });

    test('the rules file the release build names exists', () {
      expect(File('android/app/proguard-rules.pro').existsSync(), isTrue);
    });

    test('the guard fails on a debug-key fallback', () {
      final gradle = _read('android/app/build.gradle.kts').replaceFirst(
        'signingConfig = signingConfigs.findByName("release")',
        'signingConfig = signingConfigs.getByName("debug")',
      );
      expect(_signingViolations(gradle), contains('release signed with debug'));
    });

    test('the guard fails when shrinking is switched off', () {
      final gradle = _read(
        'android/app/build.gradle.kts',
      ).replaceFirst('isMinifyEnabled = true', 'isMinifyEnabled = false');
      expect(_signingViolations(gradle), contains('R8 off'));
    });

    test('no signing secret is in the repository', () {
      final gradle = _code(_read('android/app/build.gradle.kts'));
      for (final word in ['storePassword = "', 'keyPassword = "']) {
        expect(gradle.contains(word), isFalse, reason: word);
      }
      expect(File('android/key.properties').existsSync(), isFalse);
    });
  });

  group('secret files stay out of git', () {
    for (final path in [
      'android/key.properties',
      'key.properties',
      'android/app/upload-keystore.jks',
      'upload.keystore',
      'android/upload.p12',
      'config/prod.json',
      'config/staging.json',
    ]) {
      test('$path is ignored', () async {
        final result = await Process.run('git', ['check-ignore', '-q', path]);
        expect(result.exitCode, 0, reason: '$path must be git-ignored');
      });
    }
  });

  group('D · production cannot run on demonstration data', () {
    test('the seed is written only when the configuration permits it', () {
      final bootstrap = _code(_read('lib/app/bootstrap.dart'));
      expect(bootstrap.contains('if (config.permitsOfflineSeed)'), isTrue);
      expect(bootstrap.contains('if (!config.hasBackend) {'), isFalse);
      expect(RegExp(r'seedMasterData\(').allMatches(bootstrap), hasLength(1));
    });

    test(
      'start-up stops on a configuration problem before any storage opens',
      () {
        final bootstrap = _code(_read('lib/app/bootstrap.dart'));
        final refused = bootstrap.indexOf(
          'throw ConfigurationRefused(problem)',
        );
        expect(refused, greaterThan(0));
        expect(refused, lessThan(bootstrap.indexOf('resolveLocalStorage(')));
        expect(refused, lessThan(bootstrap.indexOf('openLocalStore(')));
      },
    );
  });

  group('E · production local data identity', () {
    test('only the storage module asks for the application support folder', () {
      final sources = {
        for (final file
            in Directory('lib')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')))
          file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
      };
      expect(_supportDirectoryCallers(sources), isEmpty);
    });

    test('the guard fails on a second caller', () {
      expect(
        _supportDirectoryCallers({
          'lib/data/local/elsewhere.dart':
              'final d = await getApplicationSupportDirectory();',
        }),
        ['lib/data/local/elsewhere.dart'],
      );
    });

    test(
      'bootstrap and main resolve storage from the build, never a literal',
      () {
        final bootstrap = _code(_read('lib/app/bootstrap.dart'));
        final main = _code(_read('lib/main.dart'));
        expect(bootstrap.contains('production: config.isProduction'), isTrue);
        expect(
          main.contains('production: AppConfig.fromEnvironment().isProduction'),
          isTrue,
        );
        for (final source in [bootstrap, main]) {
          expect(source.contains("'krishna_mis."), isFalse);
          expect(source.contains("'Krishna Imperial MIS'"), isFalse);
          expect(source.contains('MIS Production'), isFalse);
        }
      },
    );

    test('the legacy folder name is what the Windows executable declares', () {
      // `getApplicationSupportDirectory()` on Windows is
      // %APPDATA%\<CompanyName>\<ProductName> from Runner.rc. If that resource changed,
      // "legacy" would stop naming the folder non-production builds really use.
      final rc = _read('windows/runner/Runner.rc');
      expect(
        rc.contains(r'VALUE "CompanyName", "Krishna Imperial" "\0"'),
        isTrue,
      );
      expect(
        rc.contains(r'VALUE "ProductName", "Krishna Imperial MIS" "\0"'),
        isTrue,
      );
      final storage = _read('lib/data/local/local_storage_location.dart');
      expect(storage.contains("company = 'Krishna Imperial'"), isTrue);
      expect(storage.contains("legacy = 'Krishna Imperial MIS'"), isTrue);
      expect(
        storage.contains("production = 'Krishna Imperial MIS Production'"),
        isTrue,
      );
    });
  });

  group('F · versioning', () {
    test('the release version is semantic, with an integer build number', () {
      final version = RegExp(
        r'^version: (\d+)\.(\d+)\.(\d+)\+(\d+)$',
        multiLine: true,
      ).firstMatch(_read('pubspec.yaml'));
      expect(version, isNotNull);
      expect(int.parse(version!.group(4)!), greaterThanOrEqualTo(1));
    });

    test(
      'Android takes its version from pubspec, never a hand-typed number',
      () {
        final gradle = _code(_read('android/app/build.gradle.kts'));
        expect(gradle.contains('versionCode = flutter.versionCode'), isTrue);
        expect(gradle.contains('versionName = flutter.versionName'), isTrue);
      },
    );
  });
}
