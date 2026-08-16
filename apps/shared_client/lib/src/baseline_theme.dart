/// The app-wide baseline themes — one per app.
///
/// **These are not the establishment presets, so read this once.** There are
/// two theming systems here and they answer different questions:
///
/// * A **baseline** is what an app looks like everywhere — its chrome, its
///   empty states, its settings screens. The customer app's is *Ember Vivid*,
///   the merchant app's is *Indigo Ledger*. Neither is chosen by anybody at
///   runtime; they are the products' faces.
/// * An **establishment preset** is what one merchant picks for their own
///   venue's pages, from a fixed set of five. They live in
///   `establishment_theme.dart` as [EstablishmentThemePreset].
///
/// The names still shade into each other in two places, both harmless once
/// seen. The preset keyed `ember` carries the same accent as the customer
/// baseline, because the house colour is also offered to venues; the preset
/// keyed `indigo_soir` is a *different* indigo from the merchant baseline's.
/// The rule that keeps them apart is naming: everything here says
/// `Baseline`, nothing in the preset file does.
///
/// ## The pairing rule, which is the point of this file
///
/// Every colour that text is painted on has its foreground named beside it,
/// and both are asserted in `contrast_test.dart`. Nothing here relies on a
/// `ColorScheme` inferring a foreground.
///
/// This is not tidiness. A transparent scaffold over a *dark* canvas, with a
/// light scheme underneath it, renders inherited body text at 1.14:1 — and
/// where the canvas gradient meets the scheme's own `onSurface`, at 1.00:1,
/// which is invisible. That shipped in the merchant app. It was latent in the
/// customer app at the same time and merely happened to look fine, because
/// that canvas was light. An inherited colour that renders acceptably today
/// is the same bug either way.
///
/// Both mirror the `app_baselines` block of `design/theme_presets.json`; a
/// test compares them value for value so the two cannot drift.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The customer app's own look. Palette: Ember Vivid.
///
/// **A revert.** Bissap Bloom replaced these and could not be read; this is
/// where the app was before that, plus [hibiscus], which is new and narrow —
/// favourites and rating stars, nothing else.
///
/// Every value here is half of a stated pair. There is no colour in this
/// class that is meant to be combined with whatever a `ColorScheme` would
/// infer: if text goes on it, its `on` colour is named next to it and the
/// contrast is asserted in `contrast_test.dart`. That discipline is the
/// actual fix — the palette was never the whole problem.
class CustomerBaselineTokens {
  const CustomerBaselineTokens._();

  static const paletteName = 'Ember Vivid';

  // --- Chrome. Dark surfaces; light text on them, always stated. ----------

  /// The app bar and any band at the top of a phone held at night.
  static const deepwood = Color(0xFF12271F);
  static const deepwoodSoft = Color(0xFF1B362A);

  /// What goes on either of the two above. 13.97:1 on deepwood.
  static const onDeepwood = Color(0xFFF7F1E4);

  // --- Content surfaces. Light; dark text on them, always stated. ---------

  /// Cards and sheets.
  static const ivory = Color(0xFFF7F1E4);
  static const ivoryDim = Color(0xFFCFC7B3);

  /// What goes on ivory. 15.34:1.
  static const onIvory = Color(0xFF1B1B18);

  // --- Accents. -----------------------------------------------------------

  /// Primary accent: CTAs, active states.
  static const ember = Color(0xFFD98E2B);

  /// 5.40:1 on ember. Not white, which measures 2.67 and fails outright.
  static const onEmber = Color(0xFF3B2508);

  /// Ember dark enough to be read as text on ivory: 5.14:1, where ember
  /// itself measures 2.38 and cannot be written with at all.
  static const emberDim = Color(0xFF8A5C1C);

  /// Darker again, for a label that sits on the *canvas* rather than on a
  /// card. The golden hour bottoms out at #DDC594, where emberDim manages
  /// only 3.44:1 — fine for a heading, not for a button somebody has to
  /// read and tap. 4.93:1 at that worst stop, 7.36:1 on ivory.
  static const emberInk = Color(0xFF6B4712);

