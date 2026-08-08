import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether this person has agreed to send crash reports.
///
/// Three states rather than two. [unknown] is not a quiet no — it is "we have
/// not asked yet", and it exists so the app can tell the difference between
/// somebody who declined and somebody who has never seen the question. A
/// two-state flag defaulting to false makes those identical, and then the
/// only way to ask again is to pester everyone.
enum CrashConsent { unknown, granted, declined }

/// Where consent is remembered between launches.
///
/// An interface rather than SharedPreferences directly, matching how the
/// token and locale stores already work here: the apps supply the real one,
/// tests supply an in-memory one, and this package stays free of plugins.
abstract class CrashConsentStore {
  Future<CrashConsent> read();
  Future<void> write(CrashConsent consent);
}

/// Consent held in memory only. For tests, and for a first launch.
class InMemoryCrashConsentStore implements CrashConsentStore {
  InMemoryCrashConsentStore([this._consent = CrashConsent.unknown]);

  CrashConsent _consent;

  @override
  Future<CrashConsent> read() async => _consent;

  @override
  Future<void> write(CrashConsent consent) async => _consent = consent;
}

/// Somewhere a crash can be sent.
///
/// The same shape as the payment provider and the SMS notifier on the server:
/// an interface, a real implementation behind configuration, and a console
/// one that runs everywhere else. A console reporter is not a placeholder —
/// during development it is the useful one.
abstract class CrashReporter {
  Future<void> report(Object error, StackTrace? stack, {String? context});
}

/// Prints and moves on.
class ConsoleCrashReporter implements CrashReporter {
  const ConsoleCrashReporter();

  @override
  Future<void> report(Object error, StackTrace? stack, {String? context}) async {
    debugPrint('[crash]${context == null ? '' : ' $context'}: $error');
    if (stack != null) debugPrint(stack.toString());
  }
}

/// Holds the consent and decides whether anything is sent.
///
/// The gate is here rather than inside each reporter so there is one place to
/// read: if [isEnabled] is false nothing leaves the device, whatever the
/// reporter would have done with it.
class CrashReporting {
  CrashReporting({
    required CrashConsentStore store,
    CrashReporter reporter = const ConsoleCrashReporter(),
  })  : _store = store,
        _reporter = reporter;

  final CrashConsentStore _store;
  final CrashReporter _reporter;

  CrashConsent _consent = CrashConsent.unknown;
  CrashConsent get consent => _consent;

  /// Reports are sent only on an explicit yes. Silence is not consent, and
  /// "we have not asked" is silence.
  bool get isEnabled => _consent == CrashConsent.granted;

  /// Whether to put the question in front of somebody.
  bool get shouldAsk => _consent == CrashConsent.unknown;

  Future<void> load() async {
    _consent = await _store.read();
  }

  Future<void> setConsent(CrashConsent consent) async {
    _consent = consent;
    await _store.write(consent);
  }

  /// Send one, if allowed.
  ///
  /// Returns whether it went. Callers do not have to check [isEnabled]
  /// first — forgetting to is exactly how a consent gate stops working.
  Future<bool> report(Object error, StackTrace? stack, {String? context}) async {
    if (!isEnabled) return false;
    await _reporter.report(error, stack, context: context);
    return true;
  }

  /// Catch what Flutter would otherwise only print.
  ///
  /// Deliberately keeps the default handler as well: a crash should still
  /// reach the console during development, and replacing the handler outright
  /// is how a framework error becomes invisible.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(
        report(details.exception, details.stack, context: details.library),
      );
    };
  }
}
