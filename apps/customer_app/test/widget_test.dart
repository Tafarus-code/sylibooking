import 'dart:convert';

import 'package:customer_app/src/app.dart';
import 'package:customer_app/src/booking_store.dart';
import 'package:customer_app/src/directions.dart';
import 'package:customer_app/src/image_source.dart';
import 'package:customer_app/src/location_source.dart';
import 'package:customer_app/src/widgets/establishment_card.dart';
import 'package:customer_app/src/widgets/menu_section.dart';
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
  List<(String, String)> items, {
  /// Picture URL per item name. Most items have none, which is the norm.
  Map<String, String>? images,
  String description = '',
}) =>
    {
      'category': category,
      'category_display': display,
      'items': [
        for (final (index, item) in items.indexed)
          {
            'id': index + 1,
            'name': item.$1,
            'description': description,
            'price': item.$2,
            'image': images?[item.$1],
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

/// The three shapes the apps have to survive, in logical pixels.
///
/// Phone is the default everywhere; the other two are used by the responsive
/// tests. Real sizes, not round numbers: 360x900 is the commonest Android
/// phone here, 834x1112 an iPad in portrait, 1440x900 a laptop.
const phoneSize = Size(360, 900);
const tabletSize = Size(834, 1112);
const desktopSize = Size(1440, 900);

/// A phone turned sideways: short, not narrow. The shape that catches anything
/// assuming vertical room, and the one a rail has least height to work with.
const landscapePhoneSize = Size(900, 360);

({Widget app, FakeBackend backend, InMemoryBookingStore store}) buildApp(
  WidgetTester tester, {
  List<String>? bookingReferences,
  ({String name, String phone})? customer,
  ImageSource? imageSource,
  LocationSource? locationSource,
  DirectionsLauncher? directionsLauncher,
  Size size = phoneSize,
}) {
  // The default 800x600 test surface is shorter than any phone, which pushes
  // the bottom of the booking form out of the tree entirely. Use a realistic
  // 360x900 instead so what a customer can reach, the tests can reach.
  tester.view.physicalSize = size * 3.0;
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
      imageSource: imageSource,
      // Default: no location at all, which is the state most tests want and
      // the one the app must never depend on.
      locationSource: locationSource ??
          FakeLocationSource(
            granted: false,
            status: LocationStatus.unknown,
          ),
      directionsLauncher: directionsLauncher ?? FakeDirectionsLauncher(),
    ),
    backend: backend,
    store: store,
  );
}

void main() {
  group('phone, tablet and desktop', () {
    /// Drives one venue's whole journey at [size]: browse, detail with menu,
    /// hours, photos and reviews, then every other tab.
    ///
    /// A RenderFlex overflow, an unbounded constraint or a failed layout throws
    /// inside pump, so walking the app at a size *is* the assertion — there is
    /// no separate "did it overflow" check to forget to write.
    Future<void> walkTheApp(WidgetTester tester, Size size) async {
      final (:app, :backend, :store) = buildApp(
        tester,
        size: size,
        customer: (name: 'Fatou Diallo', phone: '+224620000000'),
        bookingReferences: ['ref-1'],
      );

      backend.on('GET', '/api/establishments/', {
        'count': 3,
        'next': null,
        'results': [
          establishmentJson(),
          establishmentJson(id: 8, name: 'Chez Fatou', type: 'restaurant'),
          establishmentJson(
            id: 9,
            name: 'Le Nimba, terrasse et salon privé',
            isOpenNow: false,
          ),
        ],
      });
      for (final id in [7, 8, 9]) {
        backend.on('GET', '/api/establishments/$id/photos/', {
          'count': 0,
          'next': null,
          'results': [],
        });
      }
      backend.on('GET', '/api/establishments/7/', {
        ...establishmentDetailJson(menu: [
          menuGroup('food', 'Food', [
            ('Poulet braisé', '75000.00'),
            ('Poisson braisé aux épices', '85000.00'),
            ('Riz gras', '40000.00'),
          ]),
          menuGroup('chicha_flavor', 'Chicha flavour', [
            ('Menthe', '50000.00'),
            ('Pomme', '50000.00'),
          ]),
        ]),
      });
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availabilityJson(),
      );
      backend.on('GET', '/api/establishments/7/reviews/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/reservations/by-reference/ref-1/', {
        ...reservationJson(),
        'establishment_name': 'Le Petit Baobab',
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Browse, then into a venue and back.
      expect(find.text('Le Petit Baobab'), findsWidgets);
      await tester.tap(find.text('Le Petit Baobab').first);
      await tester.pumpAndSettle();
      expect(find.text('Kaloum, Conakry'), findsOneWidget);

      // All the way down the venue screen: hours, photos, menu, reviews and
      // the booking pickers each get laid out at this size.
      await tester.scrollUntilVisible(
        find.text('Available times'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Every other tab.
      for (final tab in ['Bookings', 'Favourites', 'Profile', 'Browse']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('the app survives a phone', (tester) async {
      await walkTheApp(tester, phoneSize);
    });

    testWidgets('the app survives a tablet', (tester) async {
      await walkTheApp(tester, tabletSize);
    });

    testWidgets('the app survives a desktop window', (tester) async {
      await walkTheApp(tester, desktopSize);
    });

    testWidgets('the app survives a phone in landscape', (tester) async {
      await walkTheApp(tester, landscapePhoneSize);
    });

    testWidgets('a phone gets a bottom bar, not a rail', (tester) async {
      await walkTheApp(tester, phoneSize);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a tablet gets a rail, not a bottom bar', (tester) async {
      await walkTheApp(tester, tabletSize);

      // A bottom bar on a tablet is a thumb target where there is no thumb.
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('a desktop window gets an extended rail', (tester) async {
      await walkTheApp(tester, desktopSize);

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('a short window drops the greeting for the search field',
        (tester) async {
      await walkTheApp(tester, landscapePhoneSize);

      // 360dp of height cannot afford "Bonsoir, Fatou" above the fold.
      expect(find.text('Find a table'), findsOneWidget);
      expect(find.textContaining('Fatou,'), findsNothing);
      expect(find.textContaining('Bonsoir'), findsNothing);
    });

    testWidgets('a whole venue card fits in a landscape window',
        (tester) async {
      await walkTheApp(tester, landscapePhoneSize);

      // A card taller than the viewport means never seeing one in full, and
      // tapping it means scrolling to a target you cannot see.
      final card = tester.getSize(find.byType(EstablishmentCard).first);
      expect(card.height, lessThan(landscapePhoneSize.height));
    });

    testWidgets('venues are one column on a phone', (tester) async {
      await walkTheApp(tester, phoneSize);

      expect(find.byType(GridView), findsNothing);
    });

    testWidgets('venues fill the width on a desktop window', (tester) async {
      await walkTheApp(tester, desktopSize);

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, greaterThan(1));
    });

    testWidgets('content stops widening past a readable measure',
        (tester) async {
      await walkTheApp(tester, desktopSize);
      await tester.tap(find.text('Le Petit Baobab').first);
      await tester.pumpAndSettle();

      // The venue name is prose, and prose set across 1400px cannot be read.
      final width = tester.getSize(find.text('Kaloum, Conakry')).width;
      expect(width, lessThanOrEqualTo(ContentWidth.reading));
    });

    testWidgets('the menu adds columns rather than stretching cards',
        (tester) async {
      await walkTheApp(tester, desktopSize);
      await tester.tap(find.text('Le Petit Baobab').first);
      await tester.pumpAndSettle();

      final cardWidth =
          tester.getSize(find.byType(MenuItemCard).first).width;
      // A dish card that grew to half a desktop window would be absurd.
      expect(cardWidth, lessThan(320));
    });
  });

  group('app baseline theme', () {
    /// Browse with one venue, and the theme in force on that screen.
    Future<ThemeData> browseTheme(
      WidgetTester tester, {
      String? preset,
      ({String name, String phone})? customer,
    }) async {
      final (:app, :backend, :store) = buildApp(tester, customer: customer);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [
          {...establishmentJson(), 'theme_preset': preset},
        ],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      return Theme.of(tester.element(find.text('Find a table')));
    }

    testWidgets('browse chrome is Ember, not a Material default',
        (tester) async {
      final theme = await browseTheme(tester);

      expect(theme.colorScheme.primary, SylibookingTokens.ember);
      expect(theme.colorScheme.onPrimary, SylibookingTokens.onEmber);
      expect(theme.colorScheme.surface, SylibookingTokens.ivory);
      expect(theme.colorScheme.onSurface, SylibookingTokens.onIvory);
    });

    testWidgets('body copy is set in the house body face', (tester) async {
      final theme = await browseTheme(tester);

      // Loose contains: google_fonts appends a weight suffix to the family.
      expect(
        theme.textTheme.bodyMedium?.fontFamily,
        contains(SylibookingTokens.bodyFont),
      );
    });

    testWidgets('headings are set in the house display face', (tester) async {
      final theme = await browseTheme(tester);

      expect(
        theme.textTheme.headlineSmall?.fontFamily,
        contains(SylibookingTokens.displayFont),
      );
      expect(
        theme.textTheme.titleLarge?.fontFamily,
        contains(SylibookingTokens.displayFont),
      );
    });

    testWidgets('a loud venue preset does not reach the browse chrome',
        (tester) async {
      final theme = await browseTheme(tester, preset: 'bissap');

      // The same guarantee the branding tests make, asserted against the
      // baseline itself rather than merely "not bissap".
      expect(theme.colorScheme.primary, SylibookingTokens.ember);
    });

    testWidgets('the greeting names a returning customer', (tester) async {
      await browseTheme(
        tester,
        customer: (name: 'Fatou Diallo', phone: '+224620000000'),
      );

      // First name only: the greeting is a hello, not a record lookup.
      expect(find.textContaining('Fatou'), findsOneWidget);
      expect(find.textContaining('Diallo'), findsNothing);
    });

    testWidgets('a new device is greeted without a name', (tester) async {
      await browseTheme(tester);

      expect(find.text('Find a table'), findsOneWidget);
      expect(find.textContaining(','), findsNothing);
    });
  });

  group('bottom navigation', () {
    Future<FakeBackend> openApp(WidgetTester tester) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [establishmentJson()],
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('offers browse, bookings, favourites and profile',
        (tester) async {
      await openApp(tester);

      expect(find.text('Browse'), findsOneWidget);
      expect(find.text('Bookings'), findsOneWidget);
      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('browse is where the app opens', (tester) async {
      await openApp(tester);

      expect(find.text('Le Petit Baobab'), findsOneWidget);
    });

    testWidgets('the bar is themed by the app, not by a listed venue',
        (tester) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [
          {...establishmentJson(), 'theme_preset': 'indigo_soir'},
        ],
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final scheme = Theme.of(tester.element(find.text('Browse'))).colorScheme;
      expect(scheme.primary, SylibookingTokens.ember);
    });

    testWidgets('favourites says it is not built rather than looking broken',
        (tester) async {
      await openApp(tester);
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();

      expect(find.text('Favourites is coming'), findsOneWidget);
    });

    testWidgets('profile explains why there is no account', (tester) async {
      await openApp(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.textContaining('reference'), findsOneWidget);
    });

    testWidgets('coming back to browse does not refetch the list',
        (tester) async {
      final backend = await openApp(tester);
      final listCalls = backend.requests
          .where((r) => r.url.path == '/api/establishments/')
          .length;

      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();

      expect(
        backend.requests
            .where((r) => r.url.path == '/api/establishments/')
            .length,
        listCalls,
      );
    });
  });

  group('browse cards', () {
    Future<FakeBackend> browseWith(
      WidgetTester tester,
      List<Map<String, dynamic>> results, {
      LocationSource? locationSource,
    }) async {
      final (:app, :backend, :store) =
          buildApp(tester, locationSource: locationSource);
      backend.on('GET', '/api/establishments/', {
        'count': results.length,
        'next': null,
        'results': results,
      });
      for (final result in results) {
        backend.on('GET', '/api/establishments/${result['id']}/photos/', {
          'count': 1,
          'next': null,
          'results': [
            {
              'id': 1,
              'image_url': 'http://localhost:8000/media/venue.jpg',
              'caption': '',
              'uploaded_by_role': 'merchant',
              'uploaded_by_role_display': 'The venue',
              'created_at': '2026-08-01T18:00:00Z',
            },
          ],
        });
      }
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('every card carries a status badge', (tester) async {
      await browseWith(tester, [
        establishmentJson(),
        establishmentJson(
          id: 8,
          name: 'Chez Fatou',
          type: 'restaurant',
          isOpenNow: false,
        ),
      ]);

      expect(find.text('Open until 02:00'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets('a cover photo is fetched per venue', (tester) async {
      final backend = await browseWith(tester, [establishmentJson()]);

      expect(
        backend.requests.any(
          (r) => r.url.path == '/api/establishments/7/photos/',
        ),
        isTrue,
      );
    });

    testWidgets('no photos leaves the card intact', (tester) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [establishmentJson()],
      });
      backend.on('GET', '/api/establishments/7/photos/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Le Petit Baobab'), findsOneWidget);
    });

    testWidgets('the filter row offers every filter at 360dp', (tester) async {
      await browseWith(tester, [establishmentJson()]);

      // All present in the tree, whether or not each is currently on screen.
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Restaurants'), findsOneWidget);
      expect(find.text('Lounges'), findsOneWidget);
      expect(find.text('Open now'), findsOneWidget);
    });

    testWidgets('open now hides a shut venue', (tester) async {
      await browseWith(tester, [
        establishmentJson(),
        establishmentJson(id: 8, name: 'Chez Fatou', isOpenNow: false),
      ]);

      // Five chips do not fit across 360dp, so this one has to be scrolled
      // to — exactly as a customer would.
      await tester.ensureVisible(find.text('Open now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open now'));
      await tester.pumpAndSettle();

      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('Chez Fatou'), findsNothing);
    });

    testWidgets('open now filtering everything out explains itself',
        (tester) async {
      await browseWith(tester, [
        establishmentJson(isOpenNow: false),
      ]);

      // Five chips do not fit across 360dp, so this one has to be scrolled
      // to — exactly as a customer would.
      await tester.ensureVisible(find.text('Open now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing is open right now'), findsOneWidget);
    });

    testWidgets('open now is a client-side filter, not a new query',
        (tester) async {
      final backend = await browseWith(tester, [establishmentJson()]);
      final before = backend.requests.length;

      // Five chips do not fit across 360dp, so this one has to be scrolled
      // to — exactly as a customer would.
      await tester.ensureVisible(find.text('Open now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open now'));
      await tester.pumpAndSettle();

      expect(backend.requests.length, before);
    });
  });

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

  group('distance and directions', () {
    // Kaloum, Conakry — the customer's position in these tests.
    const here = LatLng(9.509167, -13.712222);

    Map<String, dynamic> venue({
      int id = 7,
      String name = 'Le Petit Baobab',
      Object? lat = '9.513667',
      Object? lon = '-13.712222',
    }) =>
        {
          ...establishmentJson(id: id, name: name),
          'latitude': lat,
          'longitude': lon,
        };

    /// The filter chips scroll horizontally; at 360dp the later ones sit
    /// off-screen, so bring one into view before tapping it.
    Future<void> tapChip(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    Future<FakeBackend> browse(
      WidgetTester tester, {
      required List<Map<String, dynamic>> results,
      LocationSource? locationSource,
    }) async {
      final (:app, :backend, :store) = buildApp(
        tester,
        locationSource: locationSource,
      );
      backend.on('GET', '/api/establishments/', {
        'count': results.length,
        'next': null,
        'results': results,
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('no location means no distance and no sort option',
        (tester) async {
      await browse(tester, results: [venue()]);

      expect(find.textContaining('away'), findsNothing);
      expect(find.text('Nearest'), findsNothing);
      // The way in is offered instead.
      expect(find.text('Show distances'), findsOneWidget);
    });

    testWidgets('a denied permission leaves browsing intact', (tester) async {
      await browse(
        tester,
        results: [venue(), venue(id: 8, name: 'Chez Fatou')],
        locationSource: FakeLocationSource(
          granted: false,
          status: LocationStatus.denied,
        ),
      );

      // The whole list still renders; only distance is missing.
      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('Chez Fatou'), findsOneWidget);
      expect(find.textContaining('away'), findsNothing);
      expect(find.text('Nearest'), findsNothing);
    });

    testWidgets('declining the rationale asks the platform for nothing',
        (tester) async {
      final location = FakeLocationSource(
        granted: false,
        status: LocationStatus.denied,
      );
      await browse(tester, results: [venue()], locationSource: location);

      await tapChip(tester, 'Show distances');
      expect(find.text('Show distances?'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(location.requestCount, 0);
      expect(find.text('Nearest'), findsNothing);
    });

    testWidgets('a refusal at the OS level is explained, not an error',
        (tester) async {
      final location = FakeLocationSource(
        granted: false,
        status: LocationStatus.denied,
      );
      await browse(tester, results: [venue()], locationSource: location);

      await tapChip(tester, 'Show distances');
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(location.requestCount, 1);
      expect(find.textContaining('browsing works without it'), findsOneWidget);
    });

    testWidgets('location off is reported differently from a refusal',
        (tester) async {
      await browse(
        tester,
        results: [venue()],
        locationSource: FakeLocationSource(
          granted: false,
          status: LocationStatus.servicesOff,
        ),
      );

      await tapChip(tester, 'Show distances');
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(find.textContaining('switched off on this phone'), findsOneWidget);
    });

    testWidgets('with a fix, cards show how far away each venue is',
        (tester) async {
      await browse(
        tester,
        results: [venue()],
        locationSource: FakeLocationSource(position: here),
      );

      // ~500 m north of the customer.
      expect(find.textContaining('m away'), findsOneWidget);
    });

    testWidgets('sorting by distance appears only with a fix', (tester) async {
      await browse(
        tester,
        results: [venue()],
        locationSource: FakeLocationSource(position: here),
      );

      expect(find.text('Nearest'), findsOneWidget);
      expect(find.text('Show distances'), findsNothing);
    });

    testWidgets('nearest first reorders the list', (tester) async {
      await browse(
        tester,
        results: [
          // Labé, ~253 km away, listed first by the API.
          venue(id: 8, name: 'Far Venue', lat: '11.318056', lon: '-12.283056'),
          venue(id: 7, name: 'Near Venue'),
        ],
        locationSource: FakeLocationSource(position: here),
      );

      List<String> order() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s == 'Near Venue' || s == 'Far Venue')
          .toList();

      expect(order(), ['Far Venue', 'Near Venue']);

      await tapChip(tester, 'Nearest');

      expect(order(), ['Near Venue', 'Far Venue']);
    });

    testWidgets('a venue with no coordinates shows no distance and sinks',
        (tester) async {
      await browse(
        tester,
        results: [
          venue(id: 9, name: 'Unmapped', lat: null, lon: null),
          venue(id: 7, name: 'Mapped'),
        ],
        locationSource: FakeLocationSource(position: here),
      );

      await tapChip(tester, 'Nearest');

      final order = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s == 'Mapped' || s == 'Unmapped')
          .toList();
      // Unmapped goes last rather than sorting as if it were at the origin.
      expect(order, ['Mapped', 'Unmapped']);
    });
  });

  group('get directions', () {
    Future<FakeDirectionsLauncher> openVenue(
      WidgetTester tester, {
      Object? lat = '9.509167',
      Object? lon = '-13.712222',
    }) async {
      final launcher = FakeDirectionsLauncher();
      final (:app, :backend, :store) =
          buildApp(tester, directionsLauncher: launcher);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [
          {...establishmentJson(), 'latitude': lat, 'longitude': lon},
        ],
      });
      backend.on('GET', '/api/establishments/7/', {
        ...establishmentDetailJson(),
        'latitude': lat,
        'longitude': lon,
      });
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availabilityJson(),
      );
      backend.on('GET', '/api/establishments/7/reviews/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/establishments/7/photos/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();
      return launcher;
    }

    testWidgets('a mapped venue offers directions', (tester) async {
      await openVenue(tester);
      expect(find.text('Get directions'), findsOneWidget);
    });

    testWidgets('an unmapped venue does not', (tester) async {
      await openVenue(tester, lat: null, lon: null);
      expect(find.text('Get directions'), findsNothing);
    });

    testWidgets('tapping hands the coordinates to the maps app',
        (tester) async {
      final launcher = await openVenue(tester);

      await tester.tap(find.text('Get directions'));
      await tester.pumpAndSettle();

      expect(launcher.opened, hasLength(1));
      expect(launcher.opened.single.latitude, closeTo(9.509167, 0.000001));
      expect(launcher.opened.single.longitude, closeTo(-13.712222, 0.000001));
      expect(launcher.lastLabel, 'Le Petit Baobab');
    });

    testWidgets('directions work without a location fix', (tester) async {
      // Only the venue's coordinates are needed to navigate to it.
      final launcher = await openVenue(tester);

      await tester.tap(find.text('Get directions'));
      await tester.pumpAndSettle();

      expect(launcher.opened, hasLength(1));
    });

    testWidgets('a phone with no maps app is told so, not left silent',
        (tester) async {
      final launcher = FakeDirectionsLauncher(succeeds: false);
      final (:app, :backend, :store) =
          buildApp(tester, directionsLauncher: launcher);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [
          {
            ...establishmentJson(),
            'latitude': '9.509167',
            'longitude': '-13.712222',
          },
        ],
      });
      backend.on('GET', '/api/establishments/7/', {
        ...establishmentDetailJson(),
        'latitude': '9.509167',
        'longitude': '-13.712222',
      });
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availabilityJson(),
      );
      backend.on('GET', '/api/establishments/7/reviews/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/establishments/7/photos/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get directions'));
      await tester.pumpAndSettle();

      expect(find.text('No maps app found on this phone.'), findsOneWidget);
    });
  });

  group('establishment branding', () {
    Future<void> openVenue(WidgetTester tester, {String? preset}) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [
          {...establishmentJson(), 'theme_preset': preset},
        ],
      });
      backend.on('GET', '/api/establishments/7/', {
        ...establishmentDetailJson(),
        'theme_preset': preset,
      });
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availabilityJson(),
      );
      backend.on('GET', '/api/establishments/7/reviews/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/establishments/7/photos/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();
    }

    /// The theme actually in force inside the detail screen.
    ColorScheme schemeInDetail(WidgetTester tester) {
      final context = tester.element(find.text('Available times'));
      return Theme.of(context).colorScheme;
    }

    // One test per preset, so each gets a fresh tester — sharing one leaves
    // the previous screen in the tree and the assertion reads the old theme.
    for (final preset in themePresets) {
      testWidgets('the detail screen renders under ${preset.name}',
          (tester) async {
        await openVenue(tester, preset: preset.key);

        // Intact under each one, not merely recoloured.
        expect(find.text('Available times'), findsOneWidget);
        expect(find.text('Kaloum, Conakry'), findsOneWidget);
        expect(schemeInDetail(tester).primary, preset.accent);
      });
    }

    testWidgets('a venue with no preset gets the default', (tester) async {
      await openVenue(tester, preset: null);

      expect(
        schemeInDetail(tester).primary,
        themePresetFor('ember').accent,
      );
    });

    testWidgets('an unknown preset falls back rather than breaking',
        (tester) async {
      // A preset a newer server knows and this build does not.
      await openVenue(tester, preset: 'neon_disco');

      expect(find.text('Available times'), findsOneWidget);
      expect(
        schemeInDetail(tester).primary,
        themePresetFor('ember').accent,
      );
    });

    testWidgets('the browse screen keeps the app theme whatever the venue uses',
        (tester) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [
          // A loud preset that must not leak into the chrome.
          {...establishmentJson(), 'theme_preset': 'bissap'},
        ],
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final browseScheme =
          Theme.of(tester.element(find.text('Find a table'))).colorScheme;
      expect(
        browseScheme.primary,
        isNot(themePresetFor('bissap').accent),
      );
    });

    testWidgets('leaving the detail screen restores the app theme',
        (tester) async {
      await openVenue(tester, preset: 'bissap');
      final branded = schemeInDetail(tester).primary;

      await tester.pageBack();
      await tester.pumpAndSettle();

      final browseScheme =
          Theme.of(tester.element(find.text('Find a table'))).colorScheme;
      expect(browseScheme.primary, isNot(branded));
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

    testWidgets('every dish is a card', (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: [
          menuGroup('food', 'Food', [
            ('Poulet braisé', '75000.00'),
            ('Poisson braisé', '85000.00'),
          ]),
          menuGroup('drink', 'Drink', [('Jus de gingembre', '20000.00')]),
        ]),
      );

      expect(find.byType(MenuItemCard), findsNWidgets(3));
    });

    testWidgets('a dish with a picture shows it', (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: [
          menuGroup(
            'food',
            'Food',
            [('Poulet braisé', '75000.00')],
            images: {
              'Poulet braisé': 'http://localhost:8000/media/poulet.jpg',
            },
          ),
        ]),
      );

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(MenuItemCard),
          matching: find.byType(Image),
        ),
      );
      expect(
        (image.image as NetworkImage).url,
        'http://localhost:8000/media/poulet.jpg',
      );
    });

    testWidgets('a dish with no picture still gets a card', (tester) async {
      // The common case for a while yet: merchants type the menu in long
      // before they photograph it.
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: [
          menuGroup('food', 'Food', [('Poulet braisé', '75000.00')]),
        ]),
      );

      expect(find.byType(MenuItemCard), findsOneWidget);
      expect(find.text('Poulet braisé'), findsOneWidget);
      expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a description is shown under the price when there is one',
        (tester) async {
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: [
          menuGroup(
            'food',
            'Food',
            [('Poulet braisé', '75000.00')],
            description: 'Grilled over charcoal, served with attiéké.',
          ),
        ]),
      );

      expect(
        find.text('Grilled over charcoal, served with attiéké.'),
        findsOneWidget,
      );
    });

    testWidgets('a long menu lays out at 360dp without overflowing',
        (tester) async {
      // Two columns of cards, long names, no picture: the layout that would
      // break first.
      await openVenue(
        tester,
        detail: establishmentDetailJson(menu: [
          menuGroup('food', 'Food', [
            for (var i = 0; i < 9; i++)
              ('Poulet braisé aux épices numéro $i', '75000.00'),
          ]),
        ]),
      );

      // Reaching the bottom of the section is the assertion: an overflow or a
      // failed layout would have thrown by now.
      // .first is the screen's own ListView; the pickers further down have
      // horizontal scrollables of their own.
      await tester.scrollUntilVisible(
        find.text('Available times'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Available times'), findsOneWidget);
    });
  });

  group('reviews and photos on the detail screen', () {
    Map<String, dynamic> reviewJson({
      int id = 1,
      int rating = 5,
      String comment = 'Excellent night.',
      String author = 'Mariama',
    }) =>
        {
          'id': id,
          'rating': rating,
          'comment': comment,
          'author': author,
          'created_at': '2026-07-20T20:00:00Z',
        };

    Map<String, dynamic> photoJson({
      int id = 1,
      String caption = 'Terrace',
      String role = 'merchant',
    }) =>
        {
          'id': id,
          'image': 'http://localhost:8000/media/establishments/7/a.jpg',
          'caption': caption,
          'uploaded_by_role': role,
          'uploaded_by_role_display':
              role == 'merchant' ? 'Merchant' : 'Customer',
          'created_at': '2026-07-20T20:00:00Z',
        };

    Future<FakeBackend> openVenue(
      WidgetTester tester, {
      double? averageRating,
      int reviewCount = 0,
      List<Map<String, dynamic>> reviews = const [],
      List<Map<String, dynamic>> photos = const [],
    }) async {
      final (:app, :backend, :store) = buildApp(tester);
      backend.on('GET', '/api/establishments/', {
        'count': 1,
        'next': null,
        'results': [establishmentJson()],
      });
      backend.on('GET', '/api/establishments/7/', {
        ...establishmentDetailJson(),
        'average_rating': averageRating,
        'review_count': reviewCount,
      });
      backend.on(
        'GET',
        '/api/establishments/7/availability/',
        availabilityJson(),
      );
      backend.on('GET', '/api/establishments/7/reviews/', {
        'count': reviews.length,
        'next': null,
        'results': reviews,
      });
      backend.on('GET', '/api/establishments/7/photos/', {
        'count': photos.length,
        'next': null,
        'results': photos,
      });

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('a venue with no reviews invites the first one',
        (tester) async {
      await openVenue(tester);

      expect(
        find.text('No reviews yet — be the first after your visit.'),
        findsOneWidget,
      );
    });

    testWidgets('the average rating is shown when there are reviews',
        (tester) async {
      await openVenue(
        tester,
        averageRating: 4.5,
        reviewCount: 2,
        reviews: [reviewJson(), reviewJson(id: 2, rating: 4)],
      );

      expect(find.text('4.5'), findsWidgets);
      expect(find.text('2 reviews'), findsOneWidget);
    });

    testWidgets('individual reviews are listed', (tester) async {
      await openVenue(
        tester,
        averageRating: 5.0,
        reviewCount: 1,
        reviews: [reviewJson(comment: 'Best chicha in Conakry.')],
      );

      expect(find.text('Best chicha in Conakry.'), findsOneWidget);
      expect(find.text('Mariama'), findsOneWidget);
    });

    testWidgets('a review with no comment still renders', (tester) async {
      await openVenue(
        tester,
        averageRating: 3.0,
        reviewCount: 1,
        reviews: [reviewJson(comment: '', rating: 3)],
      );

      expect(find.text('Mariama'), findsOneWidget);
    });

    testWidgets('photos render when the venue has them', (tester) async {
      await openVenue(tester, photos: [photoJson(caption: 'Our terrace')]);

      expect(find.text('Our terrace'), findsOneWidget);
    });

    testWidgets('a venue with no photos shows no photo strip', (tester) async {
      await openVenue(tester);

      expect(find.byType(Image), findsNothing);
    });
  });

  group('sharing a photo', () {
    Future<({FakeBackend backend, FakeImageSource picker})> openMyBookings(
      WidgetTester tester, {
      bool cancels = false,
      String reservationStatus = 'completed',
    }) async {
      final picker = FakeImageSource(cancels: cancels);
      final (:app, :backend, :store) = buildApp(
        tester,
        bookingReferences: [testReference],
        imageSource: picker,
      );
      backend.on('GET', '/api/establishments/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on(
        'GET',
        '/api/reservations/ref/$testReference/',
        reservationJson(status: reservationStatus, canCancel: false),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookings'));
      await tester.pumpAndSettle();
      return (backend: backend, picker: picker);
    }

    testWidgets('every booking offers to share a photo', (tester) async {
      await openMyBookings(tester, reservationStatus: 'pending');

      // Any status: someone turned away still has something to show.
      expect(find.text('Add a photo'), findsOneWidget);
    });

    testWidgets('backing out of the picker does nothing', (tester) async {
      final (:backend, :picker) = await openMyBookings(tester, cancels: true);

      await tester.tap(find.text('Add a photo'));
      await tester.pumpAndSettle();

      expect(picker.pickCount, 1);
      // No caption dialog, no request.
      expect(find.text('Add a caption'), findsNothing);
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('a picked photo is uploaded with the booking reference',
        (tester) async {
      final (:backend, :picker) = await openMyBookings(tester);
      backend.on('POST', '/api/establishments/7/photos/', {
        'id': 1,
        'image': 'http://localhost:8000/media/establishments/7/a.jpg',
        'caption': 'Great night',
        'uploaded_by_role': 'customer',
        'uploaded_by_role_display': 'Customer',
        'created_at': '2026-07-28T20:00:00Z',
      });

      await tester.tap(find.text('Add a photo'));
      await tester.pumpAndSettle();
      expect(find.text('Add a caption'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Great night');
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      final posted = backend.requests
          .firstWhere((r) => r.url.path == '/api/establishments/7/photos/');
      // Multipart, carrying the reference that proves the visit.
      expect(posted.headers['content-type'], contains('multipart/form-data'));
      expect(posted.body, contains(testReference));
      expect(find.text('Thanks — your photo is shared.'), findsOneWidget);
    });

    testWidgets('a rejected upload is reported', (tester) async {
      final (:backend, :picker) = await openMyBookings(tester);
      backend.on(
        'POST',
        '/api/establishments/7/photos/',
        {'image': ['That image is too large. The limit is 5 MB.']},
        status: 400,
      );

      await tester.tap(find.text('Add a photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.textContaining('too large'), findsOneWidget);
    });
  });

  group('writing a review', () {
    Future<({FakeBackend backend, InMemoryBookingStore store})> openMyBookings(
      WidgetTester tester, {
      required String reservationStatus,
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
        reservationJson(status: reservationStatus, canCancel: false),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookings'));
      await tester.pumpAndSettle();
      return (backend: backend, store: store);
    }

    testWidgets('a completed visit offers to be reviewed', (tester) async {
      await openMyBookings(tester, reservationStatus: 'completed');

      expect(find.text('Write a review'), findsOneWidget);
    });

    testWidgets('a pending booking does not offer a review', (tester) async {
      await openMyBookings(tester, reservationStatus: 'pending');

      expect(find.text('Write a review'), findsNothing);
    });

    testWidgets('the review form opens with the venue named', (tester) async {
      await openMyBookings(tester, reservationStatus: 'completed');

      await tester.tap(find.text('Write a review'));
      await tester.pumpAndSettle();

      expect(find.text('How was it?'), findsOneWidget);
      expect(find.text('Le Petit Baobab'), findsWidgets);
      expect(find.text('Only your first name is shown.'), findsOneWidget);
    });

    testWidgets('posting without a rating is refused locally', (tester) async {
      final (:backend, :store) =
          await openMyBookings(tester, reservationStatus: 'completed');

      await tester.tap(find.text('Write a review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a rating from 1 to 5.'), findsOneWidget);
      expect(
        backend.requests.where((r) => r.method == 'POST'),
        isEmpty,
      );
    });

    testWidgets('a rating and comment are posted', (tester) async {
      final (:backend, :store) =
          await openMyBookings(tester, reservationStatus: 'completed');
      backend.on('POST', '/api/establishments/7/reviews/', {
        'id': 1,
        'rating': 5,
        'comment': 'Lovely',
        'author': 'Mariama',
        'created_at': '2026-07-28T20:00:00Z',
      });

      await tester.tap(find.text('Write a review'));
      await tester.pumpAndSettle();
      // Fifth star.
      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Lovely');
      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();

      final posted = backend.requests
          .firstWhere((r) => r.url.path == '/api/establishments/7/reviews/');
      final body = jsonDecode(posted.body) as Map<String, dynamic>;
      expect(body['rating'], 5);
      expect(body['comment'], 'Lovely');
      expect(body['reservation_reference'], testReference);
    });

    testWidgets('the server refusing is shown to the customer', (tester) async {
      final (:backend, :store) =
          await openMyBookings(tester, reservationStatus: 'completed');
      backend.on(
        'POST',
        '/api/establishments/7/reviews/',
        {
          'reservation_reference': ['This visit has already been reviewed.'],
        },
        status: 400,
      );

      await tester.tap(find.text('Write a review'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already been reviewed'), findsOneWidget);
      // Still on the form rather than pretending it worked.
      expect(find.text('Post review'), findsOneWidget);
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
      await tester.tap(find.text('Bookings'));
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
      await tester.tap(find.text('Bookings'));
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
      await tester.tap(find.text('Bookings'));
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
      await tester.tap(find.text('Bookings'));
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
      await tester.tap(find.text('Bookings'));
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
