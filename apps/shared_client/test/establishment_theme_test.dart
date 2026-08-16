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

      expect(baseline.primary, MerchantBaselineTokens.ember);
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

    test('the names that still shade into each other stay distinct', () {
      // Hibiscus is the customer app's new accent and is not the preset
      // called Bissap; the merchant indigo is not the preset Indigo Soir.
      final colours = <String, Color>{
        'customer baseline hibiscus': CustomerBaselineTokens.hibiscus,
        'venue preset bissap': establishmentThemePresetFor('bissap').accent,
        'merchant baseline indigo': MerchantBaselineTokens.deepwood,
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

    test('sharing a colour is not sharing a mechanism', () {
      // The customer baseline and the preset keyed 'ember' are the same
      // orange, on purpose. What has to stay true is that a venue wearing a
      // *different* preset still overrides the chrome.
      expect(
        CustomerBaselineTokens.ember,
        establishmentThemePresetFor('ember').accent,
      );

      final overCustomer =
          scoped(customerBaselineColorScheme(), 'palm_night').primary;
      expect(overCustomer, establishmentThemePresetFor('palm_night').accent);
      expect(overCustomer, isNot(CustomerBaselineTokens.ember));
    });

    test('no preset accent is merchant chrome', () {
      // Ember is excluded on purpose: it is the house accent and the 'ember'
      // preset is that colour offered to venues. The rest of the chrome is
      // the app's alone.
      final chrome = <Color>{
        MerchantBaselineTokens.deepwood,
        MerchantBaselineTokens.sarcelle,
        MerchantBaselineTokens.ivory,
        MerchantBaselineTokens.ink,
      };

      for (final preset in establishmentThemePresets) {
        expect(chrome, isNot(contains(preset.accent)));
      }
    });
  });

  group('nothing is still wearing Ember', () {
    test('both baselines are the house style, deliberately', () {
      // Two reverts brought both back. What each app adds on top is its own:
      // sarcelle for the merchant's data, hibiscus for the customer's
      // favourites.
      for (final tokens in [
        (
          CustomerBaselineTokens.ember,
          CustomerBaselineTokens.deepwood,
          CustomerBaselineTokens.ivory,
        ),
        (
          MerchantBaselineTokens.ember,
          MerchantBaselineTokens.deepwood,
          MerchantBaselineTokens.ivory,
        ),
      ]) {
        expect(tokens.$1, SylibookingTokens.ember);
        expect(tokens.$2, SylibookingTokens.deepwood);
        expect(tokens.$3, SylibookingTokens.ivory);
      }

      expect(MerchantBaselineTokens.sarcelle, isNot(SylibookingTokens.ember));
      expect(CustomerBaselineTokens.hibiscus, isNot(SylibookingTokens.ember));
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
