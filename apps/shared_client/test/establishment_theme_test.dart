import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

/// WCAG relative luminance for a colour.
double _luminance(Color colour) {
  double linearise(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * linearise(colour.r) +
      0.7152 * linearise(colour.g) +
      0.0722 * linearise(colour.b);
}

double contrastRatio(Color a, Color b) {
  final lighter = math.max(_luminance(a), _luminance(b));
  final darker = math.min(_luminance(a), _luminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}

/// The file the backend reads. Dart mirrors it; this is what stops them
/// drifting apart.
Map<String, dynamic> loadDesignFile() {
  final file = File('../../design/theme_presets.json');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'design/theme_presets.json is the source of truth and is missing',
  );
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  // Colour assertions only; no font is resolved here, so none of the
  // binding-bound font machinery is involved.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the preset set', () {
    test('there are five', () {
      expect(establishmentThemePresets, hasLength(5));
    });

    test('they are the expected five, in order', () {
      expect(
        establishmentThemePresets.map((p) => p.key),
        ['ember', 'palm_night', 'harmattan', 'bissap', 'indigo_soir'],
      );
    });

    test('ember is the default', () {
      expect(defaultEstablishmentThemePresetKey, 'ember');
      expect(establishmentThemePresetFor(null).key, 'ember');
    });

    test('every key resolves to itself', () {
      for (final preset in establishmentThemePresets) {
        expect(establishmentThemePresetFor(preset.key).key, preset.key);
      }
    });

    test('an unknown key falls back rather than failing', () {
      // A newer preset the server knows and this build does not.
      expect(establishmentThemePresetFor('neon_disco').key, 'ember');
      expect(establishmentThemePresetFor('').key, 'ember');
    });

    test('text on accent passes WCAG AA', () {
      for (final preset in establishmentThemePresets) {
        final ratio = contrastRatio(preset.onAccent, preset.accent);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${preset.name}: ${ratio.toStringAsFixed(2)}:1 is below AA',
        );
      }
    });

    test('the contrast helper agrees with known values', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.1),
      );
    });
  });

  group('the Dart mirror matches the design file', () {
    test('same default', () {
      expect(loadDesignFile()['default'], defaultEstablishmentThemePresetKey);
    });

    test('same keys in the same order', () {
      final fromFile = (loadDesignFile()['presets'] as List)
          .map((p) => (p as Map)['key'])
          .toList();

      expect(establishmentThemePresets.map((p) => p.key).toList(), fromFile);
    });

    test('same fonts and colours for every preset', () {
      final fromFile = {
        for (final preset in loadDesignFile()['presets'] as List)
          (preset as Map)['key'] as String: preset,
      };

      for (final preset in establishmentThemePresets) {
        final source = fromFile[preset.key]!;
        expect(preset.name, source['name'], reason: preset.key);
        expect(preset.displayFont, source['display_font'], reason: preset.key);
        expect(preset.bodyFont, source['body_font'], reason: preset.key);
        expect(
          '#${preset.accent.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
          (source['accent'] as String).toUpperCase(),
          reason: preset.key,
        );
        expect(
          '#${preset.onAccent.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
          (source['on_accent'] as String).toUpperCase(),
          reason: preset.key,
        );
      }
    });
  });

  group('colorSchemeForEstablishmentPreset', () {
    // The colour half is pure, so it is asserted here. Font resolution needs
    // a real font stack and is covered by the app widget tests instead.
    final base = ThemeData(useMaterial3: true);

    test('the accent becomes the primary colour', () {
      for (final preset in establishmentThemePresets) {
        final scheme = colorSchemeForEstablishmentPreset(base, preset);
        expect(scheme.primary, preset.accent, reason: preset.key);
        expect(scheme.onPrimary, preset.onAccent, reason: preset.key);
      }
    });

    test('it follows the base brightness rather than forcing one', () {
      final dark = ThemeData(brightness: Brightness.dark);
      expect(
        colorSchemeForEstablishmentPreset(dark, establishmentThemePresets.first).brightness,
        Brightness.dark,
      );
    });

    test('each preset yields a distinct primary', () {
      final primaries = establishmentThemePresets
          .map((p) => colorSchemeForEstablishmentPreset(base, p).primary)
          .toSet();

      expect(primaries, hasLength(establishmentThemePresets.length));
    });
  });

  group('Establishment.themePreset', () {
    Establishment build(Object? preset) => Establishment.fromJson({
          'id': 1,
          'name': 'Le Petit Baobab',
          'type': 'lounge',
          'type_display': 'Lounge',
          'city': 'Conakry',
          'address': 'Kaloum',
          'theme_preset': preset,
        });

    test('it is read from the payload', () {
      expect(build('bissap').themePreset, 'bissap');
    });

    test('a venue with none defaults to ember', () {
      expect(build(null).themePreset, 'ember');
    });
  });

  // ==========================================================================
  // The two systems, layered.
  //
  // A venue preset is scoped over a baseline, not merged into it. That rule
  // predates the recolour, and these assert it against the *new* baselines
  // specifically — an isolation test written when both apps were Ember could
  // pass by accident, because the thing leaking and the thing leaked into
  // were the same colour.
  // ==========================================================================
  group('a venue preset over each new baseline', () {
    // Colour halves throughout. The full theme builders resolve Google fonts,
    // which needs a binding and a network; the schemes are split out from
    // them for exactly this reason, and every other test here uses them.
    ThemeData baselineOf(ColorScheme scheme) => ThemeData(colorScheme: scheme);

    ColorScheme scoped(ColorScheme baseline, String key) =>
        colorSchemeForEstablishmentPreset(
          baselineOf(baseline),
          establishmentThemePresetFor(key),
        );

    test('the preset wins inside its own scope, on the customer baseline', () {
      final baseline = customerBaselineColorScheme();
      final venue = scoped(baseline, 'palm_night');

      expect(
        venue.primary,
        establishmentThemePresetFor('palm_night').accent,
      );
      expect(venue.primary, isNot(baseline.primary));
    });

    test('and on the merchant baseline', () {
      final baseline = merchantBaselineColorScheme();
      final venue = scoped(baseline, 'harmattan');

      expect(
        venue.primary,
        establishmentThemePresetFor('harmattan').accent,
      );
      expect(venue.primary, isNot(baseline.primary));
    });

    test('the baseline it was derived from is not changed', () {
      // The scope returns a new scheme; the chrome around it keeps its own.
      final baseline = merchantBaselineColorScheme();

      scoped(baseline, 'bissap');

      expect(baseline.primary, MerchantBaselineTokens.copper);
      expect(merchantBaselineColorScheme().primary, baseline.primary);
    });

    test('every preset stays itself over either baseline', () {
      // The strong form: a preset resolves to its own accent regardless of
      // which app it is being shown in.
      for (final preset in establishmentThemePresets) {
        expect(
          scoped(customerBaselineColorScheme(), preset.key).primary,
          preset.accent,
          reason: '${preset.key} over Bissap Bloom',
        );
        expect(
          scoped(merchantBaselineColorScheme(), preset.key).primary,
          preset.accent,
          reason: '${preset.key} over Indigo Ledger',
        );
      }
    });

    test('the two colliding names stay four different colours', () {
      // The whole reason for the rename, stated as values. Nothing here may
      // ever be equal to anything else here.
      final colours = <String, Color>{
        'customer baseline bissap': CustomerBaselineTokens.bissap,
        'venue preset bissap': establishmentThemePresetFor('bissap').accent,
        'merchant baseline indigo': MerchantBaselineTokens.indigo,
        'venue preset indigo_soir':
            establishmentThemePresetFor('indigo_soir').accent,
      };

      expect(colours.values.toSet().length, colours.length);
    });

    test('one venue looks the same in both apps', () {
      // The preset seeds its own scheme, so a venue's own screens are the
      // venue's — not tinted by whichever app happens to be showing them.
      final overCustomer = scoped(customerBaselineColorScheme(), 'ember');
      final overMerchant = scoped(merchantBaselineColorScheme(), 'ember');

      expect(overCustomer.primary, overMerchant.primary);
    });

    test('no preset accent is a baseline colour', () {
      // Restated here, next to the scoping rules, because this is the file
      // somebody reads when they wonder whether the systems overlap.
      final baselineColours = <Color>{
        CustomerBaselineTokens.aubergine,
        CustomerBaselineTokens.bissap,
        CustomerBaselineTokens.gold,
        CustomerBaselineTokens.pruneClair,
        CustomerBaselineTokens.blush,
        MerchantBaselineTokens.indigo,
        MerchantBaselineTokens.copper,
        MerchantBaselineTokens.slateBlue,
        MerchantBaselineTokens.sage,
        MerchantBaselineTokens.parchment,
      };

      for (final preset in establishmentThemePresets) {
        expect(baselineColours, isNot(contains(preset.accent)));
      }
    });
  });

  group('nothing is still wearing Ember', () {
    test('neither baseline shares a colour with the old house style', () {
      final ember = <Color>{
        SylibookingTokens.deepwood,
        SylibookingTokens.deepwoodSoft,
        SylibookingTokens.ivory,
        SylibookingTokens.ivoryDim,
        SylibookingTokens.ember,
        SylibookingTokens.emberBright,
      };

      for (final colour in <Color>[
        CustomerBaselineTokens.aubergine,
        CustomerBaselineTokens.bissap,
        CustomerBaselineTokens.gold,
        CustomerBaselineTokens.pruneClair,
        CustomerBaselineTokens.blush,
        MerchantBaselineTokens.indigo,
        MerchantBaselineTokens.copper,
        MerchantBaselineTokens.slateBlue,
        MerchantBaselineTokens.sage,
        MerchantBaselineTokens.parchment,
      ]) {
        expect(ember, isNot(contains(colour)));
      }
    });

    test('the ember preset is untouched, because it is a venue choice', () {
      // The house style leaving the apps does not remove the preset a venue
      // may have picked. It is still the default a new venue gets.
      expect(
        establishmentThemePresetFor('ember').accent,
        SylibookingTokens.ember,
      );
      expect(defaultEstablishmentThemePresetKey, 'ember');
    });
  });
}
