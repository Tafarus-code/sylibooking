/// Indigo Ledger is gone, and this is what keeps it gone.
///
/// It shipped twice — once as written and once repaired — and neither release
/// could be read. The palette was reverted rather than fixed a third time, so
/// what remains is the risk of a value surviving somewhere and being reached
/// for again: a stray hex in a screen, a Sora import in a pubspec, a token
/// left dead-coded "in case".
///
/// This reads the source of both apps and the shared package and fails if any
/// of it comes back. Written as a file scan rather than as a Dart assertion
/// on purpose — a constant that no longer exists cannot be asserted about,
/// and the thing being guarded against is precisely a constant reappearing.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

/// Every value Indigo Ledger defined, lowercased for comparison.
const _indigoLedger = <String, String>{
  '#1e2749': 'Indigo',
  '#c97c3d': 'Copper',
  '#3d5a80': 'Slate blue',
  '#7a9e6e': 'Sage',
  '#f5f1e8': 'Parchment',
  '#0e1428': 'on-Copper / the canvas floor',
  '#151d38': 'the canvas ground',
  '#b9b8bb': 'the dimmed rail label',
};

/// Dart source under a directory, excluding generated and build output.
List<File> _sourceFiles(String root) {
  final directory = Directory(root);
  if (!directory.existsSync()) return const [];

  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.contains('.dart_tool'))
      .where((file) => !file.path.contains('${Platform.pathSeparator}build'))
      // Generated localisations carry no colours and are large.
      .where((file) => !file.path.contains('app_localizations'))
      .toList();
}

List<File> get _allSource => [
      ..._sourceFiles('lib'),
      ..._sourceFiles('../merchant_app/lib'),
      ..._sourceFiles('../customer_app/lib'),
    ];

void main() {
  group('no Indigo Ledger colour survives anywhere', () {
    test('not in any app or package source', () {
      final offenders = <String>[];

      for (final file in _allSource) {
        // This test file names the values it forbids, which would otherwise
        // make it its own only failure.
        if (file.path.contains('no_indigo_ledger_test')) continue;

        final source = file.readAsStringSync().toLowerCase();
        for (final entry in _indigoLedger.entries) {
          // 0xFF-prefixed and #-prefixed spellings both.
          final hex = entry.key.substring(1);
          if (source.contains('0xff$hex') || source.contains(entry.key)) {
            offenders.add('${file.path}: ${entry.value} (${entry.key})');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Indigo Ledger values are back:\n${offenders.join("\n")}',
      );
    });

    test('nor in the shared design file', () {
      final design = File('../../design/theme_presets.json');
      expect(design.existsSync(), isTrue);

      final text = design.readAsStringSync().toLowerCase();
      for (final entry in _indigoLedger.entries) {
        expect(
          text.contains(entry.key),
          isFalse,
          reason: '${entry.value} (${entry.key}) is back in theme_presets.json',
        );
      }
    });

    test('and the tokens name the palette that replaced it', () {
      expect(MerchantBaselineTokens.paletteName, 'Ember Professional');
      expect(CustomerBaselineTokens.paletteName, 'Ember Vivid');
    });
  });

  group('no Sora survives anywhere', () {
    test('not as a font name in any source or manifest', () {
      final offenders = <String>[];

      for (final file in [
        ..._allSource,
        File('pubspec.yaml'),
        File('../merchant_app/pubspec.yaml'),
        File('../customer_app/pubspec.yaml'),
        File('../../design/theme_presets.json'),
      ]) {
        if (!file.existsSync()) continue;
        if (file.path.contains('no_indigo_ledger_test')) continue;

        // Word-boundaried: "Sora" is a short word and this must not fire on
        // something that merely contains those four letters.
        final matches = RegExp(
          r'\bSora\b',
          caseSensitive: false,
        ).allMatches(file.readAsStringSync());
        if (matches.isNotEmpty) offenders.add(file.path);
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Sora is back in:\n${offenders.join("\n")}',
      );
    });

    test('both apps are set in Fraunces over Manrope', () {
      expect(MerchantBaselineTokens.displayFont, 'Fraunces');
      expect(CustomerBaselineTokens.displayFont, 'Fraunces');
      expect(MerchantBaselineTokens.bodyFont, 'Manrope');
      expect(CustomerBaselineTokens.bodyFont, 'Manrope');
      // The one face that never changed through any of this.
      expect(MerchantBaselineTokens.monoFont, 'IBM Plex Mono');
      expect(CustomerBaselineTokens.monoFont, 'IBM Plex Mono');
    });
  });
}
