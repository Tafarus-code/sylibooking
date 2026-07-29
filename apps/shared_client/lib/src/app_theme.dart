import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's own look, before any establishment preset is layered on top.
///
/// Mirrors the `base` block of `design/theme_presets.json`; a test compares the
/// two. Named after the Ember house style: deepwood, ivory, ember.
class SylibookingTokens {
  const SylibookingTokens._();

  static const deepwood = Color(0xFF12281F);
  static const deepwoodSoft = Color(0xFF1D3A2D);
  static const ivory = Color(0xFFF7F3EC);
  static const ivoryDim = Color(0xFFE8E0D3);
  static const ember = Color(0xFFB4551C);
  static const emberBright = Color(0xFFD9722F);
  static const onEmber = Color(0xFFFFFFFF);
  static const onDeepwood = Color(0xFFF7F3EC);
  static const onIvory = Color(0xFF12281F);

  static const displayFont = 'Fraunces';
  static const bodyFont = 'Manrope';
  static const monoFont = 'IBM Plex Mono';
}

/// Display faces carry headlines and titles; the body face carries anything
/// read at length. Split out so both apps get the same pairing and the
/// establishment scope can re-apply the same shape with different families.
TextTheme sylibookingTextTheme(TextTheme base) {
  final body = GoogleFonts.getTextTheme(SylibookingTokens.bodyFont, base);
  final display = GoogleFonts.getTextTheme(SylibookingTokens.displayFont, base);

  return body.copyWith(
    displayLarge: display.displayLarge,
    displayMedium: display.displayMedium,
    displaySmall: display.displaySmall,
    headlineLarge: display.headlineLarge,
    headlineMedium: display.headlineMedium,
    headlineSmall: display.headlineSmall,
    titleLarge: display.titleLarge,
  );
}

/// The colour half of the app theme, pure so it can be asserted without a
/// font stack — the same split as `colorSchemeForPreset`.
ColorScheme sylibookingColorScheme() => const ColorScheme.light(
      primary: SylibookingTokens.ember,
      onPrimary: SylibookingTokens.onEmber,
      primaryContainer: SylibookingTokens.deepwood,
      onPrimaryContainer: SylibookingTokens.onDeepwood,
      secondary: SylibookingTokens.deepwood,
      onSecondary: SylibookingTokens.onDeepwood,
      secondaryContainer: SylibookingTokens.deepwoodSoft,
      onSecondaryContainer: SylibookingTokens.onDeepwood,
      tertiary: SylibookingTokens.emberBright,
      onTertiary: SylibookingTokens.onEmber,
      tertiaryContainer: SylibookingTokens.ivoryDim,
      onTertiaryContainer: SylibookingTokens.onIvory,
      surface: SylibookingTokens.ivory,
      onSurface: SylibookingTokens.onIvory,
      surfaceContainerHighest: SylibookingTokens.ivoryDim,
      onSurfaceVariant: Color(0xFF4A5B51),
      // 3.08:1 against ivory. The lighter grey-green this replaced measured
      // 2.67:1, under the 3:1 AA floor for a non-text boundary — and the
      // outlined filter chips are nothing but a boundary.
      outline: Color(0xFF7F8F85),
      outlineVariant: SylibookingTokens.ivoryDim,
      error: Color(0xFF9A2B2B),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF7DEDE),
      onErrorContainer: Color(0xFF5A1414),
    );

/// The app-wide theme. Both apps use this so the chrome is one house style.
///
/// Establishment branding is layered over the top of this by
/// `EstablishmentThemeScope`, and only on the screens that belong to a venue.
ThemeData sylibookingAppTheme() {
  final scheme = sylibookingColorScheme();
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    textTheme: sylibookingTextTheme(base.textTheme),
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      elevation: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      side: BorderSide(color: scheme.outline),
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
