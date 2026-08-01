// The two catalogues have to stay in step.
//
// A key present in English and missing from French falls back silently to the
// English string, so a half-translated app looks fine in review and reads as
// a patchwork on a merchant's phone. These are hand-written files; nothing
// else catches a key that was added to one and forgotten in the other.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keys and their values, without the @-prefixed metadata entries.
Map<String, String> _messages(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final entry in raw.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

void main() {
  final en = _messages('lib/l10n/app_en.arb');
  final fr = _messages('lib/l10n/app_fr.arb');

  test('every English message has a French one', () {
    expect(fr.keys.toSet().difference(en.keys.toSet()), isEmpty,
        reason: 'in French but not in English');
    expect(en.keys.toSet().difference(fr.keys.toSet()), isEmpty,
        reason: 'in English but not in French');
  });

  test('no message was left in English', () {
    // Brand names and the two floor words are the same in both languages on
    // purpose; everything else differing by nothing means a missed line.
    const sameInBothLanguages = {
      'languageEnglish',
      'languageFrench',
      'mobileMoney',
      'tabReservations',
      'tabOrders',
      'fieldDescription',
      'countTotal',
      'photos',
      'menu',
      'amountGnf',
      'dateRange',
      'stageHeading',
    };

    final untranslated = [
      for (final key in en.keys)
        if (!sameInBothLanguages.contains(key) && en[key] == fr[key]) key,
    ];

    expect(untranslated, isEmpty);
  });

  test('placeholders survive translation', () {
    // A dropped {name} does not fail to compile — it renders a sentence with
    // a hole in it.
    final placeholder = RegExp(r'\{(\w+)[,}]');

    for (final key in en.keys) {
      final inEnglish = placeholder
          .allMatches(en[key]!)
          .map((m) => m.group(1))
          .toSet();
      final inFrench =
          placeholder.allMatches(fr[key]!).map((m) => m.group(1)).toSet();
      expect(inFrench, inEnglish, reason: key);
    }
  });
}
