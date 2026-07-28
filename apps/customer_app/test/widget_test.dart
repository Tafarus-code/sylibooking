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

/// One weekday's hours as the API sends them.
Map<String, dynamic> hoursJson(
  int day,
  String dayName, {
  String? opens,
  String? closes,
  bool isClosed = false,
}) =>
    {
      'day_of_week': day,
      'day_display': dayName,
      'is_closed': isClosed,
      'opens': opens,
      'closes': closes,
      'runs_past_midnight':
          opens != null && closes != null && closes.compareTo(opens) <= 0,
    };

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// A full week open 18:00-02:00, i.e. past midnight every night.
List<Map<String, dynamic>> lateWeek() => [
      for (var day = 0; day < 7; day++)
        hoursJson(day, _dayNames[day], opens: '18:00:00', closes: '02:00:00'),
    ];

/// A week where one day is shut.
List<Map<String, dynamic>> weekClosedOn(int closedDay) => [
      for (var day = 0; day < 7; day++)
        if (day == closedDay)
          hoursJson(day, _dayNames[day], isClosed: true)
        else
          hoursJson(day, _dayNames[day],
              opens: '12:00:00', closes: '23:00:00'),
    ];

Map<String, dynamic> menuGroup(
  String category,
  String display,
  List<(String, String)> items,
) =>
    {
      'category': category,
      'category_display': display,
      'items': [
        for (final (index, item) in items.indexed)
          {
            'id': index + 1,
            'name': item.$1,
            'description': '',
            'price': item.$2,
          },
      ],
    };

Map<String, dynamic> establishmentJson({
  int id = 7,
  String name = 'Le Petit Baobab',
  String type = 'lounge',
  String city = 'Conakry',
  int spaceCount = 2,
  bool isOpenNow = true,
  String? closesAt = '02:00:00',
  Map<String, dynamic>? today,
  // Distinguishes "no hours recorded" from "today not overridden" — passing
  // today: null alone would just fall through to the default below.
  bool hoursUnknown = false,
}) =>
    {
      'id': id,
      'name': name,
      'type': type,
      'type_display': type == 'lounge' ? 'Lounge' : 'Restaurant',
      'city': city,
      'address': 'Kaloum, $city',
      'space_count': spaceCount,
      'is_open_now': isOpenNow,
      'closes_at': closesAt,
      'today': hoursUnknown
          ? null
          : (today ??
              hoursJson(0, 'Monday', opens: '18:00:00', closes: '02:00:00')),
    };

