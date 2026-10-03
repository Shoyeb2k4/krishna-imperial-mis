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

  static AppFlavor fromName(String value) => tryParse(value) ?? AppFlavor.dev;

  /// The flavour named exactly [value], or null. A build that names an environment this
  /// code does not know is refused rather than quietly treated as development (Phase 9
  /// Slice 2, D-346).
  static AppFlavor? tryParse(String value) {
    for (final flavor in AppFlavor.values) {
      if (flavor.name == value) return flavor;
    }
    return null;
  }

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
    this.declaredFlavor,
    this.buildFlavor,
    this.releaseBuild = false,
  });

  /// Reads the compiled-in defines. Absent values yield empty strings rather than
  /// throwing, so the app still starts and can say *why* it is not configured.
  ///
  /// Every value here is fixed when the binary is built; none can be changed by somebody
  /// using the installed application. That is what makes [flavor] a trustworthy basis for
  /// choosing where local data lives (D-346).
  factory AppConfig.fromEnvironment() {
    const declared = String.fromEnvironment('APP_FLAVOR');
    // Set by the Flutter tool from the Android Gradle flavour (`--flavor prod`). Windows
    // has no flavours, so there it is always empty.
    const built = String.fromEnvironment('FLUTTER_APP_FLAVOR');
    return AppConfig(
      flavor: AppFlavor.fromName(declared),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      declaredFlavor: declared.isEmpty ? null : declared,
      buildFlavor: built.isEmpty ? null : built,
      releaseBuild: const bool.fromEnvironment('dart.vm.product'),
    );
  }

  final AppFlavor flavor;
  final String supabaseUrl;
  final String supabaseAnonKey;

  /// The `APP_FLAVOR` the configuration file named, or null when it named none. Kept apart
  /// from [flavor] so an unknown or missing name is refused, never defaulted (D-346).
  final String? declaredFlavor;

  /// The Android Gradle flavour the binary was built as, or null (Windows, host tests).
  final String? buildFlavor;

  /// Whether this is a release build (`dart.vm.product`).
  final bool releaseBuild;

  /// Supabase projects known not to be production. A production build pointed at one is
  /// refused: "production never runs against a development project" was otherwise a
  /// sentence with nothing behind it (D-346). A project reference is not a secret.
  static const Set<String> knownNonProductionProjectRefs = {
    'loratzmactetjbqolwri', // krishna-mis-dev
  };

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
  /// A completely empty configuration is *not* a problem outside production: it means
  /// "no backend yet", a supported, fully functional offline state for development and
  /// staging. A **partial** or **unsafe** configuration is a problem, because it will
  /// fail later and less clearly — and so is any production build that is not fully
  /// configured (D-346).
  ConfigurationProblem? get problem {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();

    // Which environment this binary is comes first: every later rule depends on it.
    final declared = declaredFlavor;
    if (declared != null && AppFlavor.tryParse(declared) == null) {
      return const ConfigurationProblem(
        'This build names an environment the application does not know.',
        'APP_FLAVOR must be dev, staging or prod. Rebuild with the matching '
            'config/<environment>.json.',
      );
    }
    final built = buildFlavor;
    if (built != null && built != flavor.name) {
      return const ConfigurationProblem(
        'This build and its configuration name different environments.',
        'The Android flavour and APP_FLAVOR must agree. Rebuild with --flavor and '
            '--dart-define-from-file naming the same environment.',
      );
    }
    if (releaseBuild && declared == null) {
      return const ConfigurationProblem(
        'This release build does not say which environment it belongs to.',
        'Rebuild with --dart-define-from-file=config/<environment>.json.',
      );
    }

    // Production has no offline mode. Without its backend it would seed demonstration
    // masters and look operational, which a production install must never do (D-346).
    if (flavor == AppFlavor.prod) {
      if (url.isEmpty || key.isEmpty) {
        return const ConfigurationProblem(
          'This production build has no backend configuration.',
          'Production cannot run offline or with demonstration data. Rebuild with the '
              'production configuration (docs/PRODUCTION_RUNBOOK.md).',
        );
      }
      if (knownNonProductionProjectRefs.contains(projectRef)) {
        return const ConfigurationProblem(
          'This production build is configured with a development backend.',
          'Production must use the production project. Rebuild with the production '
              'configuration.',
        );
      }
    }

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

  /// Whether this build is production, the one environment whose local data is kept apart
  /// from every other (D-346).
  bool get isProduction => flavor == AppFlavor.prod;

  /// Whether the shipped demonstration masters may be written: only with no backend, and
  /// never in production — which [problem] already refuses, stated again here so the seed
  /// call reads its own rule (D-052, D-346).
  bool get permitsOfflineSeed => !hasBackend && !isProduction;

  @override
  String toString() =>
      'AppConfig(${flavor.name}, backend: ${hasBackend ? 'configured' : 'none'}, '
      'key: ${keyKind.name})';
}
