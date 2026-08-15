/// The app-wide baseline themes — one per app.
///
/// **These are not the establishment presets, and the names collide on
/// purpose-adjacent ground, so read this once.** There are two theming
/// systems in this codebase and they answer different questions:
///
/// * A **baseline** is what an app looks like everywhere — its chrome, its
///   empty states, its settings screens. The customer app's baseline is the
///   palette called *Bissap Bloom*; the merchant app's is *Indigo Ledger*.
///   Neither is chosen by anybody at runtime; they are the products' faces.
/// * An **establishment preset** is what one merchant picks for their own
///   venue's pages, from a fixed set of five. Two of those five happen to be
///   called "Bissap" and "Indigo Soir" — different values, different system,
///   and they live in `establishment_theme.dart` as
///   [EstablishmentThemePreset].
///
/// So: `CustomerBaselineTokens.bissap` is the customer app's primary accent,
/// and the preset with key `bissap` is a hibiscus red one venue may wear.
/// Nothing in this file is named plain `Bissap` or `Indigo` on its own, and
/// nothing in the preset file is named `Baseline`. If you are reaching for a
/// colour and the word "baseline" is not in the name, you are in the venue
/// branding system rather than the app's own look.
///
/// Both mirror the `app_baselines` block of `design/theme_presets.json`; a
/// test compares them value for value so the two cannot drift.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The customer app's own look. Palette: Bissap Bloom.
class CustomerBaselineTokens {
  const CustomerBaselineTokens._();

  /// The name of the palette, for documentation and design review. Never a
  /// runtime identifier — see the library comment for why.
  static const paletteName = 'Bissap Bloom';

  /// Deep base. App bars, the dark band at the top of a phone held at night.
  static const aubergine = Color(0xFF3B1230);

  /// Primary accent: CTAs, active states, the filled favourite heart.
  static const bissap = Color(0xFFD6296B);

  /// Secondary accent: stars and highlights.
  static const gold = Color(0xFFE8B23D);

  /// Mid-tone, for gradients and borders — and the one to reach for when an
  /// accent has to carry *small text* on a light surface. See the contrast
  /// note at the foot of this file.
  static const pruneClair = Color(0xFF7A2E5C);

  /// Light content surface: cards and sheets.
  static const blush = Color(0xFFFBF2EC);

  /// White, at 4.79:1 against [bissap]. [blush] measures 4.33:1 and is under
  /// the 4.5 floor for normal text, which is what a CTA label is.
  static const onBissap = Color(0xFFFFFFFF);
  static const onGold = aubergine;
  static const onPruneClair = blush;
  static const onAubergine = blush;
  static const onBlush = aubergine;

  static const displayFont = 'Playfair Display';
  static const bodyFont = 'Manrope';
  static const monoFont = 'IBM Plex Mono';
}

/// The merchant app's own look. Palette: Indigo Ledger.
class MerchantBaselineTokens {
  const MerchantBaselineTokens._();

  static const paletteName = 'Indigo Ledger';

  /// Deep base. The navigation rail, and the ground the whole tablet sits on.
  static const indigo = Color(0xFF1E2749);

  /// Primary accent: CTAs, the active rail item, the signature glow. Replaces
  /// ember in that role.
  static const copper = Color(0xFFC97C3D);

  /// Secondary accent: secondary buttons and the counterpoint glow. Replaces
  /// palm green in that role.
  static const slateBlue = Color(0xFF3D5A80);

  /// Tertiary, used sparingly — a third data point on a chart, and no more.
  static const sage = Color(0xFF7A9E6E);

  /// Light content surface: cards and field grids.
  static const parchment = Color(0xFFF5F1E8);

  /// **Not [indigo].** Indigo measures 4.46:1 against copper — under the 4.5
  /// floor for normal text, and copper is what carries button labels. This is
  /// the deepest stop of the merchant background gradient, so it is already a
  /// palette member rather than a colour invented to pass a test, and it
  /// measures 5.60:1.
  static const onCopper = Color(0xFF0E1428);
  static const onSlateBlue = parchment;
  static const onSage = indigo;
  static const onIndigo = parchment;
  static const onParchment = indigo;

