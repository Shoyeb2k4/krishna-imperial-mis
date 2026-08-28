// secret-scan-exempt: this file contains the patterns it searches for.
// Mechanical enforcement of the rule that has no exception: no privileged credential
// may exist anywhere a client binary could pick it up.
//
// `docs/ARCHITECTURE.md` §8.1 promises "a CI grep ... rather than by discipline". This
// is that grep. It is deliberately a build-failing check and not a warning.
//
//   dart run tool/check_no_client_secrets.dart              # working tree
//   dart run tool/check_no_client_secrets.dart --history    # also every committed blob
//   dart run tool/check_no_client_secrets.dart --artefacts  # also the built binaries
//
// `--artefacts` scans what is actually distributed — the Android package and its
// contents, the Windows executable and everything beside it in its bundle — as raw
// bytes, because a compiled asset or a `--dart-define` ends up as a plain string inside a
// binary and a source-only scan would never see it. It additionally refuses any literal
// listed in a git-ignored `config/*-forbidden.local.json`, which is how a development
// identity's password is proven absent from a build without the password itself ever
// entering this file, the repository, or a report.
//
// It looks for credential *material*, not for the word "service_role" appearing in prose
// or in the classifier that exists to reject it — a check that cries wolf gets muted, and
// a muted check protects nothing.
import 'dart:convert';
import 'dart:io';

/// Whether a candidate match is really key material.
///
/// Needed because a compiled binary is not text. Dart's kernel packs every string
/// constant into one table with no separators, so `sb_secret_` — a literal in the
/// classifier that exists to *reject* secret keys — sits directly against whatever
/// literal was interned next to it, and any "prefix plus N characters" pattern matches
/// it. Length cannot separate the two; the shape of the material can.
typedef _Verifier = bool Function(RegExpMatch match);

/// Real key material is high-entropy: random base64url of that length reliably carries
/// several digits. Concatenated English identifiers carry none.
bool _looksLikeKeyMaterial(RegExpMatch match) {
  final body = match.group(1) ?? '';
  final head = body.length > 30 ? body.substring(0, 30) : body;
  final digits = RegExp(r'[0-9]').allMatches(head).length;
  return head.length >= 30 && digits >= 4;
}

/// Patterns that can only be real credential material.
final _patterns = <({String label, RegExp pattern, _Verifier? verify})>[
  (
    label: 'modern Supabase secret key',
    pattern: RegExp(r'sb_secret_([A-Za-z0-9_\-]{30,})'),
    verify: _looksLikeKeyMaterial,
  ),
  (
    label: 'Postgres connection string with a password',
    pattern: RegExp(r'postgres(?:ql)?://[^\s:/@]+:[^\s@]+@'),
    verify: null,
  ),
  (
    // The header *and* a body. Several dependencies declare the PEM delimiters as
    // constants — `crypto_keys` does — and a header on its own is a parser, not a key.
    label: 'PEM private key block',
    pattern: RegExp(
      r'-----BEGIN [A-Z ]*PRIVATE KEY-----\s*[A-Za-z0-9+/=]{40,}',
    ),
    verify: null,
  ),
  (
    label: 'Supabase JWT secret / signing secret assignment',
    pattern: RegExp(
      r'(JWT_SECRET|SIGNING_SECRET)\s*[:=]\s*["\x27]?[A-Za-z0-9/+=_\-]{16,}',
    ),
    verify: null,
  ),
];

/// Any JWT at all, so its payload can be decoded and its role inspected.
final _jwt = RegExp(
  r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}',
);

/// Directories that are never part of a shipped artefact and are noisy to scan.
const _skipDirs = {'.git', '.dart_tool', '.idea', 'node_modules', '.gradle'};

/// A file exempts itself by carrying this marker, with a reason on the same line.
///
/// Deliberately in the file rather than in a list here. A handful of files legitimately
/// contain credential *shapes* — the classifier that rejects them, this scanner, and the
/// test that proves the classifier works — and an exemption is far easier to review when
/// it sits next to the thing being exempted than when it sits in a list somebody has to
/// go and look up.
const _exemptionMarker = 'secret-scan-exempt:';

const _textExtensions = {
  '.dart',
  '.json',
  '.yaml',
  '.yml',
  '.md',
  '.xml',
  '.gradle',
  '.kts',
  '.properties',
  '.cc',
  '.cpp',
  '.h',
  '.rc',
  '.txt',
  '.sql',
  '.env',
  '.plist',
  '.cmake',
  '.g.dart',
};

