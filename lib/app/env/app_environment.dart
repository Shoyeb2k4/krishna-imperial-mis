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
  /// False throughout Phase 1 by design: no Supabase project exists yet, and the app
  /// is built to run fully offline regardless. Local entry, local storage and local
  /// reporting must never depend on this being true.
  bool get hasBackend => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Guard against the one mistake that must never ship: a service-role key compiled
  /// into a client binary. Supabase service-role JWTs carry this role claim.
  bool get looksLikeServiceRoleKey => supabaseAnonKey.contains('service_role');

  @override
  String toString() =>
      'AppConfig(${flavor.name}, backend: ${hasBackend ? 'configured' : 'none'})';
}
