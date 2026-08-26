/// Route paths, in one place.
///
/// Android and Windows are genuinely different products sharing a domain, so they
/// expose different navigation surfaces (master spec §18, §19). The Windows UI is never
/// the mobile UI stretched, and the mobile UI is never the Windows UI shrunk.
library;

abstract final class AppRoutes {
  // ── Android (phone) ───────────────────────────────────────────────────────
  static const String home = '/home';
  static const String transactions = '/transactions';
  static const String reports = '/reports';
  static const String more = '/more';

  /// The central [ + ] action. A fast sheet, not a navigation branch — adding an
  /// expense must never cost the user their place in the app.
  static const String quickAdd = '/quick-add';

  // ── Windows (desktop) ─────────────────────────────────────────────────────
  static const String overview = '/overview';
  static const String analytics = '/analytics';
  static const String masters = '/masters';
  static const String administration = '/administration';

  // ── Shared ────────────────────────────────────────────────────────────────
  static const String signIn = '/sign-in';
}
