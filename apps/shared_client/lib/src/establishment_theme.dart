import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One venue's branding.
///
/// Mirrors `design/theme_presets.json`, which the backend reads directly. A
/// test compares the two, so they cannot drift apart. Merchants pick a key;
/// nothing here is merchant-editable, which is what keeps every venue legible.
class ThemePreset {
  const ThemePreset({
    required this.key,
    required this.name,
    required this.description,
    required this.displayFont,
    required this.bodyFont,
    required this.accent,
    required this.onAccent,
  });

  final String key;
  final String name;
  final String description;

  /// Google Fonts family names, resolved at runtime rather than bundled.
  final String displayFont;
  final String bodyFont;

  final Color accent;

  /// Pre-verified against [accent] for WCAG AA; there are tests on both sides.
  final Color onAccent;
}

Color _hex(String value) =>
    Color(int.parse(value.replaceFirst('#', 'FF'), radix: 16));

/// The curated set, in the order the branding screen shows them.
const _rawPresets = <Map<String, String>>[
  {
    'key': 'ember',
    'name': 'Ember',
    'description': 'Warm amber on deep green. The house style.',
    'display_font': 'Fraunces',
    'body_font': 'Manrope',
    'accent': '#B4551C',
    'on_accent': '#FFFFFF',
  },
  {
    'key': 'palm_night',
    'name': 'Palm Night',
    'description': 'Deep forest green, quiet and after-dark.',
    'display_font': 'Playfair Display',
    'body_font': 'Inter',
    'accent': '#0B4F3A',
    'on_accent': '#FFFFFF',
  },
  {
    'key': 'harmattan',
    'name': 'Harmattan',
    'description': 'Dry-season ochre, dusty and bright.',
    'display_font': 'Space Grotesk',
    'body_font': 'IBM Plex Sans',
    'accent': '#A16207',
    'on_accent': '#FFFFFF',
  },
  {
    'key': 'bissap',
    'name': 'Bissap',
    'description': 'Hibiscus red, the colour of the drink.',
    'display_font': 'DM Serif Display',
    'body_font': 'Work Sans',
    'accent': '#9D174D',
    'on_accent': '#FFFFFF',
  },
  {
    'key': 'indigo_soir',
    'name': 'Indigo Soir',
    'description': 'Indigo dye, deep and late.',
    'display_font': 'Fraunces',
    'body_font': 'IBM Plex Sans',
    'accent': '#3730A3',
    'on_accent': '#FFFFFF',
  },
];

/// The key a venue has until someone chooses otherwise.
const defaultThemePresetKey = 'ember';

final List<ThemePreset> themePresets = [
  for (final raw in _rawPresets)
    ThemePreset(
      key: raw['key']!,
      name: raw['name']!,
      description: raw['description']!,
      displayFont: raw['display_font']!,
      bodyFont: raw['body_font']!,
      accent: _hex(raw['accent']!),
      onAccent: _hex(raw['on_accent']!),
    ),
];

/// The preset for a key, falling back to the default.
///
/// An unknown key means the server knows a preset this build does not — a
/// newer preset, most likely. Falling back beats rendering nothing.
ThemePreset themePresetFor(String? key) => themePresets.firstWhere(
      (preset) => preset.key == key,
      orElse: () => themePresets.firstWhere(
        (preset) => preset.key == defaultThemePresetKey,
      ),
    );

/// A venue's branding as a [ThemeData], for scoping over one screen.
///
/// Deliberately derived from the caller's own theme rather than built from
/// scratch: only colour and type change, so everything else about the app
/// stays as it was, and this can wrap a subtree without disturbing the
/// chrome around it.
/// The colour half of a preset, without touching the font stack.
///
/// Separate because it is pure: it can be asserted on anywhere, whereas
/// resolving a Google font needs a binding and either a network or bundled
/// assets.
ColorScheme colorSchemeForPreset(ThemeData base, ThemePreset preset) =>
    ColorScheme.fromSeed(
      seedColor: preset.accent,
      brightness: base.brightness,
    ).copyWith(primary: preset.accent, onPrimary: preset.onAccent);

ThemeData themeForPreset(ThemeData base, ThemePreset preset) {
  final scheme = colorSchemeForPreset(base, preset);

  final bodyTheme = GoogleFonts.getTextTheme(preset.bodyFont, base.textTheme);
  final displayTheme =
      GoogleFonts.getTextTheme(preset.displayFont, base.textTheme);

  return base.copyWith(
    colorScheme: scheme,
    // Display faces carry the headlines and titles; the body face carries
    // everything that has to be read at length.
    textTheme: bodyTheme.copyWith(
      displayLarge: displayTheme.displayLarge,
      displayMedium: displayTheme.displayMedium,
      displaySmall: displayTheme.displaySmall,
      headlineLarge: displayTheme.headlineLarge,
      headlineMedium: displayTheme.headlineMedium,
      headlineSmall: displayTheme.headlineSmall,
      titleLarge: displayTheme.titleLarge,
    ),
  );
}

/// Wraps a subtree in one venue's branding.
///
/// Scoped on purpose. The app's own chrome — bottom navigation, browse list,
/// settings, the venue switcher — keeps the app's theme, so moving between
/// venues never makes the app itself look like it changed.
class EstablishmentThemeScope extends StatelessWidget {
  const EstablishmentThemeScope({
    super.key,
    required this.presetKey,
    required this.child,
  });

  final String? presetKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final preset = themePresetFor(presetKey);
    return Theme(
      data: themeForPreset(Theme.of(context), preset),
      child: child,
    );
  }
}
