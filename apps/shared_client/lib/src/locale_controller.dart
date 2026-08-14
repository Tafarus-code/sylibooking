import 'package:flutter/material.dart';

import 'api_client.dart';

/// Which language the app is in, and remembering the choice.
///
/// Lives here rather than in either app because both need it and the two
/// copies would drift — the `isLoaded` gate and the header wiring below are
/// easy to get subtly wrong twice.
///
/// Null means "whatever the phone is set to", which is the right default in a
/// country where the phone is already in French — nobody should have to go
/// and set the language before they can read the app. The toggle exists for
/// the case where the phone is wrong, not as a first step.
class LocaleController extends ChangeNotifier {
  LocaleController({required this.store, this.api});

  final LocaleStore store;

  /// Told about the choice so the server answers in the same language. The
  /// app is fully translated, and an English error from the API would be the
  /// only thing left giving a French screen away.
  final SylibookingApi? api;

  Locale? _locale;
  bool _loaded = false;

  /// Null until someone chooses; the app then follows the system.
  Locale? get locale => _locale;
  bool get isLoaded => _loaded;

  /// What is actually on screen, for the toggle to mark as current.
  Locale effective(BuildContext context) =>
      _locale ?? Localizations.localeOf(context);

  Future<void> load() async {
    final saved = await store.readLanguageCode();
    if (saved != null && saved.isNotEmpty) _locale = Locale(saved);
    _loaded = true;
    api?.languageCode = _locale?.languageCode;
    notifyListeners();
  }

  Future<void> set(Locale locale) async {
    if (_locale?.languageCode == locale.languageCode) return;
    _locale = locale;
    api?.languageCode = locale.languageCode;
    notifyListeners();
    await store.writeLanguageCode(locale.languageCode);
  }
}

/// Where the chosen language lives between launches.
abstract class LocaleStore {
  Future<String?> readLanguageCode();
  Future<void> writeLanguageCode(String code);
}