  /// Secondary accent, for fills.
  ///
  /// **Large or bold text only.** Nothing clears 4.5:1 against palm — white
  /// measures 4.18 and deepwood 3.76, because palm sits in the middle of the
  /// luminance range. 4.18 is over the 3:1 floor that a bold button label
  /// needs and under the one body copy needs, so palm fills buttons and
  /// [palmDeep] carries anything smaller.
  static const palm = Color(0xFF3E8A63);
  static const onPalm = Color(0xFFFFFFFF);

  /// The same green, dark enough for body text: 6.47:1 with white on it, and
  /// 5.75:1 when written in on ivory.
  static const palmDeep = Color(0xFF1F6B44);
  static const onPalmDeep = Color(0xFFFFFFFF);

  /// **Favourites and rating stars only.** The one addition to the reverted
  /// palette, and deliberately not a general-purpose accent: a heart and a
  /// row of stars are the two things a customer looks for rather than reads.
  static const hibiscus = Color(0xFFD6396B);

  /// 4.51:1 — over the body floor, but only just, so hibiscus is not a
  /// surface anything long is set on.
  static const onHibiscus = Color(0xFFFFFFFF);

  static const displayFont = 'Fraunces';
  static const bodyFont = 'Manrope';
  static const monoFont = 'IBM Plex Mono';
}

/// The merchant app's own look. Palette: Ember Professional.
///
/// **A revert, and the second one.** Indigo Ledger went in, could not be
/// read, was repaired, and is now gone entirely — no value, no font, no
/// canvas of it survives in this codebase, and a test enforces that. This is
/// the merchant direction that has shipped without a readability problem.
///
/// The shape it shares with the palette it replaces is the point worth
/// stating: a dark canvas with light cards on it, which is exactly the
/// arrangement that failed twice. The colours were never what made that
/// fail. What failed was leaving foregrounds to be inferred, so every pair
/// here is named beside the colour it sits on and measured in
/// `contrast_test.dart`.
class MerchantBaselineTokens {
  const MerchantBaselineTokens._();

  static const paletteName = 'Ember Professional';

  // --- Chrome. Dark; light text on it, always stated. ---------------------

  /// **Chrome only** — the canvas, the nav rail, the top bars. Never a
  /// surface content stands on, and never the colour of ink.
  static const deepwood = Color(0xFF12271F);
  static const deepwoodSoft = Color(0xFF1B362A);

  /// What goes on either of those, wherever they appear. 13.97:1.
  static const onDeepwood = Color(0xFFF7F1E4);

  // --- Content surfaces. Light; dark ink on them, always stated. ----------

  /// Cards, list rows, detail panels, field grids.
  static const ivory = Color(0xFFF7F1E4);
  static const ivoryDim = Color(0xFFCFC7B3);

  /// Body ink, and the only dark colour in this app that text is set in.
  /// 15.34:1 on ivory, 17.26:1 on white.
  static const ink = Color(0xFF1B1B18);
  static const onIvory = ink;

  // --- Accents. -----------------------------------------------------------

  /// Primary accent: CTAs, the active rail item, the signature glow.
  static const ember = Color(0xFFD98E2B);

  /// 5.40:1 on ember. Not white, which measures 2.67 and fails outright.
  static const onEmber = Color(0xFF3B2508);

  /// Ember dark enough to be read as text on ivory: 5.14:1, where ember
  /// itself measures 2.38 and cannot be written with at all.
  static const emberDim = Color(0xFF8A5C1C);

  /// Teal. **Data and secondary accent only** — a second series on a chart,
  /// a secondary button — and not a general-purpose colour. 5.19:1 written
  /// on ivory, so unlike ember it can carry text.
  static const sarcelle = Color(0xFF2B6E76);
  static const onSarcelle = Color(0xFFFFFFFF);

