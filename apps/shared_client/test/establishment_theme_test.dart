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
      expect(themePresets, hasLength(5));
    });

    test('they are the expected five, in order', () {
      expect(
        themePresets.map((p) => p.key),
        ['ember', 'palm_night', 'harmattan', 'bissap', 'indigo_soir'],
      );
    });

    test('ember is the default', () {
      expect(defaultThemePresetKey, 'ember');
      expect(themePresetFor(null).key, 'ember');
    });

    test('every key resolves to itself', () {
      for (final preset in themePresets) {
        expect(themePresetFor(preset.key).key, preset.key);
      }
    });

    test('an unknown key falls back rather than failing', () {
      // A newer preset the server knows and this build does not.
      expect(themePresetFor('neon_disco').key, 'ember');
      expect(themePresetFor('').key, 'ember');
    });

    test('text on accent passes WCAG AA', () {
      for (final preset in themePresets) {
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
      expect(loadDesignFile()['default'], defaultThemePresetKey);
    });

    test('same keys in the same order', () {
      final fromFile = (loadDesignFile()['presets'] as List)
          .map((p) => (p as Map)['key'])
          .toList();

      expect(themePresets.map((p) => p.key).toList(), fromFile);
    });

    test('same fonts and colours for every preset', () {
      final fromFile = {
        for (final preset in loadDesignFile()['presets'] as List)
          (preset as Map)['key'] as String: preset,
      };

      for (final preset in themePresets) {
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

  group('colorSchemeForPreset', () {
    // The colour half is pure, so it is asserted here. Font resolution needs
    // a real font stack and is covered by the app widget tests instead.
    final base = ThemeData(useMaterial3: true);

    test('the accent becomes the primary colour', () {
      for (final preset in themePresets) {
        final scheme = colorSchemeForPreset(base, preset);
        expect(scheme.primary, preset.accent, reason: preset.key);
        expect(scheme.onPrimary, preset.onAccent, reason: preset.key);
      }
    });

    test('it follows the base brightness rather than forcing one', () {
      final dark = ThemeData(brightness: Brightness.dark);
      expect(
        colorSchemeForPreset(dark, themePresets.first).brightness,
        Brightness.dark,
      );
    });

    test('each preset yields a distinct primary', () {
      final primaries = themePresets
          .map((p) => colorSchemeForPreset(base, p).primary)
          .toSet();

      expect(primaries, hasLength(themePresets.length));
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
}
