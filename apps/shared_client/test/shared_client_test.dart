import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_client/shared_client.dart';

/// Records the requests the client makes and replies with canned JSON.
class FakeApi {
  FakeApi();

  final List<http.Request> requests = [];
  final Map<String, ({int status, Object? body})> routes = {};

  void on(String method, String path, Object? body, {int status = 200}) {
    routes['$method $path'] = (status: status, body: body);
  }

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final key = '${request.method} ${request.url.path}';
        final route = routes[key];
        if (route == null) {
          return http.Response(jsonEncode({'detail': 'no route for $key'}), 404,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(
          route.body == null ? '' : jsonEncode(route.body),
          route.status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

  http.Request get lastRequest => requests.last;
}

const _userJson = {
  'id': 1,
  'username': 'amadou',
  'first_name': 'Amadou',
  'last_name': 'Diallo',
  'is_superuser': false,
  'establishments': [
    {'id': 7, 'name': 'Le Petit Baobab', 'city': 'Conakry', 'type': 'lounge'},
  ],
};

Map<String, dynamic> reservationJson({
  int id = 1,
  String status = 'pending',
  String datetime = '2026-08-01T19:00:00Z',
}) =>
    {
      'id': id,
      'space': 3,
      'space_name': 'Table 4',
      'establishment': 7,
      'establishment_name': 'Le Petit Baobab',
      'customer_name': 'Mariama Diallo',
      'customer_phone': '+224 620 00 00 00',
      'datetime': datetime,
      'party_size': 2,
      'status': status,
      'status_display': status[0].toUpperCase() + status.substring(1),
    };

void main() {
  late FakeApi fake;
  late SylibookingApi api;

  setUp(() {
    fake = FakeApi();
    api = SylibookingApi(
      baseUrl: 'http://localhost:8000/api',
      httpClient: fake.client,
    );
  });

  group('login', () {
    test('stores the token and returns the user', () async {
      fake.on('POST', '/api/auth/login/', {'token': 'abc123', 'user': _userJson});

      final result = await api.login('amadou', 'pw');

      expect(result.token, 'abc123');
      expect(result.user.displayName, 'Amadou Diallo');
      expect(result.user.establishments.single.name, 'Le Petit Baobab');
      expect(api.isAuthenticated, isTrue);
    });

    test('sends the token on later requests', () async {
      fake.on('POST', '/api/auth/login/', {'token': 'abc123', 'user': _userJson});
      fake.on('GET', '/api/reservations/', {'count': 0, 'results': []});

      await api.login('amadou', 'pw');
      await api.reservations();

      expect(fake.lastRequest.headers['Authorization'], 'Token abc123');
    });

    test('does not send an Authorization header before login', () async {
      fake.on('GET', '/api/establishments/', {'count': 0, 'results': []});
      await api.establishments();
      expect(fake.lastRequest.headers.containsKey('Authorization'), isFalse);
    });

    test('surfaces bad credentials as an ApiException', () async {
      fake.on(
        'POST',
        '/api/auth/login/',
        {
          'non_field_errors': ['Unable to log in with provided credentials.'],
        },
        status: 400,
      );

      expect(
        () => api.login('amadou', 'wrong'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having(
                (e) => e.message,
                'message',
                contains('Unable to log in'),
              ),
        ),
      );
    });

    test('logout clears the token even when the server rejects it', () async {
      api.token = 'stale';
      fake.on('POST', '/api/auth/logout/', {'detail': 'Invalid token.'},
          status: 401);

      await api.logout();

      expect(api.isAuthenticated, isFalse);
    });
  });

  group('reservations', () {
    test('parses a page and converts datetimes to local time', () async {
      fake.on('GET', '/api/reservations/', {
        'count': 1,
        'next': null,
        'results': [reservationJson()],
      });

      final page = await api.reservations();

      expect(page.count, 1);
      final booking = page.results.single;
      expect(booking.customerName, 'Mariama Diallo');
      expect(booking.status, ReservationStatus.pending);
      expect(booking.dateTime.isUtc, isFalse);
      expect(
        booking.dateTime.toUtc(),
        DateTime.utc(2026, 8, 1, 19),
      );
    });

    test('passes date and status filters as query parameters', () async {
      fake.on('GET', '/api/reservations/', {'count': 0, 'results': []});

      await api.reservations(
        date: DateTime(2026, 8, 1),
        status: ReservationStatus.confirmed,
        establishmentId: 7,
      );

      final query = fake.lastRequest.url.queryParameters;
      expect(query['date'], '2026-08-01');
      expect(query['status'], 'confirmed');
      expect(query['establishment'], '7');
    });

    test('pads single-digit months and days', () {
      expect(formatDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('confirm returns the updated booking', () async {
      fake.on('POST', '/api/reservations/1/confirm/',
          reservationJson(status: 'confirmed'));

      final booking = await api.confirmReservation(1);

      expect(booking.status, ReservationStatus.confirmed);
    });

    test('cancel returns the updated booking', () async {
      fake.on('POST', '/api/reservations/1/cancel/',
          reservationJson(status: 'cancelled'));

      final booking = await api.cancelReservation(1);

      expect(booking.status, ReservationStatus.cancelled);
    });

    test('a 409 is flagged as a conflict', () async {
      fake.on('POST', '/api/reservations/1/confirm/',
          {'detail': 'A cancelled reservation cannot be confirmed.'},
          status: 409);

      expect(
        () => api.confirmReservation(1),
        throwsA(isA<ApiException>().having((e) => e.isConflict, 'isConflict', isTrue)),
      );
    });

    test('sends the booking time as UTC on create', () async {
      fake.on('POST', '/api/reservations/', reservationJson());

      await api.createReservation(
        spaceId: 3,
        customerName: 'Mariama Diallo',
        customerPhone: '+224 620 00 00 00',
        when: DateTime(2026, 8, 1, 19),
        partySize: 2,
      );

      final body = jsonDecode(fake.lastRequest.body) as Map<String, dynamic>;
      expect(body['datetime'], endsWith('Z'));
      expect(body['space'], 3);
    });

    test('field errors are flattened into a readable message', () async {
      fake.on(
        'POST',
        '/api/reservations/',
        {
          'datetime': ['Table 4 is already booked around that time.'],
        },
        status: 400,
      );

      expect(
        () => api.createReservation(
          spaceId: 3,
          customerName: 'x',
          customerPhone: 'y',
          when: DateTime(2026, 8, 1, 19),
          partySize: 2,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('already booked'),
          ),
        ),
      );
    });
  });

  group('establishments and availability', () {
    test('parses the list payload', () async {
      fake.on('GET', '/api/establishments/', {
        'count': 1,
        'results': [
          {
            'id': 7,
            'name': 'Le Petit Baobab',
            'type': 'lounge',
            'type_display': 'Lounge',
            'city': 'Conakry',
            'address': 'Kaloum',
            'space_count': 3,
          },
        ],
      });

      final page = await api.establishments(city: 'Conakry');

      expect(page.results.single.type, EstablishmentType.lounge);
      expect(page.results.single.spaceCount, 3);
      expect(fake.lastRequest.url.queryParameters['city'], 'Conakry');
    });

    test('parses the availability grid', () async {
      fake.on('GET', '/api/establishments/7/availability/', {
        'establishment': 7,
        'date': '2026-08-01',
        'spaces': [
          {
            'space': {
              'id': 3,
              'name': 'Table 4',
              'type': 'table',
              'type_display': 'Table',
              'capacity': 4,
            },
            'slots': [
              {'start': '2026-08-01T18:00:00Z', 'available': true},
              {'start': '2026-08-01T18:30:00Z', 'available': false},
            ],
          },
        ],
      });

      final grid = await api.availability(7, DateTime(2026, 8, 1), partySize: 2);

      expect(grid.single.space.name, 'Table 4');
      expect(grid.single.slots.where((s) => s.available), hasLength(1));
      expect(fake.lastRequest.url.queryParameters['party_size'], '2');
    });
  });

  group('failure modes', () {
    test('an unreachable server is distinguishable from an API error', () async {
      final broken = SylibookingApi(
        baseUrl: 'http://localhost:8000/api',
        httpClient: MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(
        () => broken.establishments(),
        throwsA(isA<ApiUnreachableException>()),
      );
    });

    test('unknown enum values fall back rather than throwing', () {
      final booking = Reservation.fromJson(reservationJson(status: 'refunded'));
      expect(booking.status, ReservationStatus.unknown);
      expect(booking.status.isOpen, isFalse);
    });
  });
}

/// Stands in for a network failure without importing dart:io (web-safe).
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