  /// Deep palm, the counterpoint on the canvas and the confirming action.
  static const palmDeep = Color(0xFF1F6B44);
  static const onPalmDeep = Color(0xFFFFFFFF);

  static const displayFont = 'Fraunces';
  static const bodyFont = 'Manrope';
  static const monoFont = 'IBM Plex Mono';
}

/// The colour half of the customer baseline, pure so it can be asserted
/// without a font stack — the same split the rest of the theming uses.
///
/// Every `on` role is a named token rather than something Material derived.
/// A scheme that infers its own foregrounds is how a dark-on-dark pairing
/// gets shipped: nothing warns, because nothing was ever asked.
ColorScheme customerBaselineColorScheme() => const ColorScheme.light(
      primary: CustomerBaselineTokens.ember,
      onPrimary: CustomerBaselineTokens.onEmber,
      primaryContainer: CustomerBaselineTokens.deepwood,
      onPrimaryContainer: CustomerBaselineTokens.onDeepwood,
      secondary: CustomerBaselineTokens.palm,
      onSecondary: CustomerBaselineTokens.onPalm,
      secondaryContainer: CustomerBaselineTokens.deepwoodSoft,
      onSecondaryContainer: CustomerBaselineTokens.onDeepwood,
      tertiary: CustomerBaselineTokens.palmDeep,
      onTertiary: CustomerBaselineTokens.onPalmDeep,
      tertiaryContainer: CustomerBaselineTokens.ivoryDim,
      onTertiaryContainer: CustomerBaselineTokens.onIvory,
      surface: CustomerBaselineTokens.ivory,
      onSurface: CustomerBaselineTokens.onIvory,
      surfaceContainerHighest: CustomerBaselineTokens.ivoryDim,
      // 6.42:1 on ivory.
      onSurfaceVariant: Color(0xFF4A5B51),
      // 3.02:1 on ivory — the floor for a boundary, which is all an outlined
      // chip is.
      outline: Color(0xFF7F8F85),
      outlineVariant: CustomerBaselineTokens.ivoryDim,
      error: Color(0xFF9A2B2B),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF7DEDE),
      onErrorContainer: Color(0xFF5A1414),
    );

/// The colour half of the merchant baseline.
///
/// Every `on` role is a named token. Material's own inference is what put
/// dark text on a dark ground twice.
ColorScheme merchantBaselineColorScheme() => const ColorScheme.light(
      primary: MerchantBaselineTokens.ember,
      onPrimary: MerchantBaselineTokens.onEmber,
      primaryContainer: MerchantBaselineTokens.deepwood,
      onPrimaryContainer: MerchantBaselineTokens.onDeepwood,
      secondary: MerchantBaselineTokens.sarcelle,
      onSecondary: MerchantBaselineTokens.onSarcelle,
      secondaryContainer: MerchantBaselineTokens.deepwoodSoft,
      onSecondaryContainer: MerchantBaselineTokens.onDeepwood,
      tertiary: MerchantBaselineTokens.palmDeep,
      onTertiary: MerchantBaselineTokens.onPalmDeep,
      tertiaryContainer: MerchantBaselineTokens.ivoryDim,
      onTertiaryContainer: MerchantBaselineTokens.ink,
      surface: MerchantBaselineTokens.ivory,
      // Ink, never the chrome colour. A palette where the ground and the ink
      // are the same value is one rename away from painting one on the other.
      onSurface: MerchantBaselineTokens.ink,
      surfaceContainerHighest: MerchantBaselineTokens.ivoryDim,
      // 6.42:1 on ivory.
      onSurfaceVariant: Color(0xFF4A5B51),
      // 3.02:1 on ivory — the floor for a boundary.
      outline: Color(0xFF7F8F85),
      outlineVariant: MerchantBaselineTokens.ivoryDim,
      error: Color(0xFF9A2B2B),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF7DEDE),
      onErrorContainer: Color(0xFF5A1414),
    );