Future<int> main(List<String> args) async {
  final findings = <String>[];
  final root = Directory.current;

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(root.path.length + 1)
        .replaceAll(r'\', '/');
    if (_skipDirs.any(
      (d) =>
          relative == d ||
          relative.startsWith('$d/') ||
          relative.contains('/$d/'),
    )) {
      continue;
    }
    if (!_looksTextual(relative)) continue;

    String content;
    try {
      content = await entity.readAsString();
    } on Object {
      continue; // binary or unreadable: nothing a grep could responsibly assert
    }
    if (content.contains(_exemptionMarker)) continue;
    findings.addAll(_scan(content, relative));
  }

  if (args.contains('--history')) {
    findings.addAll(await _scanHistory());
  }

  if (args.contains('--artefacts')) {
    findings.addAll(await _scanArtefacts());
  }

  if (findings.isEmpty) {
    stdout.writeln(
      'No privileged credential material found. Working tree clean'
      '${args.contains('--history') ? ', git history clean' : ''}'
      '${args.contains('--artefacts') ? ', built artefacts clean' : ''}.',
    );
    return 0;
  }

  stderr.writeln(
    'PRIVILEGED CREDENTIAL MATERIAL FOUND — this must never ship:',
  );
  for (final finding in findings) {
    stderr.writeln('  $finding');
  }
  stderr.writeln(
    '\nRotate the exposed credential first, then remove it. '
    'A key that has been committed is compromised even after deletion.',
  );
  exitCode = 1;
  return 1;
}

/// Literals that must not appear in a build, supplied out of band.
///
/// The file is git-ignored and holds the development identities' passwords. They are read
/// only to be searched for; no finding ever prints one.
List<String> _forbiddenLiterals() {
  final file = File('config/dev-identities.local.json');
  if (!file.existsSync()) return const [];
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) return const [];
  return [
    for (final entry in decoded.values)
      if (entry is Map && entry['password'] is String)
        entry['password'] as String,
  ];
}

/// The built Android and Windows artefacts, scanned as bytes.
Future<List<String>> _scanArtefacts() async {
  final findings = <String>[];
  final forbidden = _forbiddenLiterals();

  final artefacts = <String>[
    'build/app/outputs/flutter-apk/app-dev-debug.apk',
    'build/app/outputs/flutter-apk/app-dev-release.apk',
  ];
  for (final dir in const [
    'build/windows/x64/runner/Debug',
    'build/windows/x64/runner/Release',
    'build/app/intermediates/assets',
    'build/flutter_assets',
    // The unpacked Android package. A `.apk` is a zip, so searching it as bytes only
    // finds what happens to be stored uncompressed; the extracted tree is what actually
    // has to be clean.
    'build/_apk_extract',
  ]) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      artefacts.add(file.path);
    }
  }

  for (final path in artefacts) {
    final file = File(path);
    if (!file.existsSync()) continue;
    // latin1 keeps every byte addressable as a character, so an embedded ASCII
    // credential is found wherever it sits in a compiled binary.
    final content = latin1.decode(await file.readAsBytes(), allowInvalid: true);
    findings.addAll(_scan(content, 'artefact: $path'));
    for (final literal in forbidden) {
      if (content.contains(literal)) {
        findings.add('artefact: $path — a development identity password');
      }
    }
  }

  if (artefacts.isEmpty) {
    findings.add(
      'no built artefact was found to scan — build before claiming a clean binary',
    );
  }
  return findings.toSet().toList();
}

bool _looksTextual(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return _textExtensions.contains(path.substring(dot).toLowerCase());
}

/// Findings in one blob. Reports the location and the kind, never the value.
List<String> _scan(String content, String where) {
  final findings = <String>[];
  for (final entry in _patterns) {
    for (final match in entry.pattern.allMatches(content)) {
      if (entry.verify != null && !entry.verify!(match)) continue;
      findings.add('$where — ${entry.label}');
      break;
    }
  }
  for (final match in _jwt.allMatches(content)) {
    final role = _jwtRole(match.group(0)!);
    if (role != null && role != 'anon') {
      findings.add(
        '$where — JWT with role "$role" (only "anon" may appear in a client)',
      );
    }
  }
  return findings;
}

String? _jwtRole(String token) {
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(token.split('.')[1])),
    );
    final decoded = jsonDecode(payload);
    return decoded is Map && decoded['role'] is String
        ? decoded['role'] as String
        : null;
  } on Object {
    return null;
  }
}

/// Every blob ever committed. A deleted secret is still a leaked secret.
Future<List<String>> _scanHistory() async {
  // Committed blobs are scanned per file, not as one concatenated diff, so a file that
  // exempts itself is honoured in history too — and so that a finding names the file it
  // is actually in rather than "somewhere in the log".
  final files = await Process.run('git', [
    'log',
    '--all',
    '--pretty=format:',
    '--name-only',
  ]);
  if (files.exitCode != 0) {
    return ['git history could not be read: ${files.stderr}'];
  }
  final paths = (files.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && _looksTextual(line))
      .toSet();

  final findings = <String>[];
  for (final path in paths) {
    final revisions = await Process.run('git', [
      'log',
      '--all',
      '--format=%H',
      '--',
      path,
    ]);
    for (final sha
        in (revisions.stdout as String)
            .split('\n')
            .where((s) => s.trim().isNotEmpty)) {
      final blob = await Process.run('git', ['show', '${sha.trim()}:$path']);
      if (blob.exitCode != 0) continue;
      final content = blob.stdout as String;
      if (content.contains(_exemptionMarker)) continue;
      findings.addAll(
        _scan(content, 'git history: $path @ ${sha.trim().substring(0, 8)}'),
      );
    }
  }
  return findings.toSet().toList();
}
