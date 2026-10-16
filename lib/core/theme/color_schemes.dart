import 'package:flutter/material.dart';

class AppColorSchemes {
  // ChatGPT / Claude inspired sleek charcoal dark theme
  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF10A37A), // Restrained emerald / OpenAI green
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF1E2E28),
    onPrimaryContainer: Color(0xFFA7F3D0),
    secondary: Color(0xFFA1A1AA), // Zinc 400
    onSecondary: Color(0xFF18181B),
    secondaryContainer: Color(0xFF27272A),
    onSecondaryContainer: Color(0xFFE4E4E7),
    tertiary: Color(0xFF34D399),
    onTertiary: Color(0xFF064E3B),
    tertiaryContainer: Color(0xFF064E3B),
    onTertiaryContainer: Color(0xFFA7F3D0),
    error: Color(0xFFEF4444),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFF451A1A),
    onErrorContainer: Color(0xFFFCA5A5),
    surface: Color(0xFF18181B), // Zinc 900
    onSurface: Color(0xFFF4F4F5), // Zinc 100
    surfaceContainerLowest: Color(0xFF09090B), // Zinc 950
    surfaceContainerLow: Color(0xFF121214),
    surfaceContainer: Color(0xFF202024), // Neutral dark card
    surfaceContainerHigh: Color(0xFF27272A), // Zinc 800
    surfaceContainerHighest: Color(0xFF323238),
    outline: Color(0xFF71717A), // Zinc 500
    outlineVariant: Color(0xFF2E2E33), // Subtle 1px borders
  );

  // Clean, high-contrast, distraction-free light theme
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0D9488), // Restrained teal/emerald
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE6F4EA),
    onPrimaryContainer: Color(0xFF065F46),
    secondary: Color(0xFF71717A), // Zinc 500
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF4F4F5),
    onSecondaryContainer: Color(0xFF18181B),
    tertiary: Color(0xFF059669),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFECFDF5),
    onTertiaryContainer: Color(0xFF065F46),
    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF991B1B),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF18181B), // Zinc 900
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF9F9FB), // Subtle off-white
    surfaceContainer: Color(0xFFF4F4F5), // Zinc 100
    surfaceContainerHigh: Color(0xFFE4E4E7), // Zinc 200
    surfaceContainerHighest: Color(0xFFD4D4D8), // Zinc 300
    outline: Color(0xFFA1A1AA),
    outlineVariant: Color(0xFFE4E4E7), // Subtle border
  );
}
