import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

/// Crash reporting, and the one rule that makes it acceptable to ship: it
/// sends nothing until somebody has said yes.

class RecordingReporter implements CrashReporter {
  final sent = <Object>[];

  @override
  Future<void> report(Object error, StackTrace? stack, {String? context}) async {
    sent.add(error);
  }
}

void main() {
  late RecordingReporter reporter;

  setUp(() => reporter = RecordingReporter());

  CrashReporting build([CrashConsent consent = CrashConsent.unknown]) =>
      CrashReporting(
        store: InMemoryCrashConsentStore(consent),
        reporter: reporter,
      );

  group('consent', () {
    test('nothing is sent before anybody is asked', () async {
      // **The rule.** Silence is not consent, and "not asked yet" is silence.
      final crashes = build();
      await crashes.load();

      final sent = await crashes.report(StateError('boom'), null);

      expect(sent, isFalse);
      expect(reporter.sent, isEmpty);
    });

    test('nothing is sent after a no', () async {
      final crashes = build(CrashConsent.declined);
      await crashes.load();

      expect(await crashes.report(StateError('boom'), null), isFalse);
      expect(reporter.sent, isEmpty);
    });

    test('a yes is what opens the gate', () async {
      final crashes = build(CrashConsent.granted);
      await crashes.load();

      expect(await crashes.report(StateError('boom'), null), isTrue);
      expect(reporter.sent, hasLength(1));
    });

    test('declining is remembered, not treated as unasked', () async {
      // Otherwise the only way to ask again is to pester everybody who
      // already said no.
      final store = InMemoryCrashConsentStore();
      final crashes = CrashReporting(store: store, reporter: reporter);
      await crashes.load();
      await crashes.setConsent(CrashConsent.declined);

      final next = CrashReporting(store: store, reporter: reporter);
      await next.load();

      expect(next.shouldAsk, isFalse);
      expect(next.isEnabled, isFalse);
    });

    test('the question is only put once', () async {
      final crashes = build();
      await crashes.load();
      expect(crashes.shouldAsk, isTrue);

      await crashes.setConsent(CrashConsent.granted);

      expect(crashes.shouldAsk, isFalse);
    });

    test('consent can be withdrawn later', () async {
      final crashes = build(CrashConsent.granted);
      await crashes.load();
      expect(await crashes.report(StateError('one'), null), isTrue);

      await crashes.setConsent(CrashConsent.declined);

      expect(await crashes.report(StateError('two'), null), isFalse);
      expect(reporter.sent, hasLength(1));
    });
  });

  group('the gate lives in one place', () {
    test('a caller does not have to remember to check first', () async {
      // Forgetting to check isEnabled is exactly how a consent gate stops
      // working, so report() checks for them.
      final crashes = build(CrashConsent.declined);
      await crashes.load();

      await crashes.report(StateError('boom'), null);

      expect(reporter.sent, isEmpty);
    });
  });
}
