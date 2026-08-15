/// The two app-wide baseline themes.
///
/// Half of this file exists for one reason: there are now two theming systems
/// whose names nearly collide, and the tests that matter most are the ones
/// proving they are different things. "Bissap Bloom" is the customer app's
/// whole look; "bissap" is one accent a merchant may pick for their venue.
/// Confusing them would recolour every venue in Guinea by accident.
///
/// The rest asserts the locked values and the contrast floors, because a
/// palette signed off in a browser is not a palette until something measures
/// it against the surface it will actually sit on.
library;

import 'dart:convert';
import 'dart:io';
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

double _contrast(Color a, Color b) {
  final lighter = math.max(_luminance(a), _luminance(b));
  final darker = math.min(_luminance(a), _luminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}

String _hex(Color colour) =>
    '#${colour.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

Map<String, dynamic> _baselines() {
  final file = File('../../design/theme_presets.json');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'design/theme_presets.json is the source of truth and is missing',
  );
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return json['app_baselines'] as Map<String, dynamic>;
}

/// google_fonts resolves 'Playfair Display' to a family with no space in it,
/// so a `contains('Playfair Display')` would fail against a theme that is
/// perfectly correct. Compare on the same footing the library uses.
String _family(String name) => name.replaceAll(' ', '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the baselines match the design file', () {
    test('every customer colour is the same on both sides', () {
      final customer = _baselines()['customer'] as Map<String, dynamic>;

      expect(CustomerBaselineTokens.paletteName, customer['palette_name']);
      expect(_hex(CustomerBaselineTokens.aubergine), customer['aubergine']);
      expect(_hex(CustomerBaselineTokens.bissap), customer['bissap']);
      expect(_hex(CustomerBaselineTokens.gold), customer['gold']);
      expect(_hex(CustomerBaselineTokens.pruneClair), customer['prune_clair']);
      expect(_hex(CustomerBaselineTokens.blush), customer['blush']);
      expect(_hex(CustomerBaselineTokens.onBissap), customer['on_bissap']);
      expect(_hex(CustomerBaselineTokens.onGold), customer['on_gold']);
      expect(
        _hex(CustomerBaselineTokens.onPruneClair),
        customer['on_prune_clair'],
      );
      expect(_hex(CustomerBaselineTokens.onAubergine), customer['on_aubergine']);
      expect(_hex(CustomerBaselineTokens.onBlush), customer['on_blush']);
    });

    test('every merchant colour is the same on both sides', () {
      final merchant = _baselines()['merchant'] as Map<String, dynamic>;

      expect(MerchantBaselineTokens.paletteName, merchant['palette_name']);
      expect(_hex(MerchantBaselineTokens.indigo), merchant['indigo']);
      expect(_hex(MerchantBaselineTokens.copper), merchant['copper']);
      expect(_hex(MerchantBaselineTokens.slateBlue), merchant['slate_blue']);
      expect(_hex(MerchantBaselineTokens.sage), merchant['sage']);
      expect(_hex(MerchantBaselineTokens.parchment), merchant['parchment']);
      expect(_hex(MerchantBaselineTokens.onCopper), merchant['on_copper']);
      expect(
        _hex(MerchantBaselineTokens.onSlateBlue),
        merchant['on_slate_blue'],
      );
      expect(_hex(MerchantBaselineTokens.onSage), merchant['on_sage']);
      expect(_hex(MerchantBaselineTokens.onIndigo), merchant['on_indigo']);
      expect(_hex(MerchantBaselineTokens.onParchment), merchant['on_parchment']);
    });

    test('both name their fonts identically on both sides', () {
      final baselines = _baselines();
      final customer = baselines['customer'] as Map<String, dynamic>;
      final merchant = baselines['merchant'] as Map<String, dynamic>;

      expect(CustomerBaselineTokens.displayFont, customer['display_font']);
      expect(CustomerBaselineTokens.bodyFont, customer['body_font']);
      expect(CustomerBaselineTokens.monoFont, customer['mono_font']);
      expect(MerchantBaselineTokens.displayFont, merchant['display_font']);
      expect(MerchantBaselineTokens.bodyFont, merchant['body_font']);
      expect(MerchantBaselineTokens.monoFont, merchant['mono_font']);
    });
  });

  group('the locked palette values', () {
    test('the customer palette is Bissap Bloom, exactly', () {
      expect(_hex(CustomerBaselineTokens.aubergine), '#3B1230');
      expect(_hex(CustomerBaselineTokens.bissap), '#D6296B');
      expect(_hex(CustomerBaselineTokens.gold), '#E8B23D');
      expect(_hex(CustomerBaselineTokens.pruneClair), '#7A2E5C');
      expect(_hex(CustomerBaselineTokens.blush), '#FBF2EC');
    });

    test('the merchant palette is Indigo Ledger, exactly', () {
      expect(_hex(MerchantBaselineTokens.indigo), '#1E2749');
      expect(_hex(MerchantBaselineTokens.copper), '#C97C3D');
      expect(_hex(MerchantBaselineTokens.slateBlue), '#3D5A80');
      expect(_hex(MerchantBaselineTokens.sage), '#7A9E6E');
      expect(_hex(MerchantBaselineTokens.parchment), '#F5F1E8');
    });
  });

  group('the colour schemes carry the palette', () {
    test('the customer scheme leads with bissap on blush', () {
      final scheme = customerBaselineColorScheme();

      expect(scheme.primary, CustomerBaselineTokens.bissap);
      expect(scheme.onPrimary, CustomerBaselineTokens.onBissap);
      expect(scheme.secondary, CustomerBaselineTokens.gold);
      expect(scheme.surface, CustomerBaselineTokens.blush);
      expect(scheme.onSurface, CustomerBaselineTokens.aubergine);
    });

    test('the merchant scheme leads with copper on parchment', () {
      final scheme = merchantBaselineColorScheme();

      expect(scheme.primary, MerchantBaselineTokens.copper);
      expect(scheme.onPrimary, MerchantBaselineTokens.onCopper);
      expect(scheme.secondary, MerchantBaselineTokens.slateBlue);
      expect(scheme.tertiary, MerchantBaselineTokens.sage);
      expect(scheme.surface, MerchantBaselineTokens.parchment);
      expect(scheme.onSurface, MerchantBaselineTokens.indigo);
    });

    test('copper replaces ember as the merchant signature', () {
      expect(
        merchantBaselineColorScheme().primary,
        isNot(SylibookingTokens.ember),
      );
    });
  });

  group('contrast, measured against the surface each colour sits on', () {
    test('every on-colour clears AA for normal text', () {
      final pairs = <String, List<Color>>{
        'onBissap/bissap': [
          CustomerBaselineTokens.onBissap,
          CustomerBaselineTokens.bissap,
        ],
        'onGold/gold': [
          CustomerBaselineTokens.onGold,
          CustomerBaselineTokens.gold,
        ],
        'onPruneClair/pruneClair': [
          CustomerBaselineTokens.onPruneClair,
          CustomerBaselineTokens.pruneClair,
        ],
        'onBlush/blush': [
          CustomerBaselineTokens.onBlush,
          CustomerBaselineTokens.blush,
        ],
        'onAubergine/aubergine': [
          CustomerBaselineTokens.onAubergine,
          CustomerBaselineTokens.aubergine,
        ],
        'onCopper/copper': [
          MerchantBaselineTokens.onCopper,
          MerchantBaselineTokens.copper,
        ],
        'onSlateBlue/slateBlue': [
          MerchantBaselineTokens.onSlateBlue,
          MerchantBaselineTokens.slateBlue,
        ],
        'onSage/sage': [
          MerchantBaselineTokens.onSage,
          MerchantBaselineTokens.sage,
        ],
        'onParchment/parchment': [
          MerchantBaselineTokens.onParchment,
          MerchantBaselineTokens.parchment,
        ],
        'onIndigo/indigo': [
          MerchantBaselineTokens.onIndigo,
          MerchantBaselineTokens.indigo,
        ],
      };

      pairs.forEach((label, colours) {
        expect(
          _contrast(colours[0], colours[1]),
          greaterThanOrEqualTo(4.5),
          reason: '$label is under the AA floor for normal text',
        );
      });
    });

    test('on-copper is not indigo, which measures 4.46 and fails', () {
      // Named because indigo is the obvious choice and the wrong one, and a
      // future tidy-up would reach for it.
      expect(
        _contrast(
          MerchantBaselineTokens.indigo,
          MerchantBaselineTokens.copper,
        ),
        lessThan(4.5),
      );
      expect(MerchantBaselineTokens.onCopper, isNot(MerchantBaselineTokens.indigo));
    });

    test('secondary copy and boundaries clear their own floors', () {
      final customer = customerBaselineColorScheme();
      final merchant = merchantBaselineColorScheme();

      expect(
        _contrast(customer.onSurfaceVariant, customer.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(merchant.onSurfaceVariant, merchant.surface),
        greaterThanOrEqualTo(4.5),
      );
      // 3:1 is the floor for a boundary, which is all an outlined chip is.
      expect(
        _contrast(customer.outline, customer.surface),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        _contrast(merchant.outline, merchant.surface),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('the primary accents cannot carry small text, and are not asked to',
        () {
      // Documented rather than worked around: bissap on blush is 4.33 and
      // copper on parchment is 2.90. The readable stand-in in each palette is
      // the secondary role, which is why these are the values they are.
      expect(
        _contrast(
          CustomerBaselineTokens.bissap,
          CustomerBaselineTokens.blush,
        ),
        lessThan(4.5),
      );
      expect(
        _contrast(
          CustomerBaselineTokens.pruneClair,
          CustomerBaselineTokens.blush,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(
          MerchantBaselineTokens.copper,
          MerchantBaselineTokens.parchment,
        ),
        lessThan(4.5),
      );
      expect(
        _contrast(
          MerchantBaselineTokens.slateBlue,
          MerchantBaselineTokens.parchment,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('the two systems are different things', () {
    test('the customer baseline is not the bissap venue preset', () {
      final preset = establishmentThemePresetFor('bissap');

      expect(CustomerBaselineTokens.bissap, isNot(preset.accent));
      expect(_hex(CustomerBaselineTokens.bissap), '#D6296B');
      expect(_hex(preset.accent), '#9D174D');
    });

    test('the merchant baseline is not the indigo_soir venue preset', () {
      final preset = establishmentThemePresetFor('indigo_soir');

      expect(MerchantBaselineTokens.indigo, isNot(preset.accent));
      expect(_hex(MerchantBaselineTokens.indigo), '#1E2749');
      expect(_hex(preset.accent), '#3730A3');
    });

    test('no baseline colour is any venue preset accent', () {
      // The strong form: not one value in either baseline collides with any
      // of the five, so a wrong import cannot silently look right.
      final accents =
          establishmentThemePresets.map((preset) => preset.accent).toSet();
      final baseline = <Color>[
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
      ];

      for (final colour in baseline) {
        expect(accents, isNot(contains(colour)));
      }
    });

    test('the two baselines are distinct from each other', () {
      expect(
        customerBaselineColorScheme().primary,
        isNot(merchantBaselineColorScheme().primary),
      );
      expect(
        customerBaselineColorScheme().surface,
        isNot(merchantBaselineColorScheme().surface),
      );
      expect(
        CustomerBaselineTokens.displayFont,
        isNot(MerchantBaselineTokens.displayFont),
      );
    });

    test('the five venue presets are untouched by any of this', () {
      // Values, order and default key, so a recolour cannot creep into the
      // system it was told not to touch.
      expect(
        establishmentThemePresets.map((preset) => preset.key).toList(),
        ['ember', 'palm_night', 'harmattan', 'bissap', 'indigo_soir'],
      );
      expect(defaultEstablishmentThemePresetKey, 'ember');
      expect(_hex(establishmentThemePresetFor('ember').accent), '#D98E2B');
      expect(_hex(establishmentThemePresetFor('palm_night').accent), '#0B4F3A');
      expect(_hex(establishmentThemePresetFor('harmattan').accent), '#A16207');
    });
  });

  group('on a neutral screen, each baseline paints itself', () {
    Future<ThemeData> render(WidgetTester tester, ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Titre')),
              body: const Center(child: Text('Corps')),
            ),
          ),
        ),
      );
      // Settle, not a single pump: MaterialApp animates a theme change, so a
      // second render in one test otherwise reads a value part-way between
      // the two baselines — which happens to look like the first one.
      await tester.pumpAndSettle();
      return Theme.of(tester.element(find.text('Corps')));
    }

    testWidgets('the customer baseline carries Playfair Display over Manrope',
        (tester) async {
      final theme = await render(tester, customerBaselineTheme());

      expect(theme.colorScheme.primary, CustomerBaselineTokens.bissap);
      expect(theme.colorScheme.surface, CustomerBaselineTokens.blush);
      expect(
        theme.textTheme.bodyMedium?.fontFamily,
        contains(_family(CustomerBaselineTokens.bodyFont)),
      );
      expect(
        theme.textTheme.headlineSmall?.fontFamily,
        contains(_family(CustomerBaselineTokens.displayFont)),
      );
      expect(
        theme.textTheme.titleLarge?.fontFamily,
        contains(_family(CustomerBaselineTokens.displayFont)),
      );
    });

    testWidgets('the merchant baseline carries Sora over Manrope',
        (tester) async {
      final theme = await render(tester, merchantBaselineTheme());

      expect(theme.colorScheme.primary, MerchantBaselineTokens.copper);
      expect(theme.colorScheme.surface, MerchantBaselineTokens.parchment);
      expect(
        theme.textTheme.bodyMedium?.fontFamily,
        contains(_family(MerchantBaselineTokens.bodyFont)),
      );
      expect(
        theme.textTheme.headlineSmall?.fontFamily,
        contains(_family(MerchantBaselineTokens.displayFont)),
      );
    });

    testWidgets('neither baseline is the Ember house style any more',
        (tester) async {
      final customer = await render(tester, customerBaselineTheme());
      expect(customer.colorScheme.primary, isNot(SylibookingTokens.ember));
      expect(customer.colorScheme.surface, isNot(SylibookingTokens.ivory));

      final merchant = await render(tester, merchantBaselineTheme());
      expect(merchant.colorScheme.primary, isNot(SylibookingTokens.ember));
      expect(merchant.colorScheme.surface, isNot(SylibookingTokens.ivory));
    });

    testWidgets('the app bars differ, and each for its own reason',
        (tester) async {
      // Customer: a dark band at the top of a phone. Merchant: light, because
      // it meets an indigo rail and two dark bands read as a mistake.
      final customer = await render(tester, customerBaselineTheme());
      expect(
        customer.appBarTheme.backgroundColor,
        CustomerBaselineTokens.aubergine,
      );

      final merchant = await render(tester, merchantBaselineTheme());
      expect(
        merchant.appBarTheme.backgroundColor,
        MerchantBaselineTokens.parchment,
      );
    });
  });
}
