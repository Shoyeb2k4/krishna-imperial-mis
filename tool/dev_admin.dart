/// Development-backend administration for repeatable acceptance runs.
///
/// This is a *developer* tool, not part of the application. It signs in as a development
/// identity over the ordinary public API — the publishable key and a password from a
/// git-ignored file — and calls the same `SECURITY DEFINER` RPCs the client calls. It
/// holds no privileged credential, bypasses no rule, and gets exactly the answers the
/// server would give any other caller: an Owner may revoke a grant, a Manager may not.
///
/// It exists so an acceptance run can perform the administrative half of a scenario
/// (D-048 revocation, deactivation, restoration) without a human clicking through a
/// dashboard, and without any secret ever entering the repository.
///
///     dart run tool/dev_admin.dart whoami        <email>
///     dart run tool/dev_admin.dart grants        <email>
///     dart run tool/dev_admin.dart revoke-scope  <actor-email> <target-email> <unit-code>
///     dart run tool/dev_admin.dart grant-scope   <actor-email> <target-email> <role> <unit-code>
///     dart run tool/dev_admin.dart deactivate    <actor-email> <target-email>
///     dart run tool/dev_admin.dart reactivate    <actor-email> <target-email>
///     dart run tool/dev_admin.dart rename        <actor-email> <entity-type> <entity-id> <name> <base-version>
///     dart run tool/dev_admin.dart masters       <email>
library;

import 'dart:convert';
import 'dart:io';

const _configPath = 'config/dev.json';
const _identitiesPath = 'config/dev-identities.local.json';

late final Map<String, dynamic> _config;
late final Map<String, dynamic> _identities;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/dev_admin.dart <command> [...]');
    exit(64);
  }
  _config =
      jsonDecode(File(_configPath).readAsStringSync()) as Map<String, dynamic>;
  final identities = File(_identitiesPath);
  if (!identities.existsSync()) {
    stderr.writeln(
      'No development identities at $_identitiesPath. This file is git-ignored and '
      'must be created locally; see supabase/README.md.',
    );
    exit(69);
  }
  _identities =
      jsonDecode(identities.readAsStringSync()) as Map<String, dynamic>;

  final command = args.first;
  final rest = args.sublist(1);
  switch (command) {
    case 'whoami':
      final token = await _signIn(rest[0]);
      _show(await _rpc(token, 'my_authority', const {}));
    case 'grants':
      final token = await _signIn(rest[0]);
      _show(await _get(token, 'user_roles', 'select=*&revoked_at=is.null'));
    case 'revoke-scope':
      await _revokeScope(actor: rest[0], target: rest[1], unitCode: rest[2]);
    case 'grant-scope':
      await _grantScope(
        actor: rest[0],
        target: rest[1],
        roleCode: rest[2],
        unitCode: rest[3],
      );
    case 'deactivate':
      final token = await _signIn(rest[0]);
      _show(
        await _rpc(token, 'user_deactivate', {
          'p_user_id': await _userId(token, rest[1]),
        }),
      );
    case 'reactivate':
      final token = await _signIn(rest[0]);
      _show(
        await _rpc(token, 'user_reactivate', {
          'p_user_id': await _userId(token, rest[1]),
        }),
      );
    case 'rename':
      final token = await _signIn(rest[0]);
      _show(
        await _rpc(token, 'master_rename', {
          'p_entity_type': rest[1],
          'p_entity_id': rest[2],
          'p_name': rest[3],
          'p_base_row_version': int.parse(rest[4]),
        }),
      );
    case 'masters':
      final token = await _signIn(rest[0]);
      for (final table in [
        'business_units',
        'departments',
        'sections',
        'expense_categories',
        'revenue_categories',
        'vendors',
        'revenue_tax_rates',
        'payment_methods',
      ]) {
        final rows = await _get(token, table, 'select=id') as List<dynamic>;
        stdout.writeln('$table: ${rows.length}');
      }
    default:
      stderr.writeln('unknown command: $command');
      exit(64);
  }
}

Future<void> _revokeScope({
  required String actor,
  required String target,
  required String unitCode,
}) async {
  final token = await _signIn(actor);
  final grantId = await _grantIdFor(token, target, unitCode);
  _show(await _rpc(token, 'user_role_revoke', {'p_grant_id': grantId}));
}

Future<void> _grantScope({
  required String actor,
  required String target,
  required String roleCode,
  required String unitCode,
}) async {
  final token = await _signIn(actor);
  final unit = await _unitId(token, unitCode);
  _show(
    await _rpc(token, 'user_role_grant', {
      'p_user_id': await _userId(token, target),
      'p_role_code': roleCode,
      'p_business_unit_id': unit,
    }),
  );
}

Future<String> _grantIdFor(String token, String email, String unitCode) async {
  final userId = await _userId(token, email);
  final unitId = await _unitId(token, unitCode);
  final rows =
      await _get(
            token,
            'user_roles',
            'select=id&user_id=eq.$userId&business_unit_id=eq.$unitId&revoked_at=is.null',
          )
          as List<dynamic>;
  if (rows.isEmpty) {
    stderr.writeln('no live grant for $email on $unitCode');
    exit(1);
  }
  return (rows.first as Map<String, dynamic>)['id'] as String;
}

Future<String> _userId(String token, String email) async {
  final rows =
      await _get(token, 'profiles', 'select=id&email=eq.$email')
          as List<dynamic>;
  if (rows.isEmpty) {
    stderr.writeln('no profile for $email');
    exit(1);
  }
  return (rows.first as Map<String, dynamic>)['id'] as String;
}

Future<String> _unitId(String token, String code) async {
  final rows =
      await _get(token, 'business_units', 'select=id&code=eq.$code')
          as List<dynamic>;
  if (rows.isEmpty) {
    stderr.writeln('no business unit $code visible to this actor');
    exit(1);
  }
  return (rows.first as Map<String, dynamic>)['id'] as String;
}

/// Signs in and returns the access token. The password is read from the git-ignored
/// identities file and is never printed, logged or passed on a command line.
Future<String> _signIn(String email) async {
  final entry = _identities[email] as Map<String, dynamic>?;
  if (entry == null) {
    stderr.writeln('no development identity for $email');
    exit(69);
  }
  final body = await _post('/auth/v1/token?grant_type=password', {
    'email': email,
    'password': entry['password'],
  }, null);
  final token = (body as Map<String, dynamic>)['access_token'] as String?;
  if (token == null) {
    stderr.writeln('sign-in refused for $email');
    exit(1);
  }
  return token;
}

Future<Object?> _rpc(String token, String name, Map<String, Object?> args) =>
    _post('/rest/v1/rpc/$name', args, token);

Future<Object?> _get(String token, String table, String query) async {
  final uri = Uri.parse('${_config['SUPABASE_URL']}/rest/v1/$table?$query');
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers
      ..set('apikey', _config['SUPABASE_ANON_KEY'] as String)
      ..set('Authorization', 'Bearer $token');
    final response = await request.close();
    return jsonDecode(await response.transform(utf8.decoder).join());
  } finally {
    client.close();
  }
}

Future<Object?> _post(
  String path,
  Map<String, Object?> body,
  String? token,
) async {
  final uri = Uri.parse('${_config['SUPABASE_URL']}$path');
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers
      ..set('apikey', _config['SUPABASE_ANON_KEY'] as String)
      ..set('Content-Type', 'application/json');
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      stderr.writeln('HTTP ${response.statusCode}: $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  } finally {
    client.close();
  }
}

void _show(Object? value) =>
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
