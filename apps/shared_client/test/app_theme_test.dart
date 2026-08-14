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

double _contrastRatio(Color a, Color b) {
  final lighter = math.max(_luminance(a), _luminance(b));
  final darker = math.min(_luminance(a), _luminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}

String _hex(Color colour) =>
    '#${colour.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

/// The `base` block of the file the backend also reads.
Map<String, dynamic> loadBaseTokens() {
  final file = File('../../design/theme_presets.json');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'design/theme_presets.json is the source of truth and is missing',
  );
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return json['base'] as Map<String, dynamic>;
}

void main() {
  // Colours and token values only. Resolving a font needs a real font stack,
  // so anything font-shaped is asserted in the app widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the baseline tokens match the design file', () {
    test('every colour token is the same on both sides', () {
      final base = loadBaseTokens();

      expect(_hex(SylibookingTokens.deepwood), base['deepwood']);
      expect(_hex(SylibookingTokens.deepwoodSoft), base['deepwood_soft']);
      expect(_hex(SylibookingTokens.ivory), base['ivory']);
      expect(_hex(SylibookingTokens.ivoryDim), base['ivory_dim']);
      expect(_hex(SylibookingTokens.ember), base['ember']);
      expect(_hex(SylibookingTokens.emberBright), base['ember_bright']);
      expect(_hex(SylibookingTokens.onEmber), base['on_ember']);
      expect(_hex(SylibookingTokens.onDeepwood), base['on_deepwood']);
      expect(_hex(SylibookingTokens.onIvory), base['on_ivory']);
    });

    test('the type faces are the same on both sides', () {
      final base = loadBaseTokens();

      expect(SylibookingTokens.displayFont, base['display_font']);
      expect(SylibookingTokens.bodyFont, base['body_font']);
    });

    test('the baseline accent is the ember preset accent', () {
      // Not a coincidence to be maintained by hand: the app's own accent and
      // the default venue preset are the same colour by design.
      expect(SylibookingTokens.ember, themePresetFor('ember').accent);
    });
  });

  group('the baseline colour scheme', () {
    final scheme = sylibookingColorScheme();

    test('ember is the primary, ivory the surface', () {
      expect(scheme.primary, SylibookingTokens.ember);
      expect(scheme.onPrimary, SylibookingTokens.onEmber);
      expect(scheme.surface, SylibookingTokens.ivory);
      expect(scheme.onSurface, SylibookingTokens.onIvory);
    });

    test('it is a light scheme', () {
      expect(scheme.brightness, Brightness.light);
    });

    test('every foreground pairing passes WCAG AA', () {
      // Body-sized text, so 4.5:1 rather than the 3:1 large-text allowance.
      final pairs = <String, (Color, Color)>{
        'onSurface on surface': (scheme.onSurface, scheme.surface),
        'onPrimary on primary': (scheme.onPrimary, scheme.primary),
        'onSurfaceVariant on surface': (
          scheme.onSurfaceVariant,
          scheme.surface,
        ),
        'onPrimaryContainer on primaryContainer': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        'onSecondaryContainer on secondaryContainer': (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
        'onError on error': (scheme.onError, scheme.error),
        'onErrorContainer on errorContainer': (
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
      };

      pairs.forEach((label, pair) {
        final ratio = _contrastRatio(pair.$1, pair.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$label is ${ratio.toStringAsFixed(2)}:1, below AA',
        );
      });
    });

    test('the outline is visible enough to read as a border', () {
      // 3:1 is the AA threshold for a non-text boundary, which is what the
      // outlined filter chips depend on.
      expect(
        _contrastRatio(scheme.outline, scheme.surface),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('the contrast helper agrees with known values', () {
      expect(
        _contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.1),
      );
    });
  });
}