  static const displayFont = 'Sora';
  static const bodyFont = 'Manrope';
  static const monoFont = 'IBM Plex Mono';
}

/// The colour half of the customer baseline, pure so it can be asserted
/// without a font stack — the same split the rest of the theming uses.
ColorScheme customerBaselineColorScheme() => const ColorScheme.light(
      primary: CustomerBaselineTokens.bissap,
      onPrimary: CustomerBaselineTokens.onBissap,
      primaryContainer: CustomerBaselineTokens.aubergine,
      onPrimaryContainer: CustomerBaselineTokens.onAubergine,
      secondary: CustomerBaselineTokens.gold,
      onSecondary: CustomerBaselineTokens.onGold,
      secondaryContainer: CustomerBaselineTokens.pruneClair,
      onSecondaryContainer: CustomerBaselineTokens.onPruneClair,
      tertiary: CustomerBaselineTokens.pruneClair,
      onTertiary: CustomerBaselineTokens.onPruneClair,
      surface: CustomerBaselineTokens.blush,
      onSurface: CustomerBaselineTokens.onBlush,
      // A shade off the surface, for a card that has to sit on a card.
      surfaceContainerHighest: Color(0xFFF2E4DC),
      // 5.85:1 on blush. Secondary copy is still copy.
      onSurfaceVariant: Color(0xFF6E5866),
      // 3.19:1 on blush, over the AA floor for a boundary — which is all an
      // outlined chip is.
      outline: Color(0xFF9A8290),
      outlineVariant: Color(0xFFE4D2D9),
      error: Color(0xFF9A2B2B),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF7DEDE),
      onErrorContainer: Color(0xFF5A1414),
    );

/// The colour half of the merchant baseline.
ColorScheme merchantBaselineColorScheme() => const ColorScheme.light(
      primary: MerchantBaselineTokens.copper,
      onPrimary: MerchantBaselineTokens.onCopper,
      primaryContainer: MerchantBaselineTokens.indigo,
      onPrimaryContainer: MerchantBaselineTokens.onIndigo,
      secondary: MerchantBaselineTokens.slateBlue,
      onSecondary: MerchantBaselineTokens.onSlateBlue,
      secondaryContainer: MerchantBaselineTokens.indigo,
      onSecondaryContainer: MerchantBaselineTokens.onIndigo,
      tertiary: MerchantBaselineTokens.sage,
      onTertiary: MerchantBaselineTokens.onSage,
      surface: MerchantBaselineTokens.parchment,
      onSurface: MerchantBaselineTokens.onParchment,
      surfaceContainerHighest: Color(0xFFE7E1D3),
      // 5.65:1 on parchment.
      onSurfaceVariant: Color(0xFF5A5F6E),
      // 3.06:1 on parchment. The half-shade lighter this replaced measured
      // 2.90:1, under the 3:1 floor — the same trap the house outline fell
      // into once already.
      outline: Color(0xFF868A96),
      outlineVariant: Color(0xFFD8D3C4),
      error: Color(0xFF9A2B2B),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF7DEDE),
      onErrorContainer: Color(0xFF5A1414),
    );

