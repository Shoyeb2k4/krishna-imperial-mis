// secret-scan-exempt: names the key prefixes it exists to reject.
/// Deciding whether a configured Supabase key is safe to compile into a client binary.
///
/// This exists because the obvious check is wrong. A Supabase service-role key is a JWT:
/// the string a developer pastes is `eyJhbGciOi....<base64url payload>....<signature>`,
/// and the words `service_role` appear **only inside the base64 payload**. A substring
/// search for `service_role` on the raw key therefore matches nothing and waves the most
/// dangerous possible mistake straight through. The payload has to be decoded.
///
/// Two key generations are in circulation and both have a privileged twin:
///
/// | Generation | Safe in a client       | Never in a client   |
/// |---|---|---|
/// | Legacy JWT | `"role":"anon"`        | `"role":"service_role"` |
/// | Modern     | `sb_publishable_…`     | `sb_secret_…`           |
///
/// The stance is **fail closed**: anything not positively recognised as a publishable or
/// anon key is refused. A new key format Supabase invents later will stop the app with a
/// clear message, which is the right failure — far better than shipping an unclassified
/// credential to two platforms because it happened not to match a deny-list.
///
/// Nothing here ever returns, logs or embeds the key material itself. Messages describe
/// the *kind* of key found, never its value (`docs/ARCHITECTURE.md` §8.1, D-022).
library;

import 'dart:convert';

/// What the configured key turned out to be.
enum SupabaseKeyKind {
  /// No key supplied at all. Not an error — the app runs fully offline (D-020).
  absent,

  /// Modern `sb_publishable_…`. Safe to ship.
  publishable,

  /// Legacy JWT carrying `"role":"anon"`. Safe to ship.
  legacyAnon,

  /// Modern `sb_secret_…`. A privileged credential. Must never reach a client.
  secret,

  /// Legacy JWT carrying `"role":"service_role"`. Bypasses RLS entirely.
  serviceRole,

  /// A Postgres connection string — carries the database password in plain text.
  databaseUrl,

  /// Recognisably a JWT, but with a role this application does not accept.
  unknownJwtRole,

  /// Not recognisable as a client key of any supported form.
  unrecognised;

  /// Whether shipping this in an Android or Windows binary would be a security incident.
  bool get isPrivileged => switch (this) {
    SupabaseKeyKind.secret ||
    SupabaseKeyKind.serviceRole ||
    SupabaseKeyKind.databaseUrl => true,
    _ => false,
  };

  /// Whether this key may be compiled into a client binary.
  bool get isClientSafe =>
      this == SupabaseKeyKind.publishable || this == SupabaseKeyKind.legacyAnon;
}

abstract final class SupabaseKeyInspector {
  /// Classifies [key] without ever reproducing it.
  static SupabaseKeyKind classify(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return SupabaseKeyKind.absent;

    if (trimmed.startsWith('postgres://') ||
        trimmed.startsWith('postgresql://')) {
      return SupabaseKeyKind.databaseUrl;
    }
    if (trimmed.startsWith('sb_secret_')) return SupabaseKeyKind.secret;
    if (trimmed.startsWith('sb_publishable_')) {
      return SupabaseKeyKind.publishable;
    }

    final role = _jwtRole(trimmed);
    if (role != null) {
      return switch (role) {
        'anon' => SupabaseKeyKind.legacyAnon,
        'service_role' => SupabaseKeyKind.serviceRole,
        _ => SupabaseKeyKind.unknownJwtRole,
      };
    }

    // A last-resort catch for a raw payload or an environment line pasted whole. The
    // decoder above is the real check; this only exists so an odd paste still trips.
    if (trimmed.contains('service_role')) return SupabaseKeyKind.serviceRole;

    return SupabaseKeyKind.unrecognised;
  }

  /// The `role` claim of a JWT, or null when [value] is not a decodable JWT.
  static String? _jwtRole(String value) {
    final segments = value.split('.');
    if (segments.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(segments[1])),
      );
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final role = decoded['role'];
      return role is String ? role : null;
    } on Object {
      // Malformed base64 or JSON: not a JWT we can vouch for. Fall through to
      // `unrecognised`, which is refused anyway.
      return null;
    }
  }

  /// Plain-language explanation for a key that must not ship, or null when it may.
  ///
  /// Deliberately actionable, and deliberately silent about the value itself.
  static String? refusalFor(SupabaseKeyKind kind) => switch (kind) {
    SupabaseKeyKind.absent ||
    SupabaseKeyKind.publishable ||
    SupabaseKeyKind.legacyAnon => null,
    SupabaseKeyKind.serviceRole =>
      'the configured SUPABASE_ANON_KEY is a service-role key. It bypasses Row Level '
          'Security completely and must never exist on a client machine. Replace it with '
          'the publishable/anon key from Project Settings -> API Keys.',
    SupabaseKeyKind.secret =>
      'the configured SUPABASE_ANON_KEY is a secret key (sb_secret_...). Secret keys are '
          'server-side only. Use the publishable key (sb_publishable_...) instead.',
    SupabaseKeyKind.databaseUrl =>
      'the configured SUPABASE_ANON_KEY is a Postgres connection string, which contains '
          'the database password. It must never appear in application configuration.',
    SupabaseKeyKind.unknownJwtRole =>
      'the configured SUPABASE_ANON_KEY is a JWT whose role is neither "anon" nor a '
          'publishable key. Only a publishable/anon key may ship in a client binary.',
    SupabaseKeyKind.unrecognised =>
      'the configured SUPABASE_ANON_KEY is not recognisable as a Supabase publishable or '
          'anon key. Configuration is refused rather than guessed at, because an '
          'unclassified credential compiled into an app cannot be taken back.',
  };
}
