/// Design tokens — the single source of every colour, size and spacing value.
///
/// No screen, widget or export may hard-code a colour or a font size
/// (docs/DECISIONS.md D-012). Material 3 is a technical substrate only; the identity
/// comes from these tokens.
///
/// Direction (master spec §20): premium hospitality and serious financial software.
/// Off-white paper surfaces, charcoal ink, a restrained brass accent, hairline rules,
/// deliberate spacing, tabular figures wherever money appears, shadows barely present.
/// Deliberately **not** a neon fintech app, a gradient SaaS dashboard, or a page of
/// rounded stat cards.
library;

import 'package:flutter/widgets.dart';

/// Colour tokens. Semantic names only — no widget refers to "the green one".
abstract final class AppColors {
  // ── Surfaces: warm paper, not clinical white ──────────────────────────────
  static const Color paper = Color(0xFFFAF7F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3EFE8);
  static const Color surfaceSunken = Color(0xFFEDE8DF);

  // ── Ink ───────────────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF1F1D1A);
  static const Color inkMuted = Color(0xFF5C574F);
  static const Color inkFaint = Color(0xFF8A8378);
  static const Color inkInverse = Color(0xFFFBF9F5);

  // ── Rules and borders: hairlines, never heavy boxes ───────────────────────
  static const Color hairline = Color(0xFFE3DCD1);
  static const Color hairlineStrong = Color(0xFFCFC5B5);

  // ── Accent: brass. Used sparingly, for emphasis and never for decoration ──
  static const Color brass = Color(0xFFA8802C);
  static const Color brassMuted = Color(0xFFC9A75A);
  static const Color brassWash = Color(0xFFF6EEDC);

  // ── Semantic financial states ─────────────────────────────────────────────
  // Never used alone to convey profit or loss: a sign, symbol or label always
  // accompanies them (master spec §20).
  static const Color positive = Color(0xFF1E6B4F);
  static const Color negative = Color(0xFF9B2C1F);
  static const Color caution = Color(0xFF8A6A17);
  static const Color neutral = Color(0xFF5C574F);

  // ── Sync state ────────────────────────────────────────────────────────────
  static const Color syncSynced = Color(0xFF1E6B4F);
  static const Color syncPending = Color(0xFF8A6A17);
  static const Color syncFailed = Color(0xFF9B2C1F);
  static const Color syncConflict = Color(0xFF7A3E9D);
}

/// Spacing scale. A 4pt grid; every gap in the app is one of these.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii. Restrained — this is financial software, not a toy.
abstract final class AppRadius {
  static const Radius small = Radius.circular(3);
  static const Radius medium = Radius.circular(5);
  static const Radius large = Radius.circular(8);

  static const BorderRadius allSmall = BorderRadius.all(small);
  static const BorderRadius allMedium = BorderRadius.all(medium);
  static const BorderRadius allLarge = BorderRadius.all(large);
}

/// Elevation. Almost flat by design; separation comes from hairlines and spacing.
abstract final class AppElevation {
  static const double flat = 0;
  static const double raised = 1;
  static const double overlay = 6;

  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x0F1F1D1A), blurRadius: 3, offset: Offset(0, 1)),
  ];
}

/// Two density scales, one component set.
///
/// Android is a touch device used at speed on a rooftop; Windows is a finance
/// workstation showing dense tables. The difference is token values, never a second
/// implementation of the same component.
enum AppDensity {
  comfortable(
    rowHeight: 52,
    controlHeight: 48,
    pagePadding: AppSpacing.lg,
    cellPadding: AppSpacing.md,
    minTapTarget: 48,
  ),
  compact(
    rowHeight: 34,
    controlHeight: 32,
    pagePadding: AppSpacing.xl,
    cellPadding: AppSpacing.sm,
    minTapTarget: 28,
  );

  const AppDensity({
    required this.rowHeight,
    required this.controlHeight,
    required this.pagePadding,
    required this.cellPadding,
    required this.minTapTarget,
  });

  final double rowHeight;
  final double controlHeight;
  final double pagePadding;
  final double cellPadding;
  final double minTapTarget;
}

/// Type scale.
///
/// Phase 1 uses the platform text face. A licensed display serif and text face are to
/// be chosen with the owner and **bundled as assets** — never network-loaded — so both
/// apps render identically offline (docs/ARCHITECTURE.md §7). Until then the scale,
/// weights and figure treatment below are already fixed, so swapping the family in is a
/// one-line change rather than a redesign.
abstract final class AppTypography {
  /// Tabular figures: every digit occupies the same width, so columns of money align
  /// and a changing total does not make the row twitch. Mandatory anywhere a number
  /// appears in a table or metric.
  static const List<FontFeature> tabular = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  static const TextStyle heading = TextStyle(
    fontSize: 21,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  static const TextStyle subheading = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  /// Small, wide-tracked, uppercase. Used for table headers and section eyebrows.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.inkFaint,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: AppColors.ink,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: AppColors.inkMuted,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.35,
    color: AppColors.inkMuted,
  );

  /// The headline number on a metric block.
  static const TextStyle metric = TextStyle(
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.ink,
    fontFeatures: tabular,
  );

  /// Money inside a table cell.
  static const TextStyle money = TextStyle(
    fontSize: 14,
    height: 1.35,
    color: AppColors.ink,
    fontFeatures: tabular,
  );

  static const TextStyle moneyStrong = TextStyle(
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    fontFeatures: tabular,
  );
}