/// Display faces carry headlines and titles; the body face carries anything
/// read at length. The same shape as the house pairing, with each app's own
/// families.
TextTheme _baselineTextTheme(
  TextTheme base, {
  required String displayFont,
  required String bodyFont,
}) {
  final body = GoogleFonts.getTextTheme(bodyFont, base);
  final display = GoogleFonts.getTextTheme(displayFont, base);

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

ThemeData _baselineTheme({
  required ColorScheme scheme,
  required String displayFont,
  required String bodyFont,
  required Color appBarBackground,
  required Color appBarForeground,
  required Color railBackground,
  required Color railIndicator,
  required Color railSelected,
  required Color railUnselected,
}) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    textTheme: _baselineTextTheme(
      base.textTheme,
      displayFont: displayFont,
      bodyFont: bodyFont,
    ),
    // Deliberately transparent rather than the surface colour: the painted
    // canvas goes behind the Scaffold, and a solid scaffold would hide it.
    // Slices B and C put that canvas in; until then this reads as the
    // surface anyway, because nothing is painted behind it yet.
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: appBarBackground,
      foregroundColor: appBarForeground,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: appBarForeground),
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
    // The rail is the one piece of chrome the two apps style differently,
    // and it is styled here rather than in AdaptiveScaffold because they
    // share that widget. The merchant's rail is the deep base with the accent
    // on the active item, as the design document draws it; the customer's is
    // the ordinary light surface, since a customer only ever sees a rail on a
    // tablet and it is not the spine of their app.
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: railBackground,
      indicatorColor: railIndicator,
      selectedIconTheme: IconThemeData(color: railSelected),
      unselectedIconTheme: IconThemeData(color: railUnselected),
      selectedLabelTextStyle: TextStyle(
        color: railSelected,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: railUnselected),
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

/// The customer app's baseline theme. Palette: Bissap Bloom.
///
/// The app bar wears aubergine: it is the top of a phone held in one hand at
/// night, and the dark band is what makes the blush list below it read as the
/// content rather than as more chrome.
ThemeData customerBaselineTheme() => _baselineTheme(
      scheme: customerBaselineColorScheme(),
      displayFont: CustomerBaselineTokens.displayFont,
      bodyFont: CustomerBaselineTokens.bodyFont,
      appBarBackground: CustomerBaselineTokens.aubergine,
      appBarForeground: CustomerBaselineTokens.onAubergine,
      railBackground: CustomerBaselineTokens.blush,
      railIndicator: CustomerBaselineTokens.bissap,
      railSelected: CustomerBaselineTokens.onBissap,
      railUnselected: CustomerBaselineTokens.pruneClair,
    );

/// The merchant app's baseline theme. Palette: Indigo Ledger.
///
/// The header stays light: it sits beside a navigation rail that is already
/// indigo, and two dark bands meeting reads as a mistake rather than as a
/// frame.
ThemeData merchantBaselineTheme() => _baselineTheme(
      scheme: merchantBaselineColorScheme(),
      displayFont: MerchantBaselineTokens.displayFont,
      bodyFont: MerchantBaselineTokens.bodyFont,
      appBarBackground: MerchantBaselineTokens.parchment,
      appBarForeground: MerchantBaselineTokens.onParchment,
      // Indigo, with copper on the active item: the rail is the spine of the
      // merchant app, and the design document draws it as the one permanently
      // dark surface on the tablet.
      railBackground: MerchantBaselineTokens.indigo,
      railIndicator: MerchantBaselineTokens.copper,
      railSelected: MerchantBaselineTokens.onCopper,
      railUnselected: MerchantBaselineTokens.parchment,
    );

// Money is set by `sylibookingPriceStyle` in app_theme.dart, and stays
// there: it chooses the mono face and nothing else, both baselines name the
// same one, and it is already called from both apps. A baseline-flavoured
// copy of it would be two functions with one behaviour.

// ---------------------------------------------------------------------------
// Contrast notes, measured rather than assumed. Tests assert all of these.
//
// Two accents cannot carry small text on their own app's light surface, and
// both have a stand-in that can:
//
//   bissap on blush      4.33:1   fills and large text only → use pruneClair
//   pruneClair on blush  8.01:1
//   copper on parchment  2.90:1   fills only → use slateBlue
//   slateBlue on parchment 6.27:1
//
// This is why pruneClair and slateBlue are the secondary/tertiary roles in
// their schemes rather than decoration: they are the readable half of each
// palette, and a price or a link set in the primary accent would fail AA.
// ---------------------------------------------------------------------------