/// The rail's colours, pure, for the same reason the colour schemes are.
///
/// The icon and the label do not sit on the same thing, and treating them as
/// if they did is how the merchant rail shipped with an unreadable selected
/// item. The *icon* is inside the indicator pill, so it takes the pill's
/// foreground; the *label* sits below it on the rail itself, so it takes the
/// rail's. Two pairs, written as two pairs — the version this replaced gave
/// the label the pill's foreground, which put near-black on indigo at 1.25:1.
NavigationRailThemeData _railTheme({
  required Color background,
  required Color indicator,
  required Color onIndicator,
  required Color onBackground,
  required Color onBackgroundDim,
}) =>
    NavigationRailThemeData(
      backgroundColor: background,
      indicatorColor: indicator,
      selectedIconTheme: IconThemeData(color: onIndicator),
      unselectedIconTheme: IconThemeData(color: onBackground),
      selectedLabelTextStyle: TextStyle(
        color: onBackground,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: onBackgroundDim),
    );

/// The customer app's rail. Light, because a customer only meets a rail on a
/// tablet and it is not the spine of their app.
NavigationRailThemeData customerBaselineRailTheme() => _railTheme(
      background: CustomerBaselineTokens.ivory,
      indicator: CustomerBaselineTokens.ember,
      onIndicator: CustomerBaselineTokens.onEmber,
      onBackground: CustomerBaselineTokens.onIvory,
      onBackgroundDim: const Color(0xFF4A5B51),
    );

/// The merchant app's rail: deepwood, with ember on the active item. The one
/// permanently dark surface on the tablet, as the design document draws it.
NavigationRailThemeData merchantBaselineRailTheme() => _railTheme(
      background: MerchantBaselineTokens.deepwood,
      indicator: MerchantBaselineTokens.ember,
      // 5.40:1 inside the pill.
      onIndicator: MerchantBaselineTokens.onEmber,
      // 13.97:1 on the rail. The label sits on the rail, not in the pill —
      // giving it the pill's foreground is the bug that shipped once.
      onBackground: MerchantBaselineTokens.onDeepwood,
      // 7.66:1 — dimmed enough to read as unselected, not to vanish.
      onBackgroundDim: const Color(0xFFB9B5A8),
    );

/// What every Scaffold in the customer app stands on.
///
/// Transparent, and allowed to be: that canvas is light, so the app's dark
/// ink reads on it. `contrast_test.dart` measures the permission rather than
/// granting it.
const customerBaselineContentGround = Colors.transparent;

/// What every Scaffold in the merchant app stands on.
///
/// Opaque ivory. This was transparent once, over a dark canvas, which is what
/// made the app unreadable — twice. Deepwood is chrome; content stands on
/// light ground whatever is behind the screen, and this one value is what
/// spares every screen from having to remember that for itself.
const merchantBaselineContentGround = MerchantBaselineTokens.ivory;

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
  required NavigationRailThemeData rail,

  /// What every Scaffold in the app stands on — see the note at
  /// `scaffoldBackgroundColor` below.
  required Color contentGround,

  /// What a text or outlined button writes its label in. Not the accent:
  /// see the note at `textButtonTheme` below.
  required Color buttonLabel,
}) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    textTheme: _baselineTextTheme(
      base.textTheme,
      displayFont: displayFont,
      bodyFont: bodyFont,
    ),
    // **The root cause of the unreadable merchant screens, fixed here.**
    //
    // This was transparent in both apps so the painted canvas would show
    // through every Scaffold. Over a light canvas that is harmless. Over the
    // merchant's dark one it meant every screen that puts a list or a column
    // straight into a Scaffold body — which is most of them — drew text in
    // the scheme's dark `onSurface` on a dark ground: 1.14:1, and 1.00:1
    // where the gradient met `onSurface` exactly.
    //
    // Each app now names its content ground instead. Nothing inherits its
    // way onto a canvas any more, on either side, and the canvas is what
    // sits behind the chrome rather than behind the content.
    scaffoldBackgroundColor: contentGround,
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
    navigationRailTheme: rail,
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
    // A text button's label defaults to colorScheme.primary — an accent
    // picked to be filled, not written with. Ember measured 1.59:1 on the
    // customer canvas and copper 2.90:1 on parchment, both of which shipped.
    // Stated here so a button is legible wherever it is put.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: buttonLabel),
    ),
    // The same reasoning for the outlined variant, which also takes primary.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: buttonLabel),
    ),
  );
}