Map<String, dynamic> establishmentDetailJson({
  bool isOpenNow = true,
  String? closesAt = '02:00:00',
  Map<String, dynamic>? today,
  bool hoursUnknown = false,
  List<Map<String, dynamic>>? hours,
  List<Map<String, dynamic>>? menu,
}) =>
    {
      ...establishmentJson(
        isOpenNow: isOpenNow,
        closesAt: closesAt,
        today: today,
        hoursUnknown: hoursUnknown,
      ),
      'opening_hours': '',
      'hours': hours ?? lateWeek(),
      'menu': menu ?? [],
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

const testReference = '11111111-2222-3333-4444-555555555555';

Map<String, dynamic> reservationJson({
  int id = 42,
  String reference = testReference,
  String status = 'pending',
  String customer = 'Mariama Diallo',
  bool canCancel = true,
  Map<String, dynamic>? payment,
}) {
  final now = DateTime.now();
  return {
    'id': id,
    'reference': reference,
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
    'can_cancel': canCancel,
    'payment': payment,
  };
}

Map<String, dynamic> paymentJson({
  String provider = 'orange_money',
  String status = 'completed',
  String amount = '50000.00',
}) =>
    {
      'id': 1,
      'provider': provider,
      'provider_display':
          provider == 'orange_money' ? 'Orange Money' : 'MTN Mobile Money',
      'amount': amount,
      'status': status,
      'status_display': status[0].toUpperCase() + status.substring(1),
      'provider_reference': 'MOCK-ABC123',
      'created_at': '2026-08-01T18:00:00Z',
    };

({Widget app, FakeBackend backend, InMemoryBookingStore store}) buildApp(
  WidgetTester tester, {
  List<String>? bookingReferences,
  ({String name, String phone})? customer,
}) {
  // The default 800x600 test surface is shorter than any phone, which pushes
  // the bottom of the booking form out of the tree entirely. Use a realistic
  // 360x900 instead so what a customer can reach, the tests can reach.
  tester.view.physicalSize = const Size(1080, 2700);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final backend = FakeBackend();
  final store = InMemoryBookingStore(
    references: bookingReferences,
    customer: customer,
  );
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
      final (:app, :backend, :store) = buildApp(tester);
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
      final (:app, :backend, :store) = buildApp(tester);
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
      final (:app, :backend, :store) = buildApp(tester);
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
      final (:app, :backend, :store) = buildApp(tester);
      // No route registered -> 404 from the fake.

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Could not load places'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('open now indicator', () {
    Future<void> browseWith(
      WidgetTester tester,
      List<Map<String, dynamic>> results,
    ) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': results.length,
        'next': null,
        'results': results,
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
    }

    testWidgets('an open venue shows until when', (tester) async {
      // The 1am case: a lounge open until 02:00 is still open.
      await browseWith(tester, [
        establishmentJson(isOpenNow: true, closesAt: '02:00:00'),
      ]);

      expect(find.text('Open until 02:00'), findsOneWidget);
    });

    testWidgets('a closed venue says closed', (tester) async {
      await browseWith(tester, [
        establishmentJson(
          isOpenNow: false,
          closesAt: null,
          today: hoursJson(0, 'Monday',
              opens: '18:00:00', closes: '02:00:00'),
        ),
      ]);

      expect(find.text('Closed'), findsOneWidget);
      expect(find.textContaining('Open until'), findsNothing);
    });

    testWidgets('a venue closed today is not shown as open', (tester) async {
      await browseWith(tester, [
        establishmentJson(
          isOpenNow: false,
          closesAt: null,
          today: hoursJson(0, 'Monday', isClosed: true),
        ),
      ]);

      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets('a venue with no hours says so rather than guessing closed',
        (tester) async {
      await browseWith(tester, [
        {
          'id': 7,
          'name': 'Le Petit Baobab',
          'type': 'lounge',
          'type_display': 'Lounge',
          'city': 'Conakry',
          'address': 'Kaloum',
          'space_count': 2,
          'is_open_now': false,
          'closes_at': null,
          'today': null,
        },
      ]);

      expect(find.text('Hours not listed'), findsOneWidget);
      expect(find.text('Closed'), findsNothing);
      // Nothing recorded must not be reported as shut.
    });

    testWidgets('a mixed list marks each venue for itself', (tester) async {
      await browseWith(tester, [
        establishmentJson(id: 7, name: 'Open Venue', isOpenNow: true),
        establishmentJson(
          id: 8,
          name: 'Shut Venue',
          isOpenNow: false,
          closesAt: null,
        ),
      ]);

      expect(find.text('Open until 02:00'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
    });
  });

  group('hours on the detail screen', () {
    Future<void> openVenue(
      WidgetTester tester, {
      required Map<String, dynamic> detail,
    }) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [establishmentJson()],
      });
      backend.on('GET', '/api/establishments/7/', detail);
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availabilityJson(),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();
    }

    testWidgets('today is shown prominently', (tester) async {
      await openVenue(tester, detail: establishmentDetailJson());

      expect(find.text('Open until 02:00'), findsOneWidget);
    });

    testWidgets('the full week is collapsed by default', (tester) async {
      await openVenue(tester, detail: establishmentDetailJson());

      expect(find.text('All week'), findsOneWidget);
      expect(find.text('Wednesday'), findsNothing);
    });

    testWidgets('the full week expands on tap', (tester) async {
      await openVenue(tester, detail: establishmentDetailJson());

      await tester.tap(find.text('All week'));
      await tester.pumpAndSettle();

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
      expect(find.text('18:00 – 02:00'), findsNWidgets(7));
      expect(find.text('Hide week'), findsOneWidget);
    });

    testWidgets('a closed day reads as Closed in the week', (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(hours: weekClosedOn(2)),
      );

      await tester.tap(find.text('All week'));
      await tester.pumpAndSettle();

      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('12:00 – 23:00'), findsNWidgets(6));
    });

    testWidgets('closed today says so instead of borrowing another day',
        (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(
          isOpenNow: false,
          closesAt: null,
          today: hoursJson(2, 'Wednesday', isClosed: true),
          hours: weekClosedOn(2),
        ),
      );

      expect(find.text('Closed today'), findsOneWidget);
      expect(find.textContaining('Open until'), findsNothing);
    });

    testWidgets('a venue with no hours says they are not listed',
        (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(
          isOpenNow: false,
          closesAt: null,
          hoursUnknown: true,
          hours: const [],
        ),
      );

      expect(find.text('Hours not listed'), findsOneWidget);
      expect(find.text('All week'), findsNothing);
    });
  });

  group('menu on the detail screen', () {
    Future<void> openVenue(
      WidgetTester tester, {
      required Map<String, dynamic> detail,
    }) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [establishmentJson()],
      });
      backend.on('GET', '/api/establishments/7/', detail);
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availabilityJson(),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();
    }

    testWidgets('items are grouped under their category', (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: [
          menuGroup('food', 'Food', [('Poulet braisé', '75000.00')]),
          menuGroup('chicha_flavor', 'Chicha flavour', [
            ('Menthe', '50000.00'),
            ('Pomme', '50000.00'),
          ]),
        ]),
      );

      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Chicha flavour'), findsOneWidget);
      expect(find.text('Poulet braisé'), findsOneWidget);
      expect(find.text('Menthe'), findsOneWidget);
    });

    testWidgets('prices are shown', (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: [
          menuGroup('food', 'Food', [('Poulet braisé', '75000.00')]),
        ]),
      );

      expect(find.text('75000.00 GNF'), findsOneWidget);
    });

    testWidgets('a venue with no menu renders no Menu section at all',
        (tester) async {
      // Many pilot merchants will not have filled one in; an empty heading
      // reads as a broken screen.
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: const []),
      );

      expect(find.text('Menu'), findsNothing);
      expect(find.text('Food'), findsNothing);
      // The rest of the screen is unaffected.
      expect(find.text('Available times'), findsOneWidget);
    });

    testWidgets('only the categories the API sent are rendered',
        (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: [
          menuGroup('drink', 'Drink', [('Jus de gingembre', '20000.00')]),
        ]),
      );

      expect(find.text('Drink'), findsOneWidget);
      expect(find.text('Food'), findsNothing);
      expect(find.text('Chicha flavour'), findsNothing);
    });
  });

  group('availability', () {
    Future<FakeBackend> openVenue(
      WidgetTester tester, {
      Map<String, dynamic>? availability,
    }) async {
      final (:app, :backend, :store) = buildApp(tester);
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

      // Structured hours replaced the old free-text line.
      expect(find.text('Open until 02:00'), findsOneWidget);
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
      final (:app, :backend, :store) = buildApp(tester, customer: customer);
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
      // Payment choice replaced the old fixed "pay on arrival" banner.
      expect(find.text('How would you like to pay?'), findsOneWidget);
      expect(find.text('Pay on arrival'), findsOneWidget);
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

      // The reference, not the sequential id — the id is no longer usable.
      expect(await store.bookingReferences(), [testReference]);
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
      // Still on the form, so the customer can pick again. Assert on the app
      // bar rather than the button, which the error message can push off-screen.
      expect(find.text('Confirm booking'), findsOneWidget);
      expect(await store.bookingReferences(), isEmpty);
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

  group('paying for a booking', () {
    Future<({FakeBackend backend, InMemoryBookingStore store})> reachForm(
      WidgetTester tester,
    ) async {
      final (:app, :backend, :store) = buildApp(tester);
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

    Future<void> fillIn(WidgetTester tester) async {
      await tester.enterText(
        find.byType(TextFormField).first,
        'Mariama Diallo',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        '+224 620 00 00 00',
      );
    }

    testWidgets('offers cash and both mobile money providers', (tester) async {
      await reachForm(tester);

      expect(find.text('Pay on arrival'), findsOneWidget);
      expect(find.text('Orange Money'), findsOneWidget);
      expect(find.text('MTN Mobile Money'), findsOneWidget);
    });

    testWidgets('cash on arrival is the default', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on('POST', '/api/reservations/', reservationJson());

      await fillIn(tester);
      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      final body = jsonDecode(backend.lastRequest.body) as Map<String, dynamic>;
      expect(body['payment_provider'], 'cash_on_arrival');
    });

    testWidgets('choosing mobile money changes the button', (tester) async {
      await reachForm(tester);
      expect(find.text('Reserve'), findsOneWidget);

      await tester.tap(find.text('Orange Money'));
      await tester.pumpAndSettle();

      expect(find.text('Pay and reserve'), findsOneWidget);
    });

    testWidgets('the chosen provider is sent', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on(
        'POST',
        '/api/reservations/',
        reservationJson(status: 'confirmed', payment: paymentJson()),
      );

      await tester.tap(find.text('MTN Mobile Money'));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await tester.tap(find.text('Pay and reserve'));
      await tester.pumpAndSettle();

      final posted = backend.requests
          .firstWhere((r) => r.url.path == '/api/reservations/');
      final body = jsonDecode(posted.body) as Map<String, dynamic>;
      expect(body['payment_provider'], 'mtn_money');
    });

    testWidgets('the client never sends an amount', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on(
        'POST',
        '/api/reservations/',
        reservationJson(status: 'confirmed', payment: paymentJson()),
      );

      await tester.tap(find.text('Orange Money'));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await tester.tap(find.text('Pay and reserve'));
      await tester.pumpAndSettle();

      final posted = backend.requests
          .firstWhere((r) => r.url.path == '/api/reservations/');
      final body = jsonDecode(posted.body) as Map<String, dynamic>;
      expect(body.containsKey('amount'), isFalse);
    });

    testWidgets('a paid booking says the table is confirmed', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on(
        'POST',
        '/api/reservations/',
        reservationJson(status: 'confirmed', payment: paymentJson()),
      );

      await tester.tap(find.text('Orange Money'));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await tester.tap(find.text('Pay and reserve'));
      await tester.pumpAndSettle();

      expect(find.text('Table confirmed'), findsOneWidget);
      expect(find.text('Orange Money'), findsOneWidget);
      expect(find.text('50000.00 GNF'), findsOneWidget);
    });

    testWidgets('a cash booking still reads as a request', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on('POST', '/api/reservations/', reservationJson());

      await fillIn(tester);
      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Pay on arrival.'), findsOneWidget);
    });

    testWidgets('a failed payment says nothing was charged', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on(
        'POST',
        '/api/reservations/',
        reservationJson(payment: paymentJson(status: 'failed')),
      );

      await tester.tap(find.text('Orange Money'));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await tester.tap(find.text('Pay and reserve'));
      await tester.pumpAndSettle();

      expect(find.text('Payment did not go through'), findsOneWidget);
      expect(
        find.text('Nothing was charged. Pay on arrival instead.'),
        findsOneWidget,
      );
    });

    testWidgets('an unsettled payment shows as waiting', (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on(
        'POST',
        '/api/reservations/',
        reservationJson(payment: paymentJson(status: 'pending')),
      );
      // The provider still has not settled it, so polling changes nothing.
      backend.on('GET', '/api/reservations/ref/$testReference/payment/', {
        'reservation': reservationJson(payment: paymentJson(status: 'pending')),
        'payment': paymentJson(status: 'pending'),
      });

      await tester.tap(find.text('Orange Money'));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await tester.tap(find.text('Pay and reserve'));

      // Bounded pumps rather than pumpAndSettle: the waiting screen shows a
      // spinner, which never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Waiting for payment'), findsOneWidget);
    });

    testWidgets('polling confirms a payment that settles afterwards',
        (tester) async {
      final (:backend, :store) = await reachForm(tester);
      backend.on(
        'POST',
        '/api/reservations/',
        reservationJson(payment: paymentJson(status: 'pending')),
      );
      // By the time the app polls, the customer has approved it.
      backend.on('GET', '/api/reservations/ref/$testReference/payment/', {
        'reservation':
            reservationJson(status: 'confirmed', payment: paymentJson()),
        'payment': paymentJson(),
      });

      await tester.tap(find.text('Orange Money'));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await tester.tap(find.text('Pay and reserve'));

      // pumpAndSettle runs the clock forward past the poll interval, so the
      // spinner is replaced once the payment reports completed.
      await tester.pumpAndSettle();

      expect(find.text('Table confirmed'), findsOneWidget);
      expect(find.text('Waiting for payment'), findsNothing);
    });
  });

  group('my bookings', () {
    testWidgets('is empty for a new device', (tester) async {
      final (:app, :backend, :store) = buildApp(tester);
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
      final (:app, :backend, :store) =
          buildApp(tester, bookingReferences: [testReference]);
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on(
        'GET',
        '/api/reservations/ref/$testReference/',
        reservationJson(status: 'confirmed'),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();

      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
    });

    testWidgets('looks bookings up by reference, never by id', (tester) async {
      final (:app, :backend, :store) =
          buildApp(tester, bookingReferences: [testReference]);
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on(
        'GET',
        '/api/reservations/ref/$testReference/',
        reservationJson(),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();

      final paths = backend.requests.map((r) => r.url.path).toList();
      expect(paths, contains('/api/reservations/ref/$testReference/'));
      expect(paths, isNot(contains('/api/reservations/42/')));
    });

    testWidgets('a booking deleted server-side is skipped, not fatal',
        (tester) async {
      const missing = '99999999-8888-7777-6666-555555555555';
      final (:app, :backend, :store) =
          buildApp(tester, bookingReferences: [testReference, missing]);
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on(
        'GET',
        '/api/reservations/ref/$testReference/',
        reservationJson(),
      );
      // The other reference has no route -> 404.

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();

      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('No bookings yet'), findsNothing);
    });
  });

  group('cancelling a booking', () {
    Future<FakeBackend> openMyBookings(
      WidgetTester tester, {
      Map<String, dynamic>? reservation,
    }) async {
      final (:app, :backend, :store) =
          buildApp(tester, bookingReferences: [testReference]);
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on(
        'GET',
        '/api/reservations/ref/$testReference/',
        reservation ?? reservationJson(),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('a cancellable booking offers the button', (tester) async {
      await openMyBookings(tester);
      expect(find.text('Cancel booking'), findsOneWidget);
    });

    testWidgets('a booking the server will not let go hides the button',
        (tester) async {
      await openMyBookings(
        tester,
        reservation: reservationJson(canCancel: false),
      );

      expect(find.text('Cancel booking'), findsNothing);
      expect(find.text('To change this booking, call the venue.'),
          findsOneWidget);
    });

    testWidgets('cancelling asks first and can be backed out of',
        (tester) async {
      await openMyBookings(tester);

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this booking?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('confirming cancels and updates the card', (tester) async {
      final backend = await openMyBookings(tester);
      backend.on(
        'POST',
        '/api/reservations/ref/$testReference/cancel/',
        reservationJson(status: 'cancelled', canCancel: false),
      );

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Booking cancelled.'), findsOneWidget);
    });

    testWidgets('a booking that already started is refused with a reason',
        (tester) async {
      final backend = await openMyBookings(tester);
      backend.on(
        'POST',
        '/api/reservations/ref/$testReference/cancel/',
        {
          'detail': 'This booking has already started. Please call the venue '
              'directly.',
        },
        status: 409,
      );

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already started'), findsOneWidget);
    });
  });
}
