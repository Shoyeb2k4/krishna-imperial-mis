// secret-scan-exempt: this file contains the patterns it searches for.
// Mechanical enforcement of the rule that has no exception: no privileged credential
// may exist anywhere a client binary could pick it up.
//
// `docs/ARCHITECTURE.md` §8.1 promises "a CI grep ... rather than by discipline". This
// is that grep. It is deliberately a build-failing check and not a warning.
//
//   dart run tool/check_no_client_secrets.dart              # working tree + artefacts
//   dart run tool/check_no_client_secrets.dart --history    # also every committed blob
//
// It looks for credential *material*, not for the word "service_role" appearing in prose
// or in the classifier that exists to reject it — a check that cries wolf gets muted, and
// a muted check protects nothing.
import 'dart:convert';
import 'dart:io';

/// Patterns that can only be real credential material.
final _patterns = <({String label, RegExp pattern})>[
  (
    label: 'modern Supabase secret key',
    pattern: RegExp(r'sb_secret_[A-Za-z0-9_\-]{8,}'),
  ),
  (
    label: 'Postgres connection string with a password',
    pattern: RegExp(r'postgres(?:ql)?://[^\s:/@]+:[^\s@]+@'),
  ),
  (
    label: 'PEM private key block',
    pattern: RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  ),
  (
    label: 'Supabase JWT secret / signing secret assignment',
    pattern: RegExp(
      r'(JWT_SECRET|SIGNING_SECRET)\s*[:=]\s*["\x27]?[A-Za-z0-9/+=_\-]{16,}',
    ),
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

  if (findings.isEmpty) {
    stdout.writeln(
      'No privileged credential material found. '
      '${args.contains('--history') ? 'Working tree and git history clean.' : 'Working tree clean.'}',
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

bool _looksTextual(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return _textExtensions.contains(path.substring(dot).toLowerCase());
}

/// Findings in one blob. Reports the location and the kind, never the value.
List<String> _scan(String content, String where) {
  final findings = <String>[];
  for (final entry in _patterns) {
    if (entry.pattern.hasMatch(content)) {
      findings.add('$where — ${entry.label}');
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
