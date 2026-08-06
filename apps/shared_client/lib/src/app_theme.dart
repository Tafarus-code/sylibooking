import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's own look, before any establishment preset is layered on top.
///
/// Mirrors the `base` block of `design/theme_presets.json`; a test compares the
/// two. Named after the Ember house style: deepwood, ivory, ember.
class SylibookingTokens {
  const SylibookingTokens._();

  static const deepwood = Color(0xFF12271F);
  static const deepwoodSoft = Color(0xFF1B362A);
  static const ivory = Color(0xFFF7F1E4);
  static const ivoryDim = Color(0xFFCFC7B3);
  static const ember = Color(0xFFD98E2B);
  static const emberBright = Color(0xFFE8A94F);
  static const onEmber = Color(0xFF3B2508);
  static const onDeepwood = Color(0xFFF7F1E4);
  static const onIvory = Color(0xFF1B1B18);

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

/// Money, set in the mono face.
///
/// Prices are read as figures rather than as words: a column of them should
/// line up, and 150000.00 next to 15000.00 should differ visibly in width
/// rather than only in a digit. The mono face is the third font the design
/// tokens name, and this is what it is for.
TextStyle sylibookingPriceStyle(BuildContext context, {double? fontSize}) {
  final theme = Theme.of(context);
  return GoogleFonts.getFont(
    SylibookingTokens.monoFont,
    textStyle: theme.textTheme.titleMedium,
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    // Deliberately not coloured here: on a cart bar it wants onSurface, on a
    // menu row the accent. The caller decides; the face is what is shared.
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
