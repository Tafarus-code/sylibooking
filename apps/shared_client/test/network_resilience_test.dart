/// What the client does when the network misbehaves.
///
/// The rules under test are asymmetric on purpose: a read that fails is worth
/// asking again, a write that fails is not. The asymmetry is the point of the
/// file — most of these tests exist to stop a future change from making writes
/// retryable because it looked tidier.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_client/shared_client.dart';

/// A client that can be told how to fail, and counts what it was asked.
class FlakyTransport {
  FlakyTransport({
    this.failures = 0,
    this.hang = false,
    this.status = 200,
    this.body = const <String, dynamic>{'results': <dynamic>[]},
  });

  /// How many attempts fail at the transport level before one succeeds.
  int failures;

  /// When true, no attempt ever answers — the stall this whole slice is about.
  final bool hang;

  final int status;
  final Object body;

  final List<http.BaseRequest> requests = [];

  int get calls => requests.length;

  http.Client get client => MockClient((request) async {
        requests.add(request);
        if (hang) {
          // Never completes. Only the deadline can end this.
          return Completer<http.Response>().future;
        }
        if (failures > 0) {
          failures--;
          throw http.ClientException('connection reset', request.url);
        }
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
}

/// Records what the client waited for, without waiting for it.
class RecordedDelays {
  final List<Duration> waited = [];

  Future<void> call(Duration d) async => waited.add(d);
}

void main() {
  late RecordedDelays delays;

  setUp(() => delays = RecordedDelays());

  SylibookingApi apiFor(
    FlakyTransport transport, {
    Duration readTimeout = const Duration(milliseconds: 20),
    Duration writeTimeout = const Duration(milliseconds: 40),
    int readRetries = 2,
    String? token,
  }) =>
      SylibookingApi(
        baseUrl: 'http://localhost:8000/api',
        httpClient: transport.client,
        token: token,
        readTimeout: readTimeout,
        writeTimeout: writeTimeout,
        readRetries: readRetries,
        delay: delays.call,
      );

  group('a request that is never answered', () {
    test('gives up rather than waiting forever', () async {
      final transport = FlakyTransport(hang: true);
      final api = apiFor(transport);

      await expectLater(
        api.establishments(),
        throwsA(isA<ApiTimeoutException>()),
      );
    });

    test('is a timeout, not a generic failure', () async {
      // The distinction the apps read: "slow" gets a different sentence from
      // "cannot reach the server", because they ask the user for different
      // things.
      final api = apiFor(FlakyTransport(hang: true));

      try {
        await api.establishments();
        fail('expected a timeout');
      } on ApiTimeoutException catch (e) {
        expect(e.limit, const Duration(milliseconds: 20));
        expect(e.message, contains('longer than usual'));
      }
    });

    test('is still an unreachable exception, so old handlers keep working',
        () async {
      // Subclass, not sibling: every screen written before timeouts existed
      // catches ApiUnreachableException and must keep catching this.
      await expectLater(
        apiFor(FlakyTransport(hang: true)).establishments(),
        throwsA(isA<ApiUnreachableException>()),
      );
    });

    test('a write waits longer than a read before giving up', () async {
      // A payment initiation legitimately takes longer than a list.
      final api = apiFor(
        FlakyTransport(hang: true),
        readTimeout: const Duration(milliseconds: 10),
        writeTimeout: const Duration(milliseconds: 60),
      );

      try {
        await api.login('amadou', 'sylibooking');
        fail('expected a timeout');
      } on ApiTimeoutException catch (e) {
        expect(e.limit, const Duration(milliseconds: 60));
      }
    });
  });

  group('reads are retried', () {
    test('one failure then success returns the answer, having asked twice',
        () async {
      final transport = FlakyTransport(failures: 1);

      await apiFor(transport).establishments();

      expect(transport.calls, 2);
    });

    test('two failures then success still succeeds', () async {
      final transport = FlakyTransport(failures: 2);

      await apiFor(transport).establishments();

      expect(transport.calls, 3);
    });

    test('a read that never recovers throws after exactly three attempts',
        () async {
      final transport = FlakyTransport(failures: 99);

      await expectLater(
        apiFor(transport).establishments(),
        throwsA(isA<ApiUnreachableException>()),
      );
      expect(transport.calls, 3, reason: 'one attempt plus two retries');
    });

    test('a timeout is retried like any other transport failure', () async {
      final transport = FlakyTransport(hang: true);

      await expectLater(
        apiFor(transport).establishments(),
        throwsA(isA<ApiTimeoutException>()),
      );
      expect(transport.calls, 3);
    });

    test('the retry still carries the auth token', () async {
      // A retry that quietly drops the token turns a blip into a sign-out.
      final transport = FlakyTransport(failures: 1);

      await apiFor(transport, token: 'stored-token').establishments();

      expect(transport.calls, 2);
      expect(
        transport.requests.last.headers['Authorization'],
        'Token stored-token',
      );
    });

    test('retries can be switched off', () async {
      final transport = FlakyTransport(failures: 1);

      await expectLater(
        apiFor(transport, readRetries: 0).establishments(),
        throwsA(isA<ApiUnreachableException>()),
      );
      expect(transport.calls, 1);
    });
  });

  group('writes are never retried', () {
    // **The rule this file exists for.** A write that times out may already
    // have been acted on — the answer went missing, not the work. Asking
    // again books the table twice or takes the deposit twice.
    test('a failed POST is attempted once and once only', () async {
      final transport = FlakyTransport(failures: 99);

      await expectLater(
        apiFor(transport).login('amadou', 'sylibooking'),
        throwsA(isA<ApiUnreachableException>()),
      );
      expect(transport.calls, 1, reason: 'a retried POST is a double booking');
    });

    test('a POST that times out is not retried either', () async {
      final transport = FlakyTransport(hang: true);

      await expectLater(
        apiFor(transport).login('amadou', 'sylibooking'),
        throwsA(isA<ApiTimeoutException>()),
      );
      expect(
        transport.calls,
        1,
        reason: 'a timed-out write is the most dangerous one to repeat — the '
            'server may have taken it',
      );
    });

    test('and nothing is waited on before failing', () async {
      final transport = FlakyTransport(failures: 99);

      await expectLater(
        apiFor(transport).login('amadou', 'sylibooking'),
        throwsA(isA<ApiUnreachableException>()),
      );
      expect(delays.waited, isEmpty);
    });
  });

  group('backoff', () {
    test('waits longer each time, and only between attempts', () async {
      final transport = FlakyTransport(failures: 2);

      await apiFor(transport).establishments();

      // Two failures means two waits — never a third after the last attempt.
      expect(
        delays.waited,
        const [Duration(milliseconds: 400), Duration(milliseconds: 800)],
      );
    });

    test('a first attempt that works waits for nothing', () async {
      await apiFor(FlakyTransport()).establishments();

      expect(delays.waited, isEmpty);
    });
  });

  group('an answer is not a network failure', () {
    test('a 500 is not retried — the server did reply', () async {
      final transport = FlakyTransport(status: 500, body: {'detail': 'boom'});

      await expectLater(
        apiFor(transport).establishments(),
        throwsA(isA<ApiException>()),
      );
      expect(transport.calls, 1);
    });

    test('a 400 keeps its message instead of being wrapped', () async {
      final transport = FlakyTransport(
        status: 400,
        body: {'detail': 'Party size is too large.'},
      );

      try {
        await apiFor(transport).establishments();
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 400);
        expect(e.message, 'Party size is too large.');
      }
    });
  });
}
