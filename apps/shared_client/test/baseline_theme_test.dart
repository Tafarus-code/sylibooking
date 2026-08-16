/// The two app-wide baseline themes.
///
/// Half of this file exists for one reason: there are now two theming systems
/// whose names nearly collide, and the tests that matter most are the ones
/// proving they are different things. "Ember Vivid" is the customer app's
/// whole look; the preset keyed "ember" is one accent a merchant may pick for
/// their venue, and it happens to share the house accent. Confusing the two
/// systems would recolour every venue in Guinea by accident.
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

/// google_fonts drops spaces from family names, so a multi-word design name
/// would fail a `contains` against a theme that is perfectly correct. Compare
/// on the same footing the library uses.
String _family(String name) => name.replaceAll(' ', '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the baselines match the design file', () {
    test('every customer colour is the same on both sides', () {
      final customer = _baselines()['customer'] as Map<String, dynamic>;

      expect(CustomerBaselineTokens.paletteName, customer['palette_name']);
      expect(_hex(CustomerBaselineTokens.deepwood), customer['deepwood']);
      expect(
        _hex(CustomerBaselineTokens.deepwoodSoft),
        customer['deepwood_soft'],
      );
      expect(_hex(CustomerBaselineTokens.ember), customer['ember']);
      expect(_hex(CustomerBaselineTokens.emberDim), customer['ember_dim']);
      expect(_hex(CustomerBaselineTokens.palm), customer['palm']);
      expect(_hex(CustomerBaselineTokens.palmDeep), customer['palm_deep']);
      expect(_hex(CustomerBaselineTokens.ivory), customer['ivory']);
      expect(_hex(CustomerBaselineTokens.ivoryDim), customer['ivory_dim']);
      expect(_hex(CustomerBaselineTokens.hibiscus), customer['hibiscus']);
      expect(_hex(CustomerBaselineTokens.onDeepwood), customer['on_deepwood']);
      expect(_hex(CustomerBaselineTokens.onEmber), customer['on_ember']);
      expect(_hex(CustomerBaselineTokens.onPalm), customer['on_palm']);
      expect(_hex(CustomerBaselineTokens.onPalmDeep), customer['on_palm_deep']);
      expect(_hex(CustomerBaselineTokens.onIvory), customer['on_ivory']);
      expect(_hex(CustomerBaselineTokens.onHibiscus), customer['on_hibiscus']);
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
    test('the customer palette is Ember Vivid, exactly', () {
      expect(_hex(CustomerBaselineTokens.deepwood), '#12271F');
      expect(_hex(CustomerBaselineTokens.ember), '#D98E2B');
      expect(_hex(CustomerBaselineTokens.palm), '#3E8A63');
      expect(_hex(CustomerBaselineTokens.ivory), '#F7F1E4');
      expect(_hex(CustomerBaselineTokens.hibiscus), '#D6396B');
    });

    test('and is the palette the app shipped with before Bissap Bloom', () {
      // A revert, so the four reverted values are the house style's own. The
      // preset keyed 'ember' shares the accent, which is the house colour
      // being offered to venues rather than a collision.
      expect(CustomerBaselineTokens.ember, SylibookingTokens.ember);
      expect(CustomerBaselineTokens.deepwood, SylibookingTokens.deepwood);
      expect(CustomerBaselineTokens.ivory, SylibookingTokens.ivory);
      expect(
        establishmentThemePresetFor('ember').accent,
        CustomerBaselineTokens.ember,
      );
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
    test('the customer scheme leads with ember on ivory', () {
      final scheme = customerBaselineColorScheme();

      expect(scheme.primary, CustomerBaselineTokens.ember);
      expect(scheme.onPrimary, CustomerBaselineTokens.onEmber);
      expect(scheme.secondary, CustomerBaselineTokens.palm);
      expect(scheme.onSecondary, CustomerBaselineTokens.onPalm);
      expect(scheme.surface, CustomerBaselineTokens.ivory);
      expect(scheme.onSurface, CustomerBaselineTokens.onIvory);
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
        'onEmber/ember': [
          CustomerBaselineTokens.onEmber,
          CustomerBaselineTokens.ember,
        ],
        'onPalm/palm': [
          CustomerBaselineTokens.onPalm,
          CustomerBaselineTokens.palm,
        ],
        'onPalmDeep/palmDeep': [
          CustomerBaselineTokens.onPalmDeep,
          CustomerBaselineTokens.palmDeep,
        ],
        'onIvory/ivory': [
          CustomerBaselineTokens.onIvory,
          CustomerBaselineTokens.ivory,
        ],
        'onDeepwood/deepwood': [
          CustomerBaselineTokens.onDeepwood,
          CustomerBaselineTokens.deepwood,
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
        // Palm is the one stated exception, and it is stated in the tokens:
        // nothing clears 4.5 against it, so it fills buttons with bold labels
        // and palmDeep carries anything smaller. The next test pins the
        // number so the exception cannot quietly widen.
        final floor = label == 'onPalm/palm' ? 3.0 : 4.5;
        expect(
          _contrast(colours[0], colours[1]),
          greaterThanOrEqualTo(floor),
          reason: '$label is under its AA floor',
        );
      });
    });

    test('palm carries bold labels only, and palmDeep everything else', () {
      // The exception, measured. If a future change makes palm lighter or
      // darker this either becomes unnecessary or becomes a real failure —
      // both better than it silently drifting.
      final onPalm = _contrast(
        CustomerBaselineTokens.onPalm,
        CustomerBaselineTokens.palm,
      );
      expect(onPalm, greaterThanOrEqualTo(3.0));
      expect(onPalm, lessThan(4.5));

      expect(
        _contrast(
          CustomerBaselineTokens.onPalmDeep,
          CustomerBaselineTokens.palmDeep,
        ),
        greaterThanOrEqualTo(4.5),
      );
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
          CustomerBaselineTokens.ember,
          CustomerBaselineTokens.ivory,
        ),
        lessThan(4.5),
      );
      expect(
        _contrast(
          CustomerBaselineTokens.palmDeep,
          CustomerBaselineTokens.ivory,
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
    test('the customer baseline shares the house accent on purpose', () {
      // Under Bissap Bloom this asserted the opposite, and had to: the two
      // were different colours with nearly the same name. Reverted, the
      // customer baseline *is* the house style, and the preset keyed 'ember'
      // is that same colour offered to venues. Sharing a value is not sharing
      // a mechanism, which is what the rest of this group checks.
      expect(
        CustomerBaselineTokens.ember,
        establishmentThemePresetFor('ember').accent,
      );
      // And hibiscus is emphatically not the preset whose name suggests it.
      expect(
        CustomerBaselineTokens.hibiscus,
        isNot(establishmentThemePresetFor('bissap').accent),
      );
      expect(_hex(CustomerBaselineTokens.hibiscus), '#D6396B');
      expect(_hex(establishmentThemePresetFor('bissap').accent), '#9D174D');
    });

    test('the merchant baseline is not the indigo_soir venue preset', () {
      final preset = establishmentThemePresetFor('indigo_soir');

      expect(MerchantBaselineTokens.indigo, isNot(preset.accent));
      expect(_hex(MerchantBaselineTokens.indigo), '#1E2749');
      expect(_hex(preset.accent), '#3730A3');
    });

    test('no merchant colour is any venue preset accent', () {
      // Still the strong form for the merchant app, which shares nothing with
      // the preset set. The customer app is exempt by design — its accent is
      // the house colour, and 'ember' is that colour offered to venues.
      final accents =
          establishmentThemePresets.map((preset) => preset.accent).toSet();

      for (final colour in <Color>[
        MerchantBaselineTokens.indigo,
        MerchantBaselineTokens.copper,
        MerchantBaselineTokens.slateBlue,
        MerchantBaselineTokens.sage,
        MerchantBaselineTokens.parchment,
      ]) {
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

    testWidgets('the customer baseline carries Fraunces over Manrope',
        (tester) async {
      final theme = await render(tester, customerBaselineTheme());

      expect(theme.colorScheme.primary, CustomerBaselineTokens.ember);
      expect(theme.colorScheme.surface, CustomerBaselineTokens.ivory);
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

    testWidgets('the customer app is the house style and the merchant is not',
        (tester) async {
      final customer = await render(tester, customerBaselineTheme());
      expect(customer.colorScheme.primary, SylibookingTokens.ember);
      expect(customer.colorScheme.surface, SylibookingTokens.ivory);

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
        CustomerBaselineTokens.deepwood,
      );

      final merchant = await render(tester, merchantBaselineTheme());
      expect(
        merchant.appBarTheme.backgroundColor,
        MerchantBaselineTokens.parchment,
      );
    });
  });
}
