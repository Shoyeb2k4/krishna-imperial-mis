/// Wires the design tokens into a Material 3 theme.
///
/// Material 3 supplies accessibility, focus handling and input behaviour. Everything
/// visible comes from [AppColors], [AppTypography] and the spacing scale — never from
/// M3's defaults (docs/DECISIONS.md D-012).
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

abstract final class AppTheme {
  /// [density] differs per platform: comfortable on Android, compact on Windows.
  static ThemeData build({required AppDensity density}) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.brass,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.brass,
          onPrimary: AppColors.inkInverse,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
          surfaceContainerLowest: AppColors.surface,
          surfaceContainerLow: AppColors.paper,
          surfaceContainer: AppColors.surfaceMuted,
          surfaceContainerHigh: AppColors.surfaceSunken,
          outline: AppColors.hairlineStrong,
          outlineVariant: AppColors.hairline,
          error: AppColors.negative,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.paper,
      visualDensity: density == AppDensity.compact
          ? VisualDensity.compact
          : VisualDensity.standard,
      splashFactory: density == AppDensity.compact
          ? NoSplash.splashFactory
          : InkRipple.splashFactory,
      textTheme: const TextTheme(
        displaySmall: AppTypography.display,
        headlineSmall: AppTypography.heading,
        titleMedium: AppTypography.subheading,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.caption,
        labelSmall: AppTypography.overline,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: AppElevation.flat,
        scrolledUnderElevation: AppElevation.flat,
        centerTitle: false,
        titleTextStyle: AppTypography.subheading,
        shape: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: AppElevation.flat,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allMedium,
          side: BorderSide(color: AppColors.hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: density == AppDensity.compact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: density == AppDensity.compact
              ? AppSpacing.sm
              : AppSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.allSmall,
          borderSide: BorderSide(color: AppColors.hairlineStrong),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.allSmall,
          borderSide: BorderSide(color: AppColors.hairlineStrong),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.allSmall,
          borderSide: BorderSide(color: AppColors.brass, width: 1.5),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.brassWash,
        elevation: AppElevation.flat,
        labelTextStyle: WidgetStatePropertyAll(AppTypography.caption),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surfaceMuted,
        indicatorColor: AppColors.brassWash,
        selectedLabelTextStyle: AppTypography.body,
        unselectedLabelTextStyle: AppTypography.bodyMuted,
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: density.cellPadding / 2,
        iconColor: AppColors.inkMuted,
      ),
    );
  }

  /// Android: touch-first, comfortable spacing.
  static ThemeData get mobile => build(density: AppDensity.comfortable);

  /// Windows: dense financial tables, keyboard and mouse.
  static ThemeData get desktop => build(density: AppDensity.compact);
}
