// Preflight for an environment file, before it is ever compiled into a build.
//
// Reports what the configuration *is* — never what it contains. No value from the file
// is printed, logged, or returned, because the whole point of a check like this is that
// it can be run and pasted anywhere without leaking the thing it inspected.
//
//   dart run tool/check_config.dart config/dev.json
import 'dart:convert';
import 'dart:io';

import 'package:krishna_mis/app/env/app_environment.dart';

Future<int> main(List<String> args) async {
  final path = args.isEmpty ? 'config/dev.json' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln(
      '$path does not exist. Copy the matching .example.json and fill it in.',
    );
    return exitCode = 1;
  }

  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final declared = json['APP_FLAVOR'] as String?;
  // Checked as a release build would be: a file that names no environment, or one this
  // code does not know, is refused here rather than at somebody's first launch (D-346).
  final config = AppConfig(
    flavor: AppFlavor.fromName(declared ?? ''),
    supabaseUrl: (json['SUPABASE_URL'] as String?) ?? '',
    supabaseAnonKey: (json['SUPABASE_ANON_KEY'] as String?) ?? '',
    declaredFlavor: declared,
    releaseBuild: true,
  );

  stdout.writeln('file      : $path');
  stdout.writeln('flavor    : ${config.flavor.displayName}');
  stdout.writeln(
    'project   : ${config.projectRef ?? 'not derivable from the URL'}',
  );
  stdout.writeln('key kind  : ${config.keyKind.name}');
  stdout.writeln('client-safe: ${config.keyKind.isClientSafe}');

  final problem = config.problem;
  if (problem == null) {
    stdout.writeln(
      config.hasBackend
          ? 'RESULT    : usable. The app would start and connect.'
          : 'RESULT    : empty. The app would start and run fully offline.',
    );
    return 0;
  }

  stderr.writeln('RESULT    : REFUSED — the app would stop at start-up.');
  stderr.writeln('            ${problem.summary}');
  stderr.writeln('            ${problem.detail}');
  return exitCode = 1;
}
