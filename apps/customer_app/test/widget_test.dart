import 'dart:convert';

import 'package:customer_app/src/app.dart';
import 'package:customer_app/src/booking_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_client/shared_client.dart';

/// Canned backend. Routes are keyed "METHOD /path".
class FakeBackend {
  final Map<String, ({int status, Object? body})> routes = {};
  final List<http.Request> requests = [];

  void on(String method, String path, Object? body, {int status = 200}) {
    routes['$method $path'] = (status: status, body: body);
  }

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final route = routes['${request.method} ${request.url.path}'];
        if (route == null) {
          return http.Response(jsonEncode({'detail': 'not found'}), 404,
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

Map<String, dynamic> establishmentJson({
  int id = 7,
  String name = 'Le Petit Baobab',
  String type = 'lounge',
  String city = 'Conakry',
  int spaceCount = 2,
}) =>
    {
      'id': id,
      'name': name,
      'type': type,
      'type_display': type == 'lounge' ? 'Lounge' : 'Restaurant',
      'city': city,
      'address': 'Kaloum, $city',
      'space_count': spaceCount,
    };

Map<String, dynamic> establishmentDetailJson() => {
      ...establishmentJson(),
      'opening_hours': 'Mon-Sun 12:00-02:00',
      'spaces': [
        {
          'id': 3,
          'name': 'Table 4',
          'type': 'table',
          'type_display': 'Table',
          'capacity': 4,
        },
      ],
      'created_at': '2026-07-01T10:00:00Z',
    };

/// Availability for today with two free times on one table.
Map<String, dynamic> availabilityJson({
  List<String> freeHours = const ['19:00', '20:30'],
  List<String> takenHours = const ['21:00'],
}) {
  final now = DateTime.now();

  DateTime at(String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  return {
    'establishment': 7,
    'date': '${now.year}-${now.month}-${now.day}',
    'party_size': 2,
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
          for (final hour in freeHours)
            {'start': at(hour).toUtc().toIso8601String(), 'available': true},
          for (final hour in takenHours)
            {'start': at(hour).toUtc().toIso8601String(), 'available': false},
        ],
      },
    ],
  };
}

Map<String, dynamic> reservationJson({
  int id = 42,
  String status = 'pending',
  String customer = 'Mariama Diallo',
}) {
  final now = DateTime.now();
  return {
    'id': id,
    'space': 3,
    'space_name': 'Table 4',
    'establishment': 7,
    'establishment_name': 'Le Petit Baobab',
    'customer_name': customer,
    'customer_phone': '+224 620 00 00 00',
    'datetime': DateTime(now.year, now.month, now.day, 19).toUtc()
        .toIso8601String(),
    'party_size': 2,
    'status': status,
    'status_display': status[0].toUpperCase() + status.substring(1),
  };
}

({Widget app, FakeBackend backend, InMemoryBookingStore store}) buildApp({
  List<int>? bookingIds,
  ({String name, String phone})? customer,
}) {
  final backend = FakeBackend();
  final store = InMemoryBookingStore(ids: bookingIds, customer: customer);
  return (
    app: CustomerApp(
      api: SylibookingApi(
        baseUrl: 'http://localhost:8000/api',
        httpClient: backend.client,
      ),
      store: store,
    ),
    backend: backend,
    store: store,
  );
}

void main() {
  group('browse', () {
    testWidgets('lists establishments', (tester) async {
      final (:app, :backend, :store) = buildApp();
      backend.on('GET', '/api/establishments/', {
        'count': 2,
        'next': null,
        'results': [
          establishmentJson(),
          establishmentJson(
            id: 8,
            name: 'Chez Fatou',
            type: 'restaurant',
            city: 'Labé',
          ),
        ],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('Chez Fatou'), findsOneWidget);
      expect(find.text('Lounge · Conakry'), findsOneWidget);
    });

    testWidgets('shows an empty state when nothing matches', (tester) async {
      final (:app, :backend, :store) = buildApp();
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Nothing found'), findsOneWidget);
    });

    testWidgets('filtering by type queries the API', (tester) async {
      final (:app, :backend, :store) = buildApp();
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restaurants'));
      await tester.pumpAndSettle();

      expect(backend.lastRequest.url.queryParameters['type'], 'restaurant');
    });

    testWidgets('an unreachable API offers a retry', (tester) async {
      final (:app, :backend, :store) = buildApp();
      // No route registered -> 404 from the fake.

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Could not load places'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('availability', () {
    Future<FakeBackend> openVenue(
      WidgetTester tester, {
      Map<String, dynamic>? availability,
    }) async {
      final (:app, :backend, :store) = buildApp();
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [establishmentJson()],
      });
      backend.on('GET', '/api/establishments/7/', establishmentDetailJson());
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availability ?? availabilityJson(),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('shows only free times', (tester) async {
      await openVenue(tester);

      expect(find.text('19:00'), findsOneWidget);
      expect(find.text('20:30'), findsOneWidget);
      expect(find.text('21:00'), findsNothing);
    });

    testWidgets('shows the venue details', (tester) async {
      await openVenue(tester);

      expect(find.text('Mon-Sun 12:00-02:00'), findsOneWidget);
      expect(find.text('Kaloum, Conakry'), findsOneWidget);
    });

    testWidgets('changing party size re-queries with the new size',
        (tester) async {
      final backend = await openVenue(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, '4'));
      await tester.pumpAndSettle();

      expect(backend.lastRequest.url.queryParameters['party_size'], '4');
    });

    testWidgets('a fully booked day explains itself', (tester) async {
      await openVenue(
        tester,
        availability: availabilityJson(freeHours: [], takenHours: ['19:00']),
      );

      expect(find.textContaining('Nothing free for 2'), findsOneWidget);
    });
  });

  group('booking', () {
    Future<({FakeBackend backend, InMemoryBookingStore store})> reachForm(
      WidgetTester tester, {
      ({String name, String phone})? customer,
    }) async {
      final (:app, :backend, :store) = buildApp(customer: customer);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [establishmentJson()],
      });
      backend.on('GET', '/api/establishments/7/', establishmentDetailJson());
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availabilityJson(),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('19:00'));
      await tester.pumpAndSettle();
      return (backend: backend, store: store);
    }

    testWidgets('the form summarises what is being booked', (tester) async {
      await reachForm(tester);

      expect(find.text('Confirm booking'), findsOneWidget);
      expect(find.text('Table 4 (Table)'), findsOneWidget);
      expect(find.text('2 guests'), findsOneWidget);
      expect(
        find.text('Pay on arrival. Nothing is charged now.'),
        findsOneWidget,
      );
    });

    testWidgets('name and phone are required', (tester) async {
      final (:backend, :store) = await reachForm(tester);

      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      expect(
        find.text('The venue needs a name for the booking'),
        findsOneWidget,
      );
      expect(find.text('The venue will call to confirm'), findsOneWidget);
      // Nothing was sent.
      expect(
        backend.requests.where((r) => r.method == 'POST'),
        isEmpty,
      );
    });

    testWidgets('a short phone number is rejected', (tester) async {
      await reachForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Mariama');
      await tester.enterText(find.byType(TextFormField).last, '123');
      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      expect(find.text('That number looks too short'), findsOneWidget);
    });

    testWidgets('a successful booking shows the confirmation', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on('POST', '/api/reservations/', reservationJson());

      await tester.enterText(
        find.byType(TextFormField).first,
        'Mariama Diallo',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        '+224 620 00 00 00',
      );
      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('#42'), findsOneWidget);
      expect(find.text('Pay on arrival.'), findsOneWidget);
    });

    testWidgets('a successful booking is remembered on the device',
        (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on('POST', '/api/reservations/', reservationJson());

      await tester.enterText(
        find.byType(TextFormField).first,
        'Mariama Diallo',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        '+224 620 00 00 00',
      );
      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      expect(await store.bookingIds(), [42]);
      expect((await store.lastCustomer())?.name, 'Mariama Diallo');
    });

    testWidgets('the customer details are prefilled for a repeat visit',
        (tester) async {
      await reachForm(
        tester,
        customer: (name: 'Mariama Diallo', phone: '+224 620 00 00 00'),
      );

      // Assert on the fields' values: the phone hint is the same string, so
      // find.text would match the placeholder too.
      final fields =
          tester.widgetList<EditableText>(find.byType(EditableText)).toList();
      expect(fields[0].controller.text, 'Mariama Diallo');
      expect(fields[1].controller.text, '+224 620 00 00 00');
    });

    testWidgets('losing the slot to someone else is explained', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on(
        'POST',
        '/api/reservations/',
        {
          'datetime': ['Table 4 is already booked around that time.'],
        },
        status: 400,
      );

      await tester.enterText(
        find.byType(TextFormField).first,
        'Mariama Diallo',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        '+224 620 00 00 00',
      );
      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already booked'), findsOneWidget);
      // Still on the form, so the customer can pick again.
      expect(find.text('Reserve'), findsOneWidget);
      expect(await store.bookingIds(), isEmpty);
    });

    testWidgets('the booking time is sent as UTC', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on('POST', '/api/reservations/', reservationJson());

      await tester.enterText(find.byType(TextFormField).first, 'Mariama');
      await tester.enterText(find.byType(TextFormField).last, '620000000');
      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      final body = jsonDecode(backend.lastRequest.body) as Map<String, dynamic>;
      expect(body['datetime'], endsWith('Z'));
      expect(body['space'], 3);
      expect(body['party_size'], 2);
    });
  });

  group('my bookings', () {
    testWidgets('is empty for a new device', (tester) async {
      final (:app, :backend, :store) = buildApp();
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();

      expect(find.text('No bookings yet'), findsOneWidget);
    });

    testWidgets('re-reads stored bookings so the status is live',
        (tester) async {
      final (:app, :backend, :store) = buildApp(bookingIds: [42]);
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on(
        'GET',
        '/api/reservations/42/',
        reservationJson(status: 'confirmed'),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();

      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
    });

    testWidgets('a booking deleted server-side is skipped, not fatal',
        (tester) async {
      final (:app, :backend, :store) = buildApp(bookingIds: [42, 43]);
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/reservations/42/', reservationJson());
      // 43 has no route -> 404.

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();

      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('No bookings yet'), findsNothing);
    });
  });
}
