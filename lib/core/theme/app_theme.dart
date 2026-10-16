import 'package:flutter/material.dart';

import 'color_schemes.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return _buildTheme(AppColorSchemes.lightColorScheme);
  }

  static ThemeData get darkTheme {
    return _buildTheme(AppColorSchemes.darkColorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        color: isDark
            ? colorScheme.surfaceContainer
            : colorScheme.surfaceContainerLowest,
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        backgroundColor: isDark
            ? colorScheme.surfaceContainer
            : colorScheme.surfaceContainerLowest,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(
            BorderSide(color: colorScheme.outlineVariant, width: 1),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainer
            : colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark
            ? colorScheme.surfaceContainerLowest
            : colorScheme.surfaceContainerLow,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(color: colorScheme.outline),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.outline,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? colorScheme.surfaceContainerLowest
            : colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
