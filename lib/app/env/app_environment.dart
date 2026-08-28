/// Compile-time environment configuration.
///
/// Development, staging and production are three isolated backends
/// (docs/ARCHITECTURE.md §3). Values arrive through `--dart-define-from-file`, which
/// means they are compiled in — so **only** the project URL and the publishable/anon
/// key may ever appear here. The service-role key never exists on a client machine,
/// never in this repository, and never in a shipped artefact.
///
/// ```
/// flutter run    --flavor dev  --dart-define-from-file=config/dev.json
/// flutter build apk --release --flavor prod --dart-define-from-file=config/prod.json
/// ```
library;

import 'package:krishna_mis/app/env/supabase_key_inspection.dart';
import 'package:meta/meta.dart';

enum AppFlavor {
  dev,
  staging,
  prod;

  static AppFlavor fromName(String value) => AppFlavor.values.firstWhere(
    (flavor) => flavor.name == value,
    orElse: () => AppFlavor.dev,
  );

  String get displayName => switch (this) {
    AppFlavor.dev => 'Development',
    AppFlavor.staging => 'Staging',
    AppFlavor.prod => 'Production',
  };

  /// Whether the environment badge is shown in the UI. Production shows nothing; the
  /// other two are marked so nobody mistakes test data for real figures.
  bool get showsEnvironmentBadge => this != AppFlavor.prod;
}

/// Why a supplied configuration was refused.
///
/// Every one of these stops start-up. A misconfigured backend is not something to
/// discover later from a confusing network error.
@immutable
final class ConfigurationProblem {
  const ConfigurationProblem(this.summary, this.detail);

  /// One line, for a log or a dialog title.
  final String summary;

  /// What to actually do about it. Never contains key material.
  final String detail;

  @override
  String toString() => '$summary $detail';
}

final class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  /// Reads the compiled-in defines. Absent values yield empty strings rather than
  /// throwing, so the app still starts and can say *why* it is not configured.
  factory AppConfig.fromEnvironment() => const AppConfig(
    flavor: AppFlavor.dev,
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
  )._withFlavor(String.fromEnvironment('APP_FLAVOR', defaultValue: 'dev'));

  AppConfig _withFlavor(String name) => AppConfig(
    flavor: AppFlavor.fromName(name),
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
  );

  final AppFlavor flavor;
  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Whether a backend has been supplied.
  ///
  /// The app is built to run fully offline regardless. Local entry, local storage and
  /// local reporting must never depend on this being true (D-020).
  bool get hasBackend =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// What kind of key was configured. Classification, never the value.
  SupabaseKeyKind get keyKind => SupabaseKeyInspector.classify(supabaseAnonKey);

  /// The one mistake that must never ship: a privileged credential in a client binary.
  ///
  /// Named for the historical case but true of every privileged form — a modern
  /// `sb_secret_…` key and a Postgres connection string are just as fatal.
  bool get looksLikeServiceRoleKey => keyKind.isPrivileged;

  /// The project reference (`abcdefghijklmnop` in `https://abcdefghijklmnop.supabase.co`),
  /// or null when the URL is absent or not of that shape. Diagnostics only.
  String? get projectRef {
    final host = Uri.tryParse(supabaseUrl.trim())?.host ?? '';
    if (!host.endsWith('.supabase.co')) return null;
    final label = host.split('.').first;
    return label.isEmpty || label == 'db' ? null : label;
  }

  /// The reason this configuration cannot be used, or null when it is usable.
  ///
  /// A completely empty configuration is *not* a problem: it means "no backend yet",
  /// which is a supported, fully functional offline state. A **partial** or **unsafe**
  /// configuration is a problem, because it will fail later and less clearly.
  ConfigurationProblem? get problem {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();
    if (url.isEmpty && key.isEmpty) return null;

    if (url.isEmpty || key.isEmpty) {
      return const ConfigurationProblem(
        'The backend configuration is incomplete.',
        'Both SUPABASE_URL and SUPABASE_ANON_KEY must be set, or both left empty to run '
            'offline. See config/README.md.',
      );
    }

    final refusal = SupabaseKeyInspector.refusalFor(keyKind);
    if (refusal != null) {
      return ConfigurationProblem(
        'Refusing to start: $refusal',
        'No privileged Supabase credential may be compiled into an Android or Windows '
            'binary (docs/DECISIONS.md D-022).',
      );
    }

    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      return const ConfigurationProblem(
        'SUPABASE_URL is not a valid https project URL.',
        'It should look like https://<project-ref>.supabase.co — no path, no query, no '
            'credentials.',
      );
    }
    if (parsed.userInfo.isNotEmpty) {
      return const ConfigurationProblem(
        'SUPABASE_URL carries embedded credentials.',
        'Remove the user:password@ portion. The project URL is not a database URL.',
      );
    }
    if (parsed.host.startsWith('db.')) {
      return const ConfigurationProblem(
        'SUPABASE_URL points at the database host, not the API.',
        'Use https://<project-ref>.supabase.co (Project Settings -> Data API), not '
            'db.<project-ref>.supabase.co, which is the direct Postgres connection.',
      );
    }
    return null;
  }

  /// Guards the one rule that has no exception: production never runs against a
  /// development project, and development never runs against production.
  bool get isDevelopment => flavor == AppFlavor.dev;

  @override
  String toString() =>
      'AppConfig(${flavor.name}, backend: ${hasBackend ? 'configured' : 'none'}, '
      'key: ${keyKind.name})';
}