/// The customer app's baseline theme. Palette: Ember Vivid.
///
/// The app bar wears deepwood: it is the top of a phone held in one hand at
/// night, and the dark band is what makes the ivory list below it read as the
/// content rather than as more chrome.
ThemeData customerBaselineTheme() => _baselineTheme(
      scheme: customerBaselineColorScheme(),
      displayFont: CustomerBaselineTokens.displayFont,
      bodyFont: CustomerBaselineTokens.bodyFont,
      appBarBackground: CustomerBaselineTokens.deepwood,
      appBarForeground: CustomerBaselineTokens.onDeepwood,
      rail: customerBaselineRailTheme(),
      buttonLabel: CustomerBaselineTokens.emberInk,
      // The golden-hour canvas is light, so this app can afford to let it
      // through and does: the ground is the canvas, and the cards sit on it.
      contentGround: customerBaselineContentGround,
    );

/// The merchant app's baseline theme. Palette: Ember Professional.
///
/// The header stays light: it sits beside a navigation rail that is already
/// deepwood, and two dark bands meeting reads as a mistake rather than a
/// frame.
ThemeData merchantBaselineTheme() => _baselineTheme(
      scheme: merchantBaselineColorScheme(),
      displayFont: MerchantBaselineTokens.displayFont,
      bodyFont: MerchantBaselineTokens.bodyFont,
      appBarBackground: MerchantBaselineTokens.ivory,
      appBarForeground: MerchantBaselineTokens.ink,
      rail: merchantBaselineRailTheme(),
      // Sarcelle, at 5.19:1 on ivory. Ember is the fill colour and measures
      // 2.38 as text on the same surface, so it cannot carry a label.
      buttonLabel: MerchantBaselineTokens.sarcelle,
      // Parchment, opaque. Indigo is chrome — the canvas, the rail, the dark
      // banner — and content stands on light ground whatever is behind it.
      // This one value is what makes every screen in the app legible without
      // each of them having to remember to say so.
      contentGround: merchantBaselineContentGround,
    );

// Money is set by `sylibookingPriceStyle` in app_theme.dart, and stays
// there: it chooses the mono face and nothing else, both baselines name the
// same one, and it is already called from both apps. A baseline-flavoured
// copy of it would be two functions with one behaviour.

// ---------------------------------------------------------------------------
// Contrast notes, measured rather than assumed. contrast_test.dart asserts
// every one of these against the surface it is actually painted on.
//
// Customer — Ember Vivid:
//   onDeepwood on deepwood   13.97   chrome
//   onIvory on ivory         15.34   cards
//   onEmber on ember          5.40   primary fill
//   onPalm on palm            4.18   large/bold labels only
//   onPalmDeep on palmDeep    6.47   anything smaller
//   onHibiscus on hibiscus    4.51   favourites and stars
//   deepwood on the canvas   11.00   text painted straight on the ground
//
// Two accents cannot be written *in* on ivory, and have stand-ins that can:
//   ember on ivory     2.38  ->  emberDim  5.14
//   palm on ivory      3.72  ->  palmDeep  5.75
//
// Merchant — Indigo Ledger: see the merchant tokens above, and note that
// indigo is chrome only. Text is never left to inherit onto it.
// ---------------------------------------------------------------------------
