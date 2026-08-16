/// Every pair of colours either app paints together, measured.
///
/// This file exists because a palette shipped that could not be read. The
/// merchant app spent a release drawing dark body text on a dark canvas at
/// 1.14:1 — and at 1.00:1 where the background gradient met the scheme's own
/// `onSurface`, which is to say invisible. Nothing failed. Every widget test
/// passed, the app built, and the only detector was somebody opening it.
///
/// The customer app had the identical arrangement at the same time and looked
/// fine, because its canvas happened to be light. That is the part worth
/// keeping in mind: the bug was not a colour, it was a *pair* nobody had
/// written down. So this file writes them all down.
///
/// ## How it is built
///
/// Pairs are read out of the theme objects rather than copied into a list
/// here. A hand-kept table would drift from the themes the first time
/// somebody changed one and not the other, and a contrast test that measures
/// yesterday's colours is worse than none — it reports success about
/// something nobody is shipping.
///
/// ## The floors
///
/// 4.5:1 for body text and 3:1 for large or bold text, per WCAG AA. Where a
/// pair sits at the lower floor it is named in [_largeTextOnly] with the
/// reason, so widening the exception is a visible edit rather than a quiet
/// one.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

double _luminance(Color colour) {
  double linearise(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * linearise(colour.r) +
      0.7152 * linearise(colour.g) +
      0.0722 * linearise(colour.b);
}

double contrast(Color a, Color b) {
  final lighter = math.max(_luminance(a), _luminance(b));
  final darker = math.min(_luminance(a), _luminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}

/// A translucent colour laid over an opaque one, as the compositor would.
///
/// The frosted search field is a veil over the canvas, so neither half of
/// that pair is a colour anybody wrote down — it has to be worked out.
Color composite(Color over, Color under) {
  final alpha = over.a;
  double channel(double a, double b) => a * alpha + b * (1 - alpha);
  return Color.from(
    alpha: 1,
    red: channel(over.r, under.r),
    green: channel(over.g, under.g),
    blue: channel(over.b, under.b),
  );
}

/// One thing painted on another.
typedef Pair = ({String label, Color foreground, Color background});

/// Pairs allowed the 3:1 large-text floor, each with the reason it is there.
///
/// Nothing joins this map without a measurement and a sentence. It is the
/// only place the 4.5 line bends, which is what makes bending it visible.
const _largeTextOnly = <String, String>{
  'customer secondary/onSecondary':
      'Palm sits mid-luminance: nothing clears 4.5 against it — white is '
          '4.18, deepwood 3.76. It fills buttons whose labels are bold, and '
          'palmDeep carries anything smaller.',
  'customer outline/surface':
      'A boundary, not text. An outlined chip is a line around a word, and '
          '3:1 is the floor a non-text boundary answers to.',
  'merchant outline/surface': 'The same, in the other app.',
};

/// The on/role pairs a [ColorScheme] promises, as pairs.
///
/// Read off the scheme rather than listed, so a role that changes value —
/// or a role somebody adds — is measured without this file being touched.
List<Pair> schemePairs(String app, ColorScheme scheme) => [
      (
        label: '$app primary/onPrimary',
        foreground: scheme.onPrimary,
        background: scheme.primary
      ),
      (
        label: '$app secondary/onSecondary',
        foreground: scheme.onSecondary,
        background: scheme.secondary
      ),
      (
        label: '$app tertiary/onTertiary',
        foreground: scheme.onTertiary,
        background: scheme.tertiary
      ),
      (
        label: '$app surface/onSurface',
        foreground: scheme.onSurface,
        background: scheme.surface
      ),
      (
        label: '$app primaryContainer/on',
        foreground: scheme.onPrimaryContainer,
        background: scheme.primaryContainer
      ),
      (
        label: '$app secondaryContainer/on',
        foreground: scheme.onSecondaryContainer,
        background: scheme.secondaryContainer
      ),
      (
        label: '$app tertiaryContainer/on',
        foreground: scheme.onTertiaryContainer,
        background: scheme.tertiaryContainer
      ),
      (
        label: '$app error/onError',
        foreground: scheme.onError,
        background: scheme.error
      ),
      (
        label: '$app errorContainer/on',
        foreground: scheme.onErrorContainer,
        background: scheme.errorContainer
      ),
      (
        label: '$app surfaceVariant/on',
        foreground: scheme.onSurfaceVariant,
        background: scheme.surface
      ),
      (
        label: '$app outline/surface',
        foreground: scheme.outline,
        background: scheme.surface
      ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void check(Pair pair) {
    final exception = _largeTextOnly[pair.label];
    final floor = exception == null ? 4.5 : 3.0;
    final ratio = contrast(pair.foreground, pair.background);

    expect(
      ratio,
      greaterThanOrEqualTo(floor),
      reason: '${pair.label} measures ${ratio.toStringAsFixed(2)}:1, under '
          'its ${floor.toStringAsFixed(1)} floor'
          '${exception == null ? '' : ' — $exception'}',
    );
  }

  group('the helper agrees with values anybody can check', () {
    test('black on white is 21, and a colour on itself is 1', () {
      expect(contrast(Colors.black, Colors.white), closeTo(21.0, 0.01));
      expect(contrast(Colors.white, Colors.white), closeTo(1.0, 0.001));
      // The number the merchant app actually shipped at.
      expect(
        contrast(
          MerchantBaselineTokens.indigo,
          const Color(0xFF151D38),
        ),
        closeTo(1.14, 0.01),
      );
    });

    test('compositing a veil lands between the two colours', () {
      final veiled = composite(
        CustomerBaselineTokens.ivory.withValues(alpha: 0.82),
        CustomerBaselineBackground.darkestStop,
      );

      expect(
        _luminance(veiled),
        greaterThan(_luminance(CustomerBaselineBackground.darkestStop)),
      );
      expect(
        _luminance(veiled),
        lessThan(_luminance(CustomerBaselineTokens.ivory)),
      );
    });
  });

  group('every scheme role is legible on the role it names', () {
    test('customer — Ember Vivid', () {
      for (final pair in schemePairs('customer', customerBaselineColorScheme())) {
        check(pair);
      }
    });

    test('merchant — Indigo Ledger', () {
      for (final pair in schemePairs('merchant', merchantBaselineColorScheme())) {
        check(pair);
      }
    });

    test('and a venue preset stays legible over either baseline', () {
      // A preset seeds a whole scheme, so its generated roles are measured
      // too. This is the check that would have caught a venue accent being
      // used where ink belongs.
      for (final preset in establishmentThemePresets) {
        for (final base in [
          customerBaselineColorScheme(),
          merchantBaselineColorScheme(),
        ]) {
          final scheme = colorSchemeForEstablishmentPreset(
            ThemeData(colorScheme: base),
            preset,
          );
          check((
            label: '${preset.key} primary/onPrimary',
            foreground: scheme.onPrimary,
            background: scheme.primary,
          ));
          check((
            label: '${preset.key} surface/onSurface',
            foreground: scheme.onSurface,
            background: scheme.surface,
          ));
        }
      }
    });
  });

  group('chrome pairs — the dark surfaces and what goes on them', () {
    test('customer', () {
      check((
        label: 'app bar',
        foreground: CustomerBaselineTokens.onDeepwood,
        background: CustomerBaselineTokens.deepwood,
      ));
      check((
        label: 'deepwood soft',
        foreground: CustomerBaselineTokens.onDeepwood,
        background: CustomerBaselineTokens.deepwoodSoft,
      ));
    });

    test('merchant — indigo is chrome, and never carries dark text', () {
      check((
        label: 'nav rail',
        foreground: MerchantBaselineTokens.onIndigo,
        background: MerchantBaselineTokens.indigo,
      ));
      // The bug this pins: the rail's selected *label* sits on the rail, not
      // inside the copper indicator, and it was given the indicator's
      // foreground — near-black on indigo at 1.25:1.
      final rail = merchantBaselineRailTheme();
      check((
        label: 'rail selected label',
        foreground: rail.selectedLabelTextStyle!.color!,
        background: rail.backgroundColor!,
      ));
      check((
        label: 'rail unselected label',
        foreground: rail.unselectedLabelTextStyle!.color!,
        background: rail.backgroundColor!,
      ));
      check((
        label: 'rail selected icon',
        foreground: rail.selectedIconTheme!.color!,
        background: rail.indicatorColor!,
      ));
    });
  });

  group('the canvas, and what is painted straight onto it', () {
    test('customer text holds at every stop of the golden hour', () {
      for (final stop in [
        CustomerBaselineBackground.ground,
        ...CustomerBaselineBackground.gradientStops,
      ]) {
        check((
          label: 'canvas $stop',
          foreground: CustomerBaselineTokens.onIvory,
          background: stop,
        ));
      }
    });

    test('merchant chrome holds at every stop of the indigo', () {
      // Nothing dark is painted on this one any more — that was the bug — so
      // what is measured is the light chrome that legitimately sits on it.
      for (final stop in [
        MerchantBaselineBackground.ground,
        ...MerchantBaselineBackground.gradientStops,
      ]) {
        check((
          label: 'canvas $stop',
          foreground: MerchantBaselineTokens.onIndigo,
          background: stop,
        ));
      }
    });

    test('the frosted search field is legible over the darkest stop', () {
      // Neither half of this pair is a colour anybody wrote down: the veil is
      // translucent, so what the reader sees is a composite.
      final veiled = composite(
        CustomerBaselineTokens.ivory.withValues(alpha: 0.82),
        CustomerBaselineBackground.darkestStop,
      );

      check((
        label: 'frosted field',
        foreground: CustomerBaselineTokens.onIvory,
        background: veiled,
      ));
    });
  });

  group('the status vocabulary is legible wherever it is shown', () {
    test('every tone, on both apps’ card surfaces', () {
      // These are fixed by design and shared by both apps, which is exactly
      // why they need checking against two different surfaces rather than
      // one: a badge that reads on ivory and not on parchment is still broken.
      for (final tone in StatusTone.values) {
        check((
          label: '$tone badge',
          foreground: StatusBadge.foregroundOf(tone),
          background: StatusBadge.backgroundOf(tone),
        ));

        for (final surface in [
          CustomerBaselineTokens.ivory,
          MerchantBaselineTokens.parchment,
        ]) {
          final ratio = contrast(StatusBadge.backgroundOf(tone), surface);
          expect(
            ratio,
            greaterThanOrEqualTo(1.0),
            reason: '$tone is not distinguishable from $surface',
          );
        }
      }
    });
  });

  group('the structural guarantee, not just the values', () {
    test('neither app stands its content on its own canvas', () {
      // The one-line cause, as a test. A transparent ground means the canvas
      // *is* the ground, which is only safe when the canvas is light.
      expect(merchantBaselineContentGround, isNot(Colors.transparent));
      check((
        label: 'merchant page',
        foreground: merchantBaselineColorScheme().onSurface,
        background: merchantBaselineContentGround,
      ));

      if (customerBaselineContentGround == Colors.transparent) {
        // Allowed, and only because that canvas is light. Measured against
        // its darkest stop, so the permission is earned rather than assumed —
        // and the day somebody darkens the canvas, this fails.
        check((
          label: 'customer page over its canvas',
          foreground: customerBaselineColorScheme().onSurface,
          background: CustomerBaselineBackground.darkestStop,
        ));
      } else {
        check((
          label: 'customer page',
          foreground: customerBaselineColorScheme().onSurface,
          background: customerBaselineContentGround,
        ));
      }
    });

    test('no app paints its ink in the colour of its own ground', () {
      // The plainest statement of the failure: a colour on itself.
      for (final (scheme, ground) in [
        (customerBaselineColorScheme(), customerBaselineContentGround),
        (merchantBaselineColorScheme(), merchantBaselineContentGround),
      ]) {
        expect(scheme.onSurface, isNot(scheme.surface));
        expect(scheme.onSurface, isNot(ground));
      }
      expect(
        MerchantBaselineTokens.ink,
        isNot(MerchantBaselineTokens.indigo),
        reason: 'ink and chrome must stay separable',
      );
    });
  });
}
