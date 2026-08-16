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

  /// Body ink. Everything written on [parchment] or on white, and the only
  /// dark colour in this app that text is ever set in.
  ///
  /// Not [indigo]: indigo is chrome, and a colour that is both the ground
  /// under the app and the ink on its cards is one rename away from being
  /// painted on itself. Keeping them separate is what makes
  /// `contrast_test.dart` able to say which is which. 15.44:1 on parchment.
  static const ink = Color(0xFF1A1A1A);

  /// **Not [indigo].** Indigo measures 4.46:1 against copper — under the 4.5
  /// floor for normal text, and copper is what carries button labels. This is
  /// the deepest stop of the merchant background gradient, so it is already a
  /// palette member rather than a colour invented to pass a test, and it
  /// measures 5.60:1.
  static const onCopper = Color(0xFF0E1428);
  static const onSlateBlue = parchment;
  static const onSage = indigo;

  /// What goes on indigo, wherever indigo appears — the rail, the canvas, a
  /// dark banner. Never inherited: see the pairing rule in the library doc.
  static const onIndigo = parchment;

  /// What goes on parchment and on white.
  static const onParchment = ink;

  static const displayFont = 'Sora';
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
      // Ink, not indigo. This is the value that renders on every card, list
      // row and detail panel in the app, and indigo here is what made it
      // possible for content to be painted on a ground of the same colour.
      onSurface: MerchantBaselineTokens.ink,
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

  /// Goes inside the indicator pill: the selected icon, and nothing else.
  required Color railOnIndicator,

  /// Goes on the rail itself: both labels, selected and not.
  required Color railOnBackground,
  required Color railOnBackgroundDim,

  /// What every Scaffold in the app stands on. Opaque, and light in both
  /// apps — see the note at `scaffoldBackgroundColor` below.
  required Color contentGround,
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
    // The icon and the label do not sit on the same thing, and treating
    // them as if they did is how the merchant rail shipped with an
    // unreadable selected item. The *icon* is inside the indicator pill, so
    // it takes the pill's foreground; the *label* sits below it on the rail
    // itself, so it takes the rail's. Written as two pairs because they are
    // two pairs — the previous version gave the label the pill's foreground,
    // which put near-black on indigo at 1.25:1.
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: railBackground,
      indicatorColor: railIndicator,
      selectedIconTheme: IconThemeData(color: railOnIndicator),
      unselectedIconTheme: IconThemeData(color: railOnBackground),
      selectedLabelTextStyle: TextStyle(
        color: railOnBackground,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: railOnBackgroundDim,
      ),
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
      railBackground: CustomerBaselineTokens.ivory,
      railIndicator: CustomerBaselineTokens.ember,
      railOnIndicator: CustomerBaselineTokens.onEmber,
      railOnBackground: CustomerBaselineTokens.onIvory,
      railOnBackgroundDim: Color(0xFF4A5B51),
      // The golden-hour canvas is light, so this app can afford to let it
      // through and does: the ground is the canvas, and the cards sit on it.
      contentGround: Colors.transparent,
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
      // 5.60:1 inside the pill.
      railOnIndicator: MerchantBaselineTokens.onCopper,
      // 12.92:1 on the rail. This is the value that was onCopper, at 1.25:1.
      railOnBackground: MerchantBaselineTokens.parchment,
      // 7.38:1 — dimmed enough to read as unselected, not enough to vanish.
      railOnBackgroundDim: Color(0xFFB9B8BB),
      // Parchment, opaque. Indigo is chrome — the canvas, the rail, the dark
      // banner — and content stands on light ground whatever is behind it.
      // This one value is what makes every screen in the app legible without
      // each of them having to remember to say so.
      contentGround: MerchantBaselineTokens.parchment,
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
