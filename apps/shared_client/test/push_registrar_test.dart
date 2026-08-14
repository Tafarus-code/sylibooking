/// Registering a handset for push, without a handset.
///
/// The Firebase implementation is a platform channel and cannot run here, so
/// what is covered is the contract every caller depends on: the no-op default
/// is genuinely harmless, and the two API calls behind registration send what
/// the server expects.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_client/shared_client.dart';

void main() {
  group('an app with no Firebase project', () {
    test('registering does nothing and returns nothing', () async {
      // **The property that keeps a build alive without a console wizard.**
      final api = SylibookingApi(baseUrl: 'http://localhost:8000/api');

      expect(await const NoPushRegistrar().register(api), isNull);
    });

    test('unregistering is safe to call', () async {
      final api = SylibookingApi(baseUrl: 'http://localhost:8000/api');

      await expectLater(const NoPushRegistrar().unregister(api), completes);
    });

    test('there are no token refreshes to listen to', () async {
      expect(await const NoPushRegistrar().tokenRefreshes.toList(), isEmpty);
    });
  });

  group('telling the server about this handset', () {
    late List<http.Request> requests;

    SylibookingApi apiRecording() {
      requests = [];
      return SylibookingApi(
        baseUrl: 'http://localhost:8000/api',
        token: 'stored-token',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      );
    }

    test('registering posts the token and the platform', () async {
      final api = apiRecording();

      await api.registerDevice(token: 'fcm-abc', platform: 'android');

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/devices/');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['token'], 'fcm-abc');
      expect(body['platform'], 'android');
    });

    test('it travels signed in, or the server cannot attach it', () async {
      final api = apiRecording();

      await api.registerDevice(token: 'fcm-abc', platform: 'android');

      expect(requests.single.headers['Authorization'], 'Token stored-token');
    });

    test('unregistering sends the token to delete', () async {
      final api = apiRecording();

      await api.unregisterDevice('fcm-abc');

      expect(requests.single.method, 'DELETE');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['token'], 'fcm-abc');
    });
  });
}
