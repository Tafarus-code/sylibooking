import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merchant_app/src/app.dart';
import 'package:merchant_app/src/auth_controller.dart';
import 'package:merchant_app/src/image_source.dart';
import 'package:merchant_app/src/token_store.dart';
import 'package:merchant_app/src/screens/orders_screen.dart';
import 'package:merchant_app/src/widgets/reservation_card.dart';
import 'package:shared_client/shared_client.dart';

/// A locale store whose read is held open until the test lets it finish.
///
/// The in-memory one resolves in a microtask, which a single pump flushes —
/// so it cannot tell "waited for the language" apart from "did not wait".
class SlowLocaleStore implements LocaleStore {
  SlowLocaleStore(this._code);

  final String? _code;
  final _gate = Completer<void>();

  void finishRead() => _gate.complete();

  @override
  Future<String?> readLanguageCode() async {
    await _gate.future;
    return _code;
  }

  @override
  Future<void> writeLanguageCode(String code) async {}
}

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
}

Map<String, dynamic> user({List<Map<String, dynamic>>? establishments}) => {
      'id': 1,
      'username': 'amadou',
      'first_name': 'Amadou',
      'last_name': '',
      'is_superuser': false,
      'establishments': establishments ??
          [
            {
              'id': 7,
              'name': 'Le Petit Baobab',
              'city': 'Conakry',
              'type': 'lounge',
            },
          ],
    };

/// A booking today at a fixed hour, so the "Today" view always includes it.
Map<String, dynamic> paymentJson({
  String provider = 'orange_money',
  String status = 'completed',
  String amount = '50000.00',
  String? reference = 'MOCK-A4A546A240074095',
}) =>
    {
      'id': 1,
      'provider': provider,
      'provider_display': switch (provider) {
        'orange_money' => 'Orange Money',
        'mtn_money' => 'MTN Mobile Money',
        _ => 'Cash on arrival',
      },
      'amount': amount,
      'status': status,
      'status_display': status[0].toUpperCase() + status.substring(1),
      'provider_reference': reference,
      'created_at': '2026-08-01T18:00:00Z',
    };

/// A booking whose time is still ahead, whatever hour the suite runs at.
///
/// The default fixture sits at today 19:00, which is in the past if the
/// tests run in the evening — the same trap the kitchen queue fell into.
Map<String, dynamic> futureBooking({
  int id = 1,
  String status = 'confirmed',
}) {
  final ahead = DateTime.now().add(const Duration(hours: 3));
  return {
    ...booking(id: id, status: status),
    'datetime': ahead.toUtc().toIso8601String(),
  };
}

/// A booking whose time has already passed, so it can be closed.
///
/// The desk only offers "Mark arrived" once the sitting has begun, so a
/// fixture at the default 19:00 cannot exercise it before that hour.
Map<String, dynamic> startedBooking({
  int id = 1,
  String status = 'confirmed',
}) {
  final started = DateTime.now().subtract(const Duration(hours: 1));
  return {
    ...booking(id: id, status: status),
    'datetime': started.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> booking({
  int id = 1,
  String status = 'pending',
  String customer = 'Mariama Diallo',
  String paymentProvider = 'cash_on_arrival',
  String? paymentStatus,
  bool isPaid = false,
  bool? canConfirm,
  Map<String, dynamic>? payment,
  String reference = '11111111-2222-3333-4444-555555555555',
}) {
  final now = DateTime.now();
  final when = DateTime(now.year, now.month, now.day, 19).toUtc();
  return {
    'id': id,
    'reference': reference,
    'space': 3,
    'space_name': 'Table 4',
    'establishment': 7,
    'establishment_name': 'Le Petit Baobab',
    'customer_name': customer,
    'customer_phone': '+224 620 00 00 00',
    'datetime': when.toIso8601String(),
    'party_size': 2,
    'status': status,
    'status_display': status[0].toUpperCase() + status.substring(1),
    'payment_provider': paymentProvider,
    'payment_provider_display': switch (paymentProvider) {
      'orange_money' => 'Orange Money',
      'mtn_money' => 'MTN Mobile Money',
      _ => 'Cash on arrival',
    },
    'payment_status': paymentStatus,
    'is_paid': isPaid,
    // Mirrors the server: cash and paid bookings are confirmable, an unpaid
    // mobile money one is not.
    'can_confirm': canConfirm ??
        (status == 'pending' &&
            !(paymentProvider != 'cash_on_arrival' && !isPaid)),
    'payment': payment,
  };
}

/// A booking paid in full through a provider.
Map<String, dynamic> paidBooking({
  String provider = 'orange_money',
  int id = 1,
  String customer = 'Mariama Diallo',
  String status = 'pending',
}) =>
    booking(
      id: id,
      customer: customer,
      status: status,
      paymentProvider: provider,
      paymentStatus: 'completed',
      isPaid: true,
      payment: paymentJson(provider: provider),
    );

/// A mobile money booking whose money has not arrived.
Map<String, dynamic> unpaidBooking({
  String provider = 'orange_money',
  String paymentStatus = 'pending',
  int id = 1,
  String customer = 'Mariama Diallo',
}) =>
    booking(
      id: id,
      customer: customer,
      paymentProvider: provider,
      paymentStatus: paymentStatus,
      isPaid: false,
      payment: paymentJson(provider: provider, status: paymentStatus),
    );

/// The card's actions are built with `FilledButton.icon`/`TextButton.icon`,
/// whose runtime type is a private subclass. `find.byType` matches exact types,
/// so match on the visible label instead, which is what a merchant taps anyway.
final confirmButton = find.text('Confirm');
final cancelButton = find.text('Cancel');

/// The three shapes the app has to survive, in logical pixels.
///
/// A merchant might work the door on a phone and do the books on a laptop, so
/// all three are real. 834x1112 is an iPad in portrait, 1440x900 a laptop.
const phoneSize = Size(360, 900);
const tabletSize = Size(834, 1112);
const desktopSize = Size(1440, 900);

/// A phone turned sideways: short, not narrow. The shape that catches anything
/// assuming vertical room, and the one a rail has least height to work with.
const landscapePhoneSize = Size(900, 360);

({AuthController auth, FakeBackend backend}) buildAuth(
  WidgetTester tester, {
  String? storedToken,
  Size size = phoneSize,
}) {
  // A merchant reads this on a phone in a dim lounge, not on an 800x600
  // desktop surface. Testing at 360x900 is what surfaced two overflow bugs in
  // the customer app, so this app is held to the same width.
  tester.view.physicalSize = size * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final backend = FakeBackend();
  // Every signed-in path loads the venue list. One venue by default, so the
  // switcher stays out of the way; tests that need several override this.
  backend.on('GET', '/api/merchant/establishments/', {
    'results': [venueJson()],
  });

  final auth = AuthController(
    api: SylibookingApi(
      baseUrl: 'http://localhost:8000/api',
      httpClient: backend.client,
    ),
    tokenStore: InMemoryTokenStore(storedToken),
  );
  return (auth: auth, backend: backend);
}

Map<String, dynamic> venueJson({
  int id = 7,
  String name = 'Le Petit Baobab',
  String city = 'Conakry',
  String role = 'owner',
}) =>
    {
      'id': id,
      'name': name,
      'type': 'lounge',
      'city': city,
      'address': 'Kaloum',
      'tagline': '',
      'role': role,
      'role_display': role[0].toUpperCase() + role.substring(1),
      'can_edit_profile': role == 'owner' || role == 'manager',
      'can_manage_staff': role == 'owner',
    };

void main() {
  group('the kitchen queue', () {
    Map<String, dynamic> orderJson({
      int id = 1,
      String customer = 'Mariama Diallo',
      String status = 'placed',
      String? paymentProvider,
      bool isPaid = false,
      bool? canAdvance,
      int? reservation,
    }) =>
        {
          'id': id,
          'reference': 'order-ref-$id',
          'establishment': 7,
          'establishment_name': 'Le Petit Baobab',
          'reservation': reservation,
          'customer_name': customer,
          'customer_phone': '+224 620 00 00 00',
          'pickup_time': DateTime.now()
              .add(const Duration(hours: 2))
              .toUtc()
              .toIso8601String(),
          'status': status,
          'status_display': status[0].toUpperCase() + status.substring(1),
          'created_at': '2026-08-01T18:00:00Z',
          'items': [
            {
              'id': id,
              'menu_item': 1,
              'menu_item_name': 'Poulet braisé',
              'quantity': 2,
              'unit_price_at_order': '75000.00',
              'line_total': '150000.00',
            },
          ],
          'total': '150000.00',
          'payment_provider': paymentProvider,
          'payment_provider_display': switch (paymentProvider) {
            'orange_money' => 'Orange Money',
            'mtn_money' => 'MTN Mobile Money',
            _ => 'Cash on arrival',
          },
          'payment_status': paymentProvider == null
              ? null
              : (isPaid ? 'completed' : 'pending'),
          'is_paid': isPaid,
          // Mirrors the server: cash advances freely, unpaid mobile money
          // does not.
          'can_advance': canAdvance ??
              (paymentProvider == null ||
                  paymentProvider == 'cash_on_arrival' ||
                  isPaid),
          'next_status': switch (status) {
            'placed' => 'preparing',
            'preparing' => 'ready',
            'ready' => 'completed',
            _ => null,
          },
        };

    /// Signs in and opens the Orders tab.
    Future<FakeBackend> openQueue(
      WidgetTester tester,
      List<Map<String, dynamic>> orders, {
      String role = 'owner',
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(role: role)],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': orders});

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      // Orders is a tab on the venue desk, not its own navigation destination.
      await tester.tap(find.text('Commandes'));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('the queue is reachable from the shell', (tester) async {
      await openQueue(tester, [orderJson()]);

      expect(find.text('Mariama Diallo'), findsOneWidget);
    });

    testWidgets('a ticket shows what to cook and when it is wanted',
        (tester) async {
      await openQueue(tester, [orderJson()]);

      expect(find.text('Poulet braisé'), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);
      expect(find.text('150000.00 GNF'), findsOneWidget);
    });

    testWidgets('tickets are grouped by stage, not mixed by time',
        (tester) async {
      await openQueue(tester, [
        orderJson(id: 1, customer: 'Mariama Diallo'),
        orderJson(id: 2, customer: 'Ibrahima Sory', status: 'preparing'),
        orderJson(id: 3, customer: 'Aïssatou Bah', status: 'ready'),
      ]);

      expect(find.text('Ready to collect · 1'), findsOneWidget);
      expect(find.text('Being prepared · 1'), findsOneWidget);
      expect(find.text('New orders · 1'), findsOneWidget);
    });

    testWidgets('finished tickets drop off the queue', (tester) async {
      await openQueue(tester, [
        orderJson(id: 1, status: 'completed', customer: 'Gone'),
        orderJson(id: 2, status: 'cancelled', customer: 'Also gone'),
      ]);

      expect(find.text('Nothing in the queue'), findsOneWidget);
    });

    testWidgets('an empty queue says so', (tester) async {
      await openQueue(tester, const []);

      expect(find.text('Nothing in the queue'), findsOneWidget);
    });

    testWidgets('the button names the next step', (tester) async {
      await openQueue(tester, [
        orderJson(id: 1),
        orderJson(id: 2, status: 'preparing', customer: 'Ibrahima'),
        orderJson(id: 3, status: 'ready', customer: 'Aïssatou'),
      ]);

      expect(find.text('Start preparing'), findsOneWidget);
      expect(find.text('Mark ready'), findsOneWidget);
      expect(find.text('Collected'), findsOneWidget);
    });

    testWidgets('advancing a cash order updates the ticket in place',
        (tester) async {
      final backend = await openQueue(tester, [orderJson()]);
      backend.on(
        'POST',
        '/api/merchant/orders/1/status/',
        orderJson(status: 'preparing'),
      );

      await tester.tap(find.text('Start preparing'));
      await tester.pumpAndSettle();

      expect(find.text('Mark ready'), findsOneWidget);
      expect(find.text('Being prepared · 1'), findsOneWidget);
    });

    testWidgets('the requested status is what gets sent', (tester) async {
      final backend = await openQueue(tester, [orderJson()]);
      backend.on(
        'POST',
        '/api/merchant/orders/1/status/',
        orderJson(status: 'preparing'),
      );

      await tester.tap(find.text('Start preparing'));
      await tester.pumpAndSettle();

      final post = backend.requests.firstWhere(
        (r) => r.url.path == '/api/merchant/orders/1/status/',
      );
      final sent = jsonDecode(post.body) as Map<String, dynamic>;
      expect(sent['status'], 'preparing');
    });

    testWidgets('an unpaid mobile money ticket cannot be started',
        (tester) async {
      await openQueue(tester, [
        orderJson(paymentProvider: 'orange_money'),
      ]);

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Start preparing'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('and it says why, rather than just greying out',
        (tester) async {
      await openQueue(tester, [
        orderJson(paymentProvider: 'orange_money'),
      ]);

      expect(find.textContaining('cannot start'), findsOneWidget);
      expect(find.text('Unpaid'), findsOneWidget);
    });

    testWidgets('a paid mobile money ticket works normally', (tester) async {
      await openQueue(tester, [
        orderJson(paymentProvider: 'orange_money', isPaid: true),
      ]);

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Start preparing'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text('Paid (Orange Money)'), findsOneWidget);
    });

    testWidgets('a cash ticket is badged as cash, not as unpaid',
        (tester) async {
      await openQueue(tester, [orderJson()]);

      expect(find.text('Cash on pickup'), findsOneWidget);
      expect(find.text('Unpaid'), findsNothing);
    });

    testWidgets('an unpaid ticket can still be cancelled', (tester) async {
      await openQueue(tester, [
        orderJson(paymentProvider: 'orange_money'),
      ]);

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('cancelling asks first', (tester) async {
      await openQueue(tester, [orderJson()]);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel this order?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(find.text('Mariama Diallo'), findsOneWidget);
    });

    testWidgets('a server refusal is surfaced, not swallowed', (tester) async {
      final backend = await openQueue(tester, [orderJson()]);
      backend.on(
        'POST',
        '/api/merchant/orders/1/status/',
        {'detail': 'Orange Money payment is pending. Start this order once '
            'the payment completes, or cancel it.'},
        status: 409,
      );

      await tester.tap(find.text('Start preparing'));
      await tester.pumpAndSettle();

      expect(find.textContaining('payment is pending'), findsOneWidget);
    });

    testWidgets('an order for a table is marked as one', (tester) async {
      await openQueue(tester, [orderJson(reservation: 5)]);

      expect(find.text('At their table'), findsOneWidget);
    });

    testWidgets('a plain pickup is not', (tester) async {
      await openQueue(tester, [orderJson()]);

      expect(find.text('At their table'), findsNothing);
    });

    testWidgets('staff can work the queue', (tester) async {
      // Running the floor is operations, whatever the role.
      final backend = await openQueue(tester, [orderJson()], role: 'staff');
      backend.on(
        'POST',
        '/api/merchant/orders/1/status/',
        orderJson(status: 'preparing'),
      );

      await tester.tap(find.text('Start preparing'));
      await tester.pumpAndSettle();

      expect(find.text('Mark ready'), findsOneWidget);
    });

    testWidgets('the queue is requested for the selected venue only',
        (tester) async {
      final backend = await openQueue(tester, [orderJson()]);

      final request = backend.requests.lastWhere(
        (r) => r.url.path == '/api/merchant/orders/',
      );
      expect(request.url.queryParameters['establishment'], '7');
    });

    testWidgets('each ticket carries a badge for where it has got to',
        (tester) async {
      await openQueue(tester, [
        orderJson(id: 1),
        orderJson(id: 2, status: 'preparing', customer: 'Ibrahima'),
        orderJson(id: 3, status: 'ready', customer: 'Aïssatou'),
      ]);

      // Badge language, not just a heading: the state travels with the ticket.
      expect(
        find.descendant(
          of: find.byType(OrderStatusBadge),
          matching: find.text('Placed'),
        ),
        findsOneWidget,
      );
      expect(find.byType(OrderStatusBadge), findsNWidgets(3));
    });

    testWidgets('each state gets its own colour', (tester) async {
      await openQueue(tester, [
        orderJson(id: 1),
        orderJson(id: 2, status: 'preparing', customer: 'Ibrahima'),
        orderJson(id: 3, status: 'ready', customer: 'Aïssatou'),
      ]);

      final colours = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(OrderStatusBadge),
              matching: find.byType(Container),
            ),
          )
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .toSet();

      expect(colours, hasLength(3));
    });
  });

  group('the venue desk switcher', () {
    Future<FakeBackend> signIn(
      WidgetTester tester, {
      String preset = 'ember',
      List<Map<String, dynamic>>? orders,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [
          {...venueJson(), 'theme_preset': preset},
        ],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 1,
        'next': null,
        'results': [paidBooking()],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': orders ?? []});

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('both queues live on one screen', (tester) async {
      await signIn(tester);

      expect(find.text('Réservations'), findsOneWidget);
      expect(find.text('Commandes'), findsOneWidget);
    });

    testWidgets('orders are not a separate navigation destination',
        (tester) async {
      await signIn(tester);

      // Same job as reservations: someone arriving at a time, and something
      // owed to them when they do.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Orders'), findsNothing);
    });

    testWidgets('switching to orders and back keeps the date range',
        (tester) async {
      final backend = await signIn(tester);

      await tester.tap(find.text('Next 7 days'));
      await tester.pumpAndSettle();
      final callsBefore =
          backend.requests.where((r) => r.url.path == '/api/reservations/');
      final rangeRequest = callsBefore.last.url.queryParameters;

      await tester.tap(find.text('Commandes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations'));
      await tester.pumpAndSettle();

      // The week range survived the round trip, and nothing refetched.
      expect(find.text('Next 7 days'), findsOneWidget);
      expect(
        backend.requests
            .where((r) => r.url.path == '/api/reservations/')
            .last
            .url
            .queryParameters,
        rangeRequest,
      );
    });

    testWidgets('switching tabs does not refetch either queue',
        (tester) async {
      final backend = await signIn(tester);
      int calls(String path) =>
          backend.requests.where((r) => r.url.path == path).length;

      final reservations = calls('/api/reservations/');
      final orders = calls('/api/merchant/orders/');

      await tester.tap(find.text('Commandes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations'));
      await tester.pumpAndSettle();

      expect(calls('/api/reservations/'), reservations);
      expect(calls('/api/merchant/orders/'), orders);
    });

    testWidgets('the orders queue keeps its own state across a switch',
        (tester) async {
      await signIn(tester, orders: [
        {
          'id': 1,
          'reference': 'order-ref-1',
          'establishment': 7,
          'establishment_name': 'Le Petit Baobab',
          'reservation': null,
          'customer_name': 'Mariama Diallo',
          'customer_phone': '+224 620 00 00 00',
          'pickup_time': DateTime.now()
              .add(const Duration(hours: 2))
              .toUtc()
              .toIso8601String(),
          'status': 'placed',
          'status_display': 'Placed',
          'created_at': '2026-08-01T18:00:00Z',
          'items': const [],
          'total': '150000.00',
          'payment_provider': null,
          'payment_provider_display': 'Cash on arrival',
          'payment_status': null,
          'is_paid': false,
          'can_advance': true,
          'next_status': 'preparing',
        },
      ]);

      await tester.tap(find.text('Commandes'));
      await tester.pumpAndSettle();
      expect(find.text('Mariama Diallo'), findsOneWidget);

      await tester.tap(find.text('Réservations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commandes'));
      await tester.pumpAndSettle();

      expect(find.text('Mariama Diallo'), findsOneWidget);
    });

    testWidgets('the desk carries the venue own branding', (tester) async {
      await signIn(tester, preset: 'bissap');
      await tester.tap(find.text('Commandes'));
      await tester.pumpAndSettle();

      // A venue's own screens look like the venue, the way a customer sees it.
      final scheme = Theme.of(
        tester.element(find.text('Nothing in the queue')),
      ).colorScheme;
      expect(scheme.primary, themePresetFor('bissap').accent);
    });

    testWidgets('but the chrome around it does not', (tester) async {
      await signIn(tester, preset: 'bissap');

      // The navigation is the app, not the venue.
      final scheme =
          Theme.of(tester.element(find.text('Payments'))).colorScheme;
      expect(scheme.primary, SylibookingTokens.ember);
    });
  });

  group('phone, tablet and desktop', () {
    /// Signs in at [size] and walks every tab.
    ///
    /// A RenderFlex overflow or a failed layout throws inside pump, so walking
    /// the app at a size is itself the assertion.
    Future<void> walkTheApp(WidgetTester tester, Size size) async {
      final (:auth, :backend) = buildAuth(
        tester,
        storedToken: 'stored-token',
        size: size,
      );
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 3,
        'next': null,
        'results': [
          paidBooking(),
          unpaidBooking(id: 2, customer: 'Ibrahima Sory Barry'),
          booking(id: 3, customer: 'Aïssatou Bah', status: 'confirmed'),
        ],
      });
      backend.on('GET', '/api/dashboard/payments/', {
        'period': {'from': '2026-07-01', 'to': '2026-07-30'},
        'establishments': [
          {'id': 7, 'name': 'Le Petit Baobab'},
        ],
        'reservations': {
          'total': 10,
          'pending': 2,
          'confirmed': 6,
          'cancelled': 1,
          'completed': 1,
        },
        'payments': {
          'collected': '150000.00',
          'awaiting': '50000.00',
          'failed': '25000.00',
          'completed_count': 3,
          'pending_count': 1,
          'failed_count': 1,
        },
        'by_provider': [
          {
            'provider': 'orange_money',
            'provider_display': 'Orange Money',
            'bookings': 3,
            'collected': '150000.00',
            'awaiting': '50000.00',
          },
        ],
        'needs_attention': [unpaidBooking(id: 2)],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      expect(find.text('Mariama Diallo'), findsWidgets);

      for (final tab in ['Payments', 'Manage', 'Reservations']) {
        await tester.tap(find.text(tab).last);
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

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('a desktop window gets an extended rail', (tester) async {
      await walkTheApp(tester, desktopSize);

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('booking rows stop widening past a readable measure',
        (tester) async {
      await walkTheApp(tester, desktopSize);

      // A card stretched across a 1440px window puts the customer's name and
      // the Confirm button a screen apart.
      final card = tester.getSize(find.byType(ReservationCard).first);
      expect(card.width, lessThanOrEqualTo(ContentWidth.list));
    });

    // One test per size, so each gets a fresh tester: pumping a second app
    // into a tester that is still settling the first one never settles.
    for (final (label, size) in [
      ('a phone', phoneSize),
      ('a tablet', tabletSize),
      ('a desktop window', desktopSize),
    ]) {
      testWidgets('the venue picker lays out on $label', (tester) async {
        final (:auth, :backend) = buildAuth(
          tester,
          storedToken: 'stored-token',
          size: size,
        );
        backend.on('GET', '/api/auth/me/', user());
        backend.on('GET', '/api/merchant/establishments/', {
          'results': [
            venueJson(),
            venueJson(id: 8, name: 'Chez Fatou', city: 'Labé', role: 'manager'),
          ],
        });

        await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Choose a venue'), findsOneWidget);
      });
    }
  });

  group('app baseline theme', () {
    /// Signed in on the reservation list, with the theme in force there.
    Future<ThemeData> signedInTheme(
      WidgetTester tester, {
      List<Map<String, dynamic>>? venues,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': venues ?? [venueJson()],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      return Theme.of(tester.element(find.text('Reservations').first));
    }

    testWidgets('the merchant app runs on the same Ember baseline',
        (tester) async {
      final theme = await signedInTheme(tester);

      // Was a teal seed before: two apps in one product should not look like
      // two products.
      expect(theme.colorScheme.primary, SylibookingTokens.ember);
      expect(theme.colorScheme.surface, SylibookingTokens.ivory);
      expect(theme.colorScheme.onSurface, SylibookingTokens.onIvory);
    });

    testWidgets('merchant type comes from the house faces', (tester) async {
      final theme = await signedInTheme(tester);

      expect(
        theme.textTheme.bodyMedium?.fontFamily,
        contains(SylibookingTokens.bodyFont),
      );
      expect(
        theme.textTheme.titleLarge?.fontFamily,
        contains(SylibookingTokens.displayFont),
      );
    });

    testWidgets('the venue picker is app chrome, not venue branding',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [
          {...venueJson(id: 7), 'theme_preset': 'bissap'},
          {...venueJson(id: 8, name: 'Chez Fatou'), 'theme_preset': 'harmattan'},
        ],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      final scheme =
          Theme.of(tester.element(find.text('Choose a venue'))).colorScheme;
      expect(scheme.primary, SylibookingTokens.ember);
    });

    testWidgets('the login screen is themed before any venue is known',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester);

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      final scheme =
          Theme.of(tester.element(find.text('Sign in'))).colorScheme;
      expect(scheme.primary, SylibookingTokens.ember);
    });
  });

  group('login screen', () {
    testWidgets('is shown when there is no stored token', (tester) async {
      final (:auth, :backend) = buildAuth(tester);

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Reservations'), findsNothing);
    });

    testWidgets('validates empty fields before calling the API',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester);

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('shows a friendly message on bad credentials', (tester) async {
      final (:auth, :backend) = buildAuth(tester);
      backend.on('POST', '/api/auth/login/', {
        'non_field_errors': ['Unable to log in with provided credentials.'],
      }, status: 400);

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'amadou');
      await tester.enterText(find.byType(TextFormField).last, 'wrong');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong username or password.'), findsOneWidget);
    });

    testWidgets('a successful sign-in lands on the reservation list',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester);
      backend.on('POST', '/api/auth/login/', {
        'token': 'abc123',
        'user': user(),
      });
      backend.on('GET', '/api/reservations/', {
        'count': 1,
        'next': null,
        'results': [booking()],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'amadou');
      await tester.enterText(find.byType(TextFormField).last, 'pw');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      // Twice now: the app bar title and the navigation destination.
      expect(find.text('Reservations'), findsWidgets);
      // The subtitle names the venue and the role at it.
      expect(find.text('Le Petit Baobab · Owner'), findsOneWidget);
      expect(find.text('Mariama Diallo'), findsOneWidget);
    });

    testWidgets('a stored token skips the login screen', (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {'count': 0, 'results': []});

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      expect(find.text('Reservations'), findsWidgets);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('a rejected stored token falls back to login', (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'expired');
      backend.on('GET', '/api/auth/me/', {'detail': 'Invalid token.'},
          status: 401);

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('reservation list', () {
    Future<FakeBackend> signedIn(
      WidgetTester tester, {
      required Object reservationsBody,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', reservationsBody);

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('shows booking details', (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking()],
      });

      expect(find.text('Mariama Diallo'), findsOneWidget);
      expect(find.text('Table 4 · 2 guests'), findsOneWidget);
      expect(find.text('+224 620 00 00 00'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('shows an empty state when nothing is booked', (tester) async {
      await signedIn(
        tester,
        reservationsBody: {'count': 0, 'next': null, 'results': []},
      );

      expect(find.text('Nothing booked today'), findsOneWidget);
    });

    testWidgets('a pending booking offers Confirm and Cancel', (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking()],
      });

      expect(confirmButton, findsOneWidget);
      expect(cancelButton, findsOneWidget);
    });

    testWidgets('a cancelled booking offers no actions', (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking(status: 'cancelled')],
      });

      expect(find.text('Cancelled'), findsOneWidget);
      expect(confirmButton, findsNothing);
      expect(cancelButton, findsNothing);
    });

    testWidgets('confirming updates the card in place', (tester) async {
      final backend = await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking()],
      });
      backend.on(
        'POST',
        '/api/reservations/1/confirm/',
        booking(status: 'confirmed'),
      );

      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(find.text('Confirmed'), findsOneWidget);
      expect(confirmButton, findsNothing);
      expect(find.text('Reservation confirmed.'), findsOneWidget);
    });

    testWidgets('cancelling asks for confirmation first', (tester) async {
      final backend = await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking()],
      });
      backend.on(
        'POST',
        '/api/reservations/1/cancel/',
        booking(status: 'cancelled'),
      );

      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
      expect(find.text('Cancel this reservation?'), findsOneWidget);

      // Backing out leaves the booking alone.
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);

      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
    });

    testWidgets('a conflict from the server is surfaced', (tester) async {
      final backend = await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking()],
      });
      backend.on(
        'POST',
        '/api/reservations/1/confirm/',
        {'detail': 'A cancelled reservation cannot be confirmed.'},
        status: 409,
      );

      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(
        find.text('A cancelled reservation cannot be confirmed.'),
        findsOneWidget,
      );
    });

    testWidgets('switching to the week view asks for a date range',
        (tester) async {
      final backend = await signedIn(tester, reservationsBody: {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.tap(find.text('Next 7 days'));
      await tester.pumpAndSettle();

      final query = backend.requests.last.url.queryParameters;
      expect(query['date_from'], isNotNull);
      expect(query['date_to'], isNotNull);
      expect(query['date_from'], isNot(query['date_to']));
      expect(find.text('Nothing booked this week'), findsOneWidget);
    });

    testWidgets('a failing reservations call shows a retry', (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      // No /reservations/ route registered -> the fake returns 404.

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      expect(find.text('Could not load reservations'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a user with no venue is told why the list is empty',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user(establishments: []));
      backend.on('GET', '/api/reservations/', {'count': 0, 'results': []});

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();

      expect(find.text('No venue assigned'), findsWidgets);
    });

    testWidgets('a cash booking is badged as cash, not as unpaid',
        (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking()],
      });

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Unpaid'), findsNothing);
    });

    testWidgets('an Orange Money booking is badged as paid', (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [paidBooking()],
      });

      expect(find.text('Paid (Orange Money)'), findsOneWidget);
    });

    testWidgets('an MTN booking names MTN', (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [paidBooking(provider: 'mtn_money')],
      });

      expect(find.text('Paid (MTN Mobile Money)'), findsOneWidget);
    });

    testWidgets('an unpaid mobile money booking is badged unpaid',
        (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [unpaidBooking()],
      });

      expect(find.text('Unpaid'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
    });

    testWidgets('a failed payment is badged distinctly from merely unpaid',
        (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [unpaidBooking(paymentStatus: 'failed')],
      });

      expect(find.text('Payment failed'), findsOneWidget);
    });

    testWidgets('a mixed day badges each row for its own state',
        (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 3,
        'next': null,
        'results': [
          booking(id: 1, customer: 'Cash Customer'),
          paidBooking(id: 2, customer: 'Orange Customer'),
          unpaidBooking(id: 3, customer: 'Unpaid Customer'),
        ],
      });

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Paid (Orange Money)'), findsOneWidget);
      expect(find.text('Unpaid'), findsOneWidget);
    });

    testWidgets('badges are distinguishable by icon, not colour alone',
        (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 3,
        'next': null,
        'results': [
          booking(id: 1, customer: 'Cash Customer'),
          paidBooking(id: 2, customer: 'Orange Customer'),
          unpaidBooking(id: 3, customer: 'Unpaid Customer'),
        ],
      });

      expect(find.byIcon(Icons.local_atm), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    });
  });

  group('confirming and payment', () {
    Future<FakeBackend> signedIn(
      WidgetTester tester, {
      required Object reservationsBody,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', reservationsBody);

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('a cash booking can be confirmed', (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking()],
      });

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Confirm'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('a paid booking can be confirmed', (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [paidBooking()],
      });

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Confirm'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('an unpaid booking has confirm disabled, with a reason',
        (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [unpaidBooking()],
      });

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Confirm'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text('Cannot confirm until the payment clears.'),
        findsOneWidget,
      );
    });

    testWidgets('an unpaid booking can still be cancelled', (tester) async {
      await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [unpaidBooking()],
      });

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('the server refusing to confirm is surfaced', (tester) async {
      // The app disables the button, but the server is the authority: if the
      // two ever disagree, the merchant must see why.
      final backend = await signedIn(tester, reservationsBody: {
        'count': 1,
        'next': null,
        'results': [booking(canConfirm: true, paymentProvider: 'orange_money')],
      });
      backend.on(
        'POST',
        '/api/reservations/1/confirm/',
        {
          'detail': 'Orange Money payment is pending. Confirm this booking '
              'once the payment completes, or cancel it.',
        },
        status: 409,
      );

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.textContaining('payment is pending'), findsOneWidget);
    });
  });

  group('reservation detail', () {
    Future<FakeBackend> openDetail(
      WidgetTester tester,
      Map<String, dynamic> row,
    ) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 1,
        'next': null,
        'results': [row],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mariama Diallo'));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('opens from the list', (tester) async {
      await openDetail(tester, paidBooking());
      expect(find.text('Reservation'), findsOneWidget);
    });

    testWidgets('shows the amount and provider reference for reconciliation',
        (tester) async {
      await openDetail(tester, paidBooking());

      expect(find.text('50000.00 GNF'), findsOneWidget);
      expect(find.text('MOCK-A4A546A240074095'), findsOneWidget);
      expect(find.text('Paid (Orange Money)'), findsOneWidget);
    });

    testWidgets('a cash booking says nothing is owed yet', (tester) async {
      await openDetail(tester, booking());

      expect(find.text('Cash on arrival'), findsWidgets);
      expect(
        find.text('Nothing yet — settled at the venue'),
        findsOneWidget,
      );
    });

    testWidgets('an unpaid booking explains why it cannot be confirmed',
        (tester) async {
      await openDetail(tester, unpaidBooking());

      expect(
        find.textContaining('cannot be confirmed until the payment clears'),
        findsOneWidget,
      );
    });

    testWidgets('the reference is copyable for a dispute', (tester) async {
      await openDetail(tester, paidBooking());

      expect(find.byTooltip('Copy Provider reference'), findsOneWidget);
    });
  });

  group('payments dashboard', () {
    Map<String, dynamic> dashboardJson({
      String collected = '150000.00',
      String awaiting = '0.00',
      String failed = '0.00',
      int completedCount = 3,
      int pendingCount = 0,
      int failedCount = 0,
      List<Map<String, dynamic>>? needsAttention,
    }) =>
        {
          'period': {'from': '2026-07-01', 'to': '2026-07-30'},
          'establishments': [
            {'id': 7, 'name': 'Le Petit Baobab'},
          ],
          'reservations': {
            'total': 10,
            'pending': 2,
            'confirmed': 6,
            'cancelled': 1,
            'completed': 1,
          },
          'payments': {
            'collected': collected,
            'awaiting': awaiting,
            'failed': failed,
            'completed_count': completedCount,
            'pending_count': pendingCount,
            'failed_count': failedCount,
          },
          'by_provider': [
            {
              'provider': 'cash_on_arrival',
              'provider_display': 'Cash on arrival',
              'bookings': 6,
              'collected': '0.00',
              'awaiting': '0.00',
            },
            {
              'provider': 'orange_money',
              'provider_display': 'Orange Money',
              'bookings': 3,
              'collected': '150000.00',
              'awaiting': '0.00',
            },
            {
              'provider': 'mtn_money',
              'provider_display': 'MTN Mobile Money',
              'bookings': 0,
              'collected': '0.00',
              'awaiting': '0.00',
            },
          ],
          'needs_attention': needsAttention ?? [],
        };

    Future<FakeBackend> openDashboard(
      WidgetTester tester, {
      Map<String, dynamic>? dashboard,
      bool failDashboard = false,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      if (!failDashboard) {
        backend.on(
          'GET',
          '/api/dashboard/payments/',
          dashboard ?? dashboardJson(),
        );
      }

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.payments_outlined));
      await tester.pumpAndSettle();
      return backend;
    }

    /// The "Needs chasing" section sits below the fold on a 360x900 phone, so
    /// it is not built until scrolled to.
    Future<void> scrollToBottom(WidgetTester tester) async {
      // Drag the list itself: any content-based target scrolls out of reach
      // after the first drag.
      const list = Key('payments-dashboard-list');
      for (var i = 0; i < 5; i++) {
        await tester.drag(find.byKey(list), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('is reachable from the reservations screen', (tester) async {
      await openDashboard(tester);
      expect(find.text('Collected'), findsOneWidget);
    });

    testWidgets('shows what was collected', (tester) async {
      await openDashboard(tester);

      expect(find.text('150000.00 GNF'), findsWidgets);
      expect(find.text('3 payments'), findsOneWidget);
    });

    testWidgets('shows outstanding and failed money separately',
        (tester) async {
      await openDashboard(
        tester,
        dashboard: dashboardJson(
          awaiting: '50000.00',
          failed: '25000.00',
          pendingCount: 1,
          failedCount: 1,
        ),
      );

      expect(find.text('Awaiting'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('1 pending'), findsOneWidget);
      expect(find.text('1 failed'), findsOneWidget);
    });

    testWidgets('breaks takings down by payment method', (tester) async {
      await openDashboard(tester);

      expect(find.text('Cash on arrival'), findsOneWidget);
      expect(find.text('Orange Money'), findsOneWidget);
      expect(find.text('MTN Mobile Money'), findsOneWidget);
      // Cash is settled at the till, so it shows no figure.
      expect(find.text('at the till'), findsOneWidget);
    });

    testWidgets('counts bookings by status', (tester) async {
      await openDashboard(tester);

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
    });

    testWidgets('says so when nothing is outstanding', (tester) async {
      await openDashboard(tester);

      await scrollToBottom(tester);

      expect(
        find.text('Nothing outstanding. Every booking is settled.'),
        findsOneWidget,
      );
    });

    testWidgets('lists bookings that need chasing', (tester) async {
      await openDashboard(
        tester,
        dashboard: dashboardJson(needsAttention: [
          {
            'id': 42,
            'customer_name': 'Unpaid Guest',
            'datetime': DateTime.now()
                .add(const Duration(days: 2))
                .toUtc()
                .toIso8601String(),
            'space_name': 'Table 4',
            'establishment_name': 'Le Petit Baobab',
            'payment_status': 'pending',
            'payment_provider_display': 'Orange Money',
          },
        ]),
      );

      await scrollToBottom(tester);

      expect(find.text('Unpaid Guest'), findsOneWidget);
      expect(find.text('Orange Money not received'), findsOneWidget);
      expect(
        find.text('Nothing outstanding. Every booking is settled.'),
        findsNothing,
      );
    });

    testWidgets('a failed payment reads differently from an unpaid one',
        (tester) async {
      await openDashboard(
        tester,
        dashboard: dashboardJson(needsAttention: [
          {
            'id': 42,
            'customer_name': 'Failed Guest',
            'datetime': DateTime.now()
                .add(const Duration(days: 2))
                .toUtc()
                .toIso8601String(),
            'space_name': 'Table 4',
            'establishment_name': 'Le Petit Baobab',
            'payment_status': 'failed',
            'payment_provider_display': 'MTN Mobile Money',
          },
        ]),
      );

      await scrollToBottom(tester);

      expect(find.text('MTN Mobile Money payment failed'), findsOneWidget);
    });

    testWidgets('changing the window re-queries with new dates',
        (tester) async {
      final backend = await openDashboard(tester);

      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();

      final query = backend.requests.last.url.queryParameters;
      expect(query['date_from'], isNotNull);
      expect(query['date_to'], isNotNull);
    });

    testWidgets('a failure offers a retry', (tester) async {
      await openDashboard(tester, failDashboard: true);

      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('venue switcher', () {
    Future<({AuthController auth, FakeBackend backend})> signIn(
      WidgetTester tester, {
      required List<Map<String, dynamic>> venues,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {'results': venues});
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/dashboard/payments/', {
        'period': {'from': '2026-07-01', 'to': '2026-07-30'},
        'establishments': [],
        'reservations': {'total': 0},
        'payments': {
          'collected': '0.00',
          'awaiting': '0.00',
          'failed': '0.00',
          'completed_count': 0,
          'pending_count': 0,
          'failed_count': 0,
        },
        'by_provider': [],
        'needs_attention': [],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      return (auth: auth, backend: backend);
    }

    testWidgets('a single-venue user never sees the switcher', (tester) async {
      await signIn(tester, venues: [venueJson()]);

      expect(find.text('Choose a venue'), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      // Straight into the app.
      expect(find.text('Reservations'), findsWidgets);
    });

    testWidgets('a staff-role single-venue user also skips it',
        (tester) async {
      await signIn(tester, venues: [venueJson(role: 'staff')]);

      expect(find.text('Choose a venue'), findsNothing);
      expect(find.text('Le Petit Baobab · Staff'), findsOneWidget);
    });

    testWidgets('a multi-venue user must choose first', (tester) async {
      await signIn(tester, venues: [
        venueJson(id: 7, name: 'Le Petit Baobab'),
        venueJson(id: 8, name: 'Chez Fatou', city: 'Labé', role: 'manager'),
      ]);

      expect(find.text('Choose a venue'), findsOneWidget);
      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('Chez Fatou'), findsOneWidget);
      // Not in the app yet.
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the picker shows the role at each venue', (tester) async {
      await signIn(tester, venues: [
        venueJson(id: 7, name: 'Le Petit Baobab', role: 'owner'),
        venueJson(id: 8, name: 'Chez Fatou', role: 'manager'),
      ]);

      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Manager'), findsOneWidget);
    });

    testWidgets('choosing a venue enters the app scoped to it',
        (tester) async {
      final (:auth, :backend) = await signIn(tester, venues: [
        venueJson(id: 7, name: 'Le Petit Baobab'),
        venueJson(id: 8, name: 'Chez Fatou', role: 'manager'),
      ]);

      await tester.tap(find.text('Chez Fatou'));
      await tester.pumpAndSettle();

      expect(find.text('Chez Fatou · Manager'), findsOneWidget);
      final listed = backend.requests
          .where((r) => r.url.path == '/api/reservations/')
          .last;
      expect(listed.url.queryParameters['establishment'], '8');
    });

    testWidgets('a multi-venue user can switch from inside the app',
        (tester) async {
      final (:auth, :backend) = await signIn(tester, venues: [
        venueJson(id: 7, name: 'Le Petit Baobab'),
        venueJson(id: 8, name: 'Chez Fatou', role: 'manager'),
      ]);
      await tester.tap(find.text('Le Petit Baobab'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pumpAndSettle();
      expect(find.text('Choose a venue'), findsOneWidget);

      await tester.tap(find.text('Chez Fatou'));
      await tester.pumpAndSettle();

      final listed = backend.requests
          .where((r) => r.url.path == '/api/reservations/')
          .last;
      expect(listed.url.queryParameters['establishment'], '8');
    });

    testWidgets('reservations are requested for the selected venue only',
        (tester) async {
      final (:auth, :backend) = await signIn(tester, venues: [venueJson()]);

      final listed = backend.requests
          .where((r) => r.url.path == '/api/reservations/')
          .last;
      expect(listed.url.queryParameters['establishment'], '7');
    });

    testWidgets('the dashboard is requested for the selected venue only',
        (tester) async {
      final (:auth, :backend) = await signIn(tester, venues: [venueJson()]);

      await tester.tap(find.byIcon(Icons.payments_outlined));
      await tester.pumpAndSettle();

      final asked = backend.requests
          .where((r) => r.url.path == '/api/dashboard/payments/')
          .last;
      expect(asked.url.queryParameters['establishment'], '7');
    });

    testWidgets('an account with no venue is told so', (tester) async {
      await signIn(tester, venues: const []);

      expect(find.text('No venue yet'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('manage tab and role gating', () {
    Future<FakeBackend> openManage(
      WidgetTester tester, {
      String role = 'owner',
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(role: role)],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('an owner sees every management entry', (tester) async {
      await openManage(tester, role: 'owner');

      // The list is taller than a 360dp phone, so not every entry can be on
      // screen at once. Each is reached the way a merchant reaches it.
      for (final entry in [
        'Menu',
        'Opening hours',
        'Venue details',
        'Who has access',
      ]) {
        await tester.scrollUntilVisible(
          find.text(entry),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(entry), findsOneWidget, reason: entry);
      }
    });

    testWidgets('a manager sees everything except access', (tester) async {
      await openManage(tester, role: 'manager');

      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Opening hours'), findsOneWidget);
      expect(find.text('Venue details'), findsOneWidget);
      // Staff management is owner-only, so it is not offered at all.
      expect(find.text('Who has access'), findsNothing);
    });

    testWidgets('staff see only the menu, and are told why', (tester) async {
      await openManage(tester, role: 'staff');

      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Mark items sold out'), findsOneWidget);
      expect(find.text('Opening hours'), findsNothing);
      expect(find.text('Venue details'), findsNothing);
      expect(find.text('Who has access'), findsNothing);
      expect(
        find.textContaining('managed by an owner or manager'),
        findsOneWidget,
      );
    });

    testWidgets('the venue and the role are named', (tester) async {
      await openManage(tester, role: 'manager');

      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.textContaining('you are manager here'), findsOneWidget);
    });
  });

  group('menu screen', () {
    Future<FakeBackend> openMenu(
      WidgetTester tester, {
      String role = 'owner',
      List<Map<String, dynamic>>? items,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(role: role)],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/establishments/7/menu/', {
        'results': items ??
            [
              {
                'id': 1,
                'name': 'Poulet braisé',
                'description': '',
                'category': 'food',
                'price': '75000.00',
                'is_available': true,
              },
            ],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('items are listed with their price', (tester) async {
      await openMenu(tester);

      expect(find.text('Poulet braisé'), findsOneWidget);
      expect(find.text('75000.00 GNF'), findsOneWidget);
    });

    testWidgets('an owner can add and edit items', (tester) async {
      await openMenu(tester, role: 'owner');

      expect(find.text('Add item'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('staff get the availability switch but no editing',
        (tester) async {
      await openMenu(tester, role: 'staff');

      // The switch is the one menu change their role allows.
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('Add item'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(
        find.textContaining('Adding and editing is done by a manager or owner'),
        findsOneWidget,
      );
    });

    testWidgets('toggling availability calls the dedicated endpoint',
        (tester) async {
      final backend = await openMenu(tester, role: 'staff');
      backend.on(
        'PATCH',
        '/api/merchant/establishments/7/menu/1/availability/',
        {
          'id': 1,
          'name': 'Poulet braisé',
          'description': '',
          'category': 'food',
          'price': '75000.00',
          'is_available': false,
        },
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final patched = backend.requests.last;
      expect(
        patched.url.path,
        '/api/merchant/establishments/7/menu/1/availability/',
      );
      expect(find.text('Sold out'), findsOneWidget);
    });

    testWidgets('an empty menu says so', (tester) async {
      await openMenu(tester, items: const []);

      expect(find.text('No menu yet'), findsOneWidget);
    });
  });

  group('photos and menu pictures', () {
    Future<({FakeBackend backend, FakeImageSource picker})> openManage(
      WidgetTester tester, {
      String role = 'owner',
      bool cancels = false,
      List<Map<String, dynamic>>? photos,
      List<Map<String, dynamic>>? menu,
    }) async {
      final picker = FakeImageSource(cancels: cancels);
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(role: role)],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/establishments/7/photos/', {
        'count': photos?.length ?? 0,
        'next': null,
        'results': photos ?? [],
      });
      backend.on('GET', '/api/merchant/establishments/7/menu/', {
        'results': menu ??
            [
              {
                'id': 1,
                'name': 'Poulet braisé',
                'description': '',
                'category': 'food',
                'price': '75000.00',
                'is_available': true,
                'image_url': null,
              },
            ],
      });

      await tester.pumpWidget(
        MerchantApp(
          auth: auth,
          imageSource: picker,
          localeStore: InMemoryLocaleStore(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      return (backend: backend, picker: picker);
    }

    testWidgets('an owner can reach the photos screen', (tester) async {
      await openManage(tester);

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('staff can look at photos but not add them', (tester) async {
      await openManage(tester, role: 'staff');

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      expect(find.text('Add photo'), findsNothing);
      expect(
        find.textContaining('An owner or manager adds photos here'),
        findsOneWidget,
      );
    });

    testWidgets('a picked photo is uploaded', (tester) async {
      final (:backend, :picker) = await openManage(tester);
      backend.on('POST', '/api/establishments/7/photos/', {
        'id': 1,
        'image': 'http://localhost:8000/media/establishments/7/a.jpg',
        'caption': 'The terrace',
        'uploaded_by_role': 'merchant',
        'uploaded_by_role_display': 'Merchant',
        'created_at': '2026-07-28T20:00:00Z',
      });

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'The terrace');
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();

      expect(picker.pickCount, 1);
      // By method too: the screen GETs the same path to list photos.
      final posted = backend.requests.firstWhere(
        (r) =>
            r.method == 'POST' &&
            r.url.path == '/api/establishments/7/photos/',
      );
      expect(posted.headers['content-type'], contains('multipart/form-data'));
      expect(find.text('Photo added.'), findsOneWidget);
    });

    testWidgets('backing out of the picker uploads nothing', (tester) async {
      final (:backend, :picker) = await openManage(tester, cancels: true);

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(picker.pickCount, 1);
      expect(find.text('Add a caption'), findsNothing);
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('an item with no picture shows a tappable placeholder',
        (tester) async {
      await openManage(tester);

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    });

    testWidgets('staff see a plain placeholder, not an invitation',
        (tester) async {
      await openManage(tester, role: 'staff');

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
      expect(find.byIcon(Icons.restaurant), findsOneWidget);
    });

    testWidgets('tapping the placeholder uploads a picture for the item',
        (tester) async {
      final (:backend, :picker) = await openManage(tester);
      backend.on('PATCH', '/api/merchant/establishments/7/menu/1/', {
        'id': 1,
        'name': 'Poulet braisé',
        'description': '',
        'category': 'food',
        'price': '75000.00',
        'is_available': true,
        'image_url': 'http://localhost:8000/media/menu/7/a.jpg',
      });

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();

      expect(picker.pickCount, 1);
      final patched = backend.requests
          .firstWhere((r) => r.url.path.endsWith('/menu/1/'));
      expect(patched.method, 'PATCH');
      expect(patched.headers['content-type'], contains('multipart/form-data'));
      expect(find.textContaining('Picture added'), findsOneWidget);
    });
  });

  group('branding screen', () {
    Future<FakeBackend> openBranding(
      WidgetTester tester, {
      String role = 'owner',
      String preset = 'ember',
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(role: role)],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/establishments/7/', {
        'id': 7,
        'name': 'Le Petit Baobab',
        'type': 'lounge',
        'city': 'Conakry',
        'address': 'Kaloum',
        'tagline': '',
        'description': '',
        'opening_hours': '',
        'theme_preset': preset,
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Branding'));
      await tester.pumpAndSettle();
      return backend;
    }

    /// The preview and the save button sit below the fold on a 360x900
    /// phone, so they are not built until scrolled to.
    Future<void> scrollDown(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.drag(
          find.byKey(const Key('branding-list')),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('all five presets are offered', (tester) async {
      await openBranding(tester);

      for (final preset in themePresets) {
        expect(find.text(preset.name), findsOneWidget, reason: preset.key);
      }
    });

    testWidgets('each swatch shows the venue name in its own style',
        (tester) async {
      await openBranding(tester);

      // Each visible swatch renders the venue's own name on the accent.
      expect(find.text('Le Petit Baobab'), findsWidgets);
    });

    testWidgets('the saved preset starts selected', (tester) async {
      await openBranding(tester, preset: 'bissap');
      await scrollDown(tester);

      // Selected swatch is the only one with a filled check.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('choosing a preset previews it before saving', (tester) async {
      final backend = await openBranding(tester, preset: 'ember');

      await tester.tap(find.text('Bissap'));
      await tester.pumpAndSettle();
      await scrollDown(tester);

      // Preview re-themed, and nothing sent yet.
      final previewScheme =
          Theme.of(tester.element(find.text('Open until 02:00'))).colorScheme;
      expect(previewScheme.primary, themePresetFor('bissap').accent);
      expect(backend.requests.where((r) => r.method == 'PATCH'), isEmpty);
      expect(find.text('Save branding'), findsOneWidget);
    });

    testWidgets('saving sends only the preset key', (tester) async {
      final backend = await openBranding(tester);
      backend.on('PATCH', '/api/merchant/establishments/7/', {
        'id': 7,
        'name': 'Le Petit Baobab',
        'type': 'lounge',
        'city': 'Conakry',
        'address': 'Kaloum',
        'tagline': '',
        'description': '',
        'opening_hours': '',
        'theme_preset': 'indigo_soir',
      });

      await tester.tap(find.text('Indigo Soir'));
      await tester.pumpAndSettle();
      await scrollDown(tester);
      await tester.tap(find.text('Save branding'));
      await tester.pumpAndSettle();

      final patched = backend.requests.firstWhere((r) => r.method == 'PATCH');
      final body = jsonDecode(patched.body) as Map<String, dynamic>;
      expect(body, {'theme_preset': 'indigo_soir'});
      // No colours or fonts travel — only the key.
      expect(body.containsKey('accent'), isFalse);
      expect(find.text('Branding saved.'), findsOneWidget);
    });

    testWidgets('a refusal from the server is surfaced', (tester) async {
      final backend = await openBranding(tester);
      backend.on(
        'PATCH',
        '/api/merchant/establishments/7/',
        {'detail': 'Your role here is staff. Editing the venue profile is '
            'not something you can do.'},
        status: 403,
      );

      await tester.tap(find.text('Bissap'));
      await tester.pumpAndSettle();
      await scrollDown(tester);
      await tester.tap(find.text('Save branding'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not something you can do'), findsOneWidget);
    });

    testWidgets('staff are not offered branding at all', (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(role: 'staff')],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Branding'), findsNothing);
    });

    testWidgets('the app chrome keeps its own theme', (tester) async {
      await openBranding(tester, preset: 'bissap');

      // The screen around the preview is the app's, not the venue's.
      final chrome =
          Theme.of(tester.element(find.text('Branding').first)).colorScheme;
      expect(chrome.primary, isNot(themePresetFor('bissap').accent));
    });
  });

  group('signing out', () {
    Future<FakeBackend> signedIn(
      WidgetTester tester, {
      required Object reservationsBody,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', reservationsBody);

      await tester.pumpWidget(MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(),
        ));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('signing out returns to the login screen', (tester) async {
      final backend = await signedIn(tester, reservationsBody: {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('POST', '/api/auth/logout/', null, status: 204);

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('English and French', () {
    /// Signed in on the reservation list, in the given language.
    Future<({FakeBackend backend, InMemoryLocaleStore store})> signedIn(
      WidgetTester tester, {
      String? language,
      List<Map<String, dynamic>>? reservations,
      Size size = phoneSize,
    }) async {
      final (:auth, :backend) = buildAuth(
        tester,
        storedToken: 'stored-token',
        size: size,
      );
      final store = InMemoryLocaleStore(language);
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': reservations?.length ?? 0,
        'next': null,
        'results': reservations ?? [],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: store),
      );
      await tester.pumpAndSettle();
      return (backend: backend, store: store);
    }

    testWidgets('the app is English by default', (tester) async {
      await signedIn(tester);

      expect(find.text('Reservations'), findsWidgets);
      expect(find.text('Manage'), findsOneWidget);
    });

    testWidgets('a stored French choice is in force at launch',
        (tester) async {
      await signedIn(tester, language: 'fr');

      // The navigation bar, which is the first thing a merchant reads.
      expect(find.text('Gérer'), findsOneWidget);
      expect(find.text('Paiements'), findsOneWidget);
    });

    testWidgets('the desk switcher stays French in both languages',
        (tester) async {
      await signedIn(tester);

      // Deliberate: these are the words merchants already use on the floor,
      // so they do not flip with the rest of the app.
      expect(find.text('Réservations'), findsWidgets);
      expect(find.text('Commandes'), findsOneWidget);
    });

    testWidgets('an empty day says so in French', (tester) async {
      await signedIn(tester, language: 'fr');

      expect(find.text('Aucune réservation aujourd\'hui'), findsOneWidget);
      expect(find.text('Nothing booked today'), findsNothing);
    });

    testWidgets('a booking on the list reads in French', (tester) async {
      await signedIn(
        tester,
        language: 'fr',
        reservations: [booking(status: 'confirmed')],
      );

      // The status badge comes from the app, not from the server's
      // status_display, so it has to be translated here.
      expect(find.text('Confirmée'), findsOneWidget);
      expect(find.textContaining('2 personnes'), findsOneWidget);
      expect(find.text('Espèces'), findsOneWidget);
    });

    testWidgets('the language toggle lives on Manage', (tester) async {
      await signedIn(tester);

      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      // And it is clear of the navigation bar, not hidden behind it.
      final toggle = tester.getRect(find.text('Français'));
      final bar = tester.getRect(find.byType(NavigationBar));
      expect(toggle.bottom, lessThanOrEqualTo(bar.top));
    });

    testWidgets('switching to French translates the screen underneath',
        (tester) async {
      await signedIn(tester);

      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);

      await tester.tap(find.text('Français'));
      await tester.pumpAndSettle();
      // French runs longer, so the same rows sit further down the list.
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('Se déconnecter'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      // And the toggle itself, so it can be found again to switch back.
      expect(find.text('Langue'), findsOneWidget);
    });

    testWidgets('the choice survives the next launch', (tester) async {
      final (:backend, :store) = await signedIn(tester);

      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Français'));
      await tester.pumpAndSettle();

      expect(await store.readLanguageCode(), 'fr');
    });

    testWidgets('the server is told which language to answer in',
        (tester) async {
      final (:backend, :store) = await signedIn(tester, language: 'fr');

      // The API translates its own refusals; a French app that forgot to say
      // so would show French screens with English messages on them.
      final me = backend.requests.firstWhere(
        (r) => r.url.path == '/api/auth/me/',
      );
      expect(me.headers['Accept-Language'], 'fr');
    });

    testWidgets('an English app sends no language header at all',
        (tester) async {
      final (:backend, :store) = await signedIn(tester);

      // No header means English, which is what every older client sends.
      final me = backend.requests.firstWhere(
        (r) => r.url.path == '/api/auth/me/',
      );
      expect(me.headers.containsKey('Accept-Language'), isFalse);
    });

    testWidgets('nothing is fetched before the language is known',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      final store = SlowLocaleStore('fr');

      await tester.pumpWidget(MerchantApp(auth: auth, localeStore: store));
      await tester.pump();

      // Reading the stored language is still in flight. Anything sent now
      // would go out before the app could say which language to answer in,
      // and the first thing a merchant reads on a cold start is an error.
      expect(backend.requests, isEmpty);

      store.finishRead();
      await tester.pumpAndSettle();

      expect(backend.requests, isNotEmpty);
      expect(backend.requests.first.headers['Accept-Language'], 'fr');
    });

    testWidgets('a French login screen refuses in French', (tester) async {
      final (:auth, :backend) = buildAuth(tester);
      backend.on(
        'POST',
        '/api/auth/login/',
        {'detail': 'Invalid credentials.'},
        status: 400,
      );

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore('fr')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'amadou');
      await tester.enterText(find.byType(TextFormField).last, 'wrong');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(
        find.text('Nom d\'utilisateur ou mot de passe incorrect.'),
        findsOneWidget,
      );
    });

    testWidgets('the role follows the language, not the sign-in request',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      // What the server sends when the venue list was fetched in English —
      // which it always is, because the list is loaded once at sign-in and
      // held for the whole session.
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson()],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore('fr')),
      );
      await tester.pumpAndSettle();

      // Not "Le Petit Baobab · Owner": the payload says Owner, and nothing
      // refetches it when the language changes.
      expect(find.textContaining('Propriétaire'), findsOneWidget);
      expect(find.textContaining('Owner'), findsNothing);
    });

    testWidgets('the French labels still fit a 360dp phone', (tester) async {
      // French runs longer than English almost everywhere, and the navigation
      // bar is the tightest row in the app.
      await signedIn(tester, language: 'fr');

      for (final label in ['Réservations', 'Paiements', 'Gérer']) {
        final rect = tester.getRect(find.text(label).last);
        expect(rect.right, lessThanOrEqualTo(phoneSize.width), reason: label);
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('tables and rooms', () {
    Map<String, dynamic> spaceJson({
      int id = 1,
      String name = 'Table 4',
      String type = 'table',
      int capacity = 4,
      bool isActive = true,
    }) =>
        {
          'id': id,
          'name': name,
          'type': type,
          'type_display': switch (type) {
            'vip_room' => 'VIP room',
            'terrace' => 'Terrace',
            _ => 'Table',
          },
          'capacity': capacity,
          'is_active': isActive,
        };

    /// On the spaces screen, for the given role.
    Future<FakeBackend> openSpaces(
      WidgetTester tester, {
      String role = 'owner',
      List<Map<String, dynamic>>? spaces,
      String? language,
      Size size = phoneSize,
    }) async {
      final (:auth, :backend) = buildAuth(
        tester,
        storedToken: 'stored-token',
        size: size,
      );
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(role: role)],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/establishments/7/spaces/', {
        'results': spaces ?? [spaceJson()],
      });

      await tester.pumpWidget(
        MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(language),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('an owner is offered tables and rooms', (tester) async {
      await openSpaces(tester);

      expect(find.text('Tables and rooms'), findsOneWidget);
    });

    testWidgets('staff are not', (tester) async {
      // They may read the layout over the API — the desk names the table a
      // booking is on — but there is nothing here they can change.
      await openSpaces(tester, role: 'staff');

      expect(find.text('Tables and rooms'), findsNothing);
    });

    testWidgets('it sits above opening hours', (tester) async {
      // A venue is defined by its rooms before it is defined by its hours.
      await openSpaces(tester);

      final spaces = tester.getRect(find.text('Tables and rooms'));
      final hours = tester.getRect(find.text('Opening hours'));
      expect(spaces.top, lessThan(hours.top));
    });

    testWidgets('the seating plan lists what is there', (tester) async {
      await openSpaces(tester, spaces: [
        spaceJson(name: 'Table 4', capacity: 4),
        spaceJson(id: 2, name: 'VIP Room 1', type: 'vip_room', capacity: 8),
      ]);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();

      expect(find.text('Table 4'), findsOneWidget);
      expect(find.text('VIP Room 1'), findsOneWidget);
      expect(find.text('4 seats'), findsOneWidget);
      expect(find.text('8 seats'), findsOneWidget);
    });

    testWidgets('a venue with no tables says what to do about it',
        (tester) async {
      await openSpaces(tester, spaces: []);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();

      expect(find.text('No tables yet'), findsOneWidget);
      expect(
        find.textContaining('needs somewhere to sit'),
        findsOneWidget,
      );
    });

    testWidgets('adding a table posts what the server expects',
        (tester) async {
      final backend = await openSpaces(tester, spaces: []);
      backend.on('POST', '/api/merchant/establishments/7/spaces/',
          spaceJson(name: 'Terrace 1', type: 'terrace', capacity: 6));

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a table'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Terrace 1');
      await tester.enterText(find.byType(TextFormField).last, '6');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final posted = backend.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/spaces/'),
      );
      final body = jsonDecode(posted.body) as Map<String, dynamic>;
      expect(body['name'], 'Terrace 1');
      expect(body['capacity'], 6);
      // The wire value, not the enum name: the server speaks snake_case.
      expect(body['type'], 'table');
    });

    testWidgets('a duplicate name is shown, not swallowed', (tester) async {
      final backend = await openSpaces(tester);
      backend.on(
        'POST',
        '/api/merchant/establishments/7/spaces/',
        {'name': ['There is already a space called that here.']},
        status: 400,
      );

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a table'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Table 4');
      await tester.enterText(find.byType(TextFormField).last, '2');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('already a space called that'),
        findsOneWidget,
      );
    });

    testWidgets('a table seating nobody is refused before the round trip',
        (tester) async {
      final backend = await openSpaces(tester, spaces: []);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a table'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Nowhere');
      await tester.enterText(find.byType(TextFormField).last, '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('A table seats at least one guest.'), findsOneWidget);
      expect(
        backend.requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/spaces/'),
        ),
        isEmpty,
      );
    });

    testWidgets('removing a table explains that its bookings are kept',
        (tester) async {
      await openSpaces(tester);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Table 4?'), findsOneWidget);
      // Said before the tap, not after.
      expect(
        find.textContaining('retired rather than erased'),
        findsOneWidget,
      );
    });

    testWidgets('a table with no history reports as deleted', (tester) async {
      final backend = await openSpaces(tester);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();

      // Registered only now: overriding the list before navigating would
      // have the screen load its post-delete state and never show the row.
      backend.on(
        'DELETE',
        '/api/merchant/establishments/7/spaces/1/',
        null,
        status: 204,
      );
      backend.on('GET', '/api/merchant/establishments/7/spaces/', {
        'results': [],
      });

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Table 4 removed.'), findsOneWidget);
    });

    testWidgets('a booked table reports as retired instead', (tester) async {
      final backend = await openSpaces(tester);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();

      // 200 with the space: the server kept it, because it has history.
      backend.on(
        'DELETE',
        '/api/merchant/establishments/7/spaces/1/',
        spaceJson(isActive: false),
      );
      backend.on('GET', '/api/merchant/establishments/7/spaces/', {
        'results': [spaceJson(isActive: false)],
      });

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('past bookings are kept'),
        findsOneWidget,
      );
      // And it is still on the list, marked, so it can be brought back.
      expect(find.text('Out of service'), findsOneWidget);
    });

    testWidgets('a retired table can be brought back', (tester) async {
      final backend = await openSpaces(
        tester,
        spaces: [spaceJson(isActive: false)],
      );
      backend.on(
        'PATCH',
        '/api/merchant/establishments/7/spaces/1/',
        spaceJson(),
      );

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bring back'));
      await tester.pumpAndSettle();

      final patched = backend.requests.lastWhere((r) => r.method == 'PATCH');
      expect(
        jsonDecode(patched.body) as Map<String, dynamic>,
        {'is_active': true},
      );
    });

    testWidgets('a retired table offers no edit menu', (tester) async {
      // Editing a table that is out of service is not a thing to offer;
      // bringing it back is.
      await openSpaces(tester, spaces: [spaceJson(isActive: false)]);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.text('Bring back'), findsOneWidget);
    });

    testWidgets('the form fits a 360dp phone', (tester) async {
      await openSpaces(tester, spaces: []);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a table'));
      await tester.pumpAndSettle();

      for (final field in tester.widgetList(find.byType(TextFormField))) {
        final rect = tester.getRect(find.byWidget(field));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(phoneSize.width));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('French labels do not overflow the row', (tester) async {
      await openSpaces(
        tester,
        language: 'fr',
        spaces: [spaceJson(name: 'Salon VIP 1', type: 'vip_room', capacity: 8)],
      );

      await tester.tap(find.text('Tables et salons'));
      await tester.pumpAndSettle();

      expect(find.text('Salon VIP'), findsOneWidget);
      expect(find.text('8 places'), findsOneWidget);
      final rect = tester.getRect(find.text('8 places'));
      expect(rect.right, lessThanOrEqualTo(phoneSize.width));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the layout is grouped by kind', (tester) async {
      await openSpaces(tester, spaces: [
        spaceJson(id: 1, name: 'Table 4', capacity: 4),
        spaceJson(id: 2, name: 'Terrace 1', type: 'terrace', capacity: 6),
        spaceJson(id: 3, name: 'Table 5', capacity: 2),
      ]);

      await tester.tap(find.text('Tables and rooms'));
      await tester.pumpAndSettle();

      // Two tables under one heading, the terrace under its own.
      expect(find.text('Table'), findsOneWidget);
      expect(find.text('Terrace'), findsOneWidget);
      final tableHeading = tester.getRect(find.text('Table'));
      final terraceHeading = tester.getRect(find.text('Terrace'));
      expect(tester.getRect(find.text('Table 5')).top,
          lessThan(terraceHeading.top));
      expect(tableHeading.top, lessThan(terraceHeading.top));
    });
  });

  group('registering a venue', () {
    Map<String, dynamic> createdVenueJson({
      int id = 9,
      String name = 'Chez Aissatou',
      String type = 'restaurant',
      String city = 'Conakry',
    }) =>
        {
          'id': id,
          'name': name,
          'type': type,
          'city': city,
          'address': 'Kaloum',
          'latitude': null,
          'longitude': null,
          'tagline': '',
          'description': '',
          'opening_hours': '',
          'theme_preset': 'ember',
        };

    /// Signed in with no venue at all — the state a brand-new account is in.
    Future<FakeBackend> openWithNoVenue(
      WidgetTester tester, {
      String? language,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user(establishments: []));
      backend.on('GET', '/api/merchant/establishments/', {'results': []});

      await tester.pumpWidget(
        MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(language),
        ),
      );
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('an account with no venue is offered one', (tester) async {
      await openWithNoVenue(tester);

      expect(find.text('Create your venue'), findsOneWidget);
    });

    testWidgets('and is no longer told to go and find an admin',
        (tester) async {
      // The old copy was accurate until this slice and is now the opposite
      // of the truth.
      await openWithNoVenue(tester);

      expect(find.textContaining('admin can set one up'), findsNothing);
      expect(find.textContaining('Create your own venue'), findsOneWidget);
    });

    testWidgets('the form asks for the essentials and nothing else',
        (tester) async {
      await openWithNoVenue(tester);

      await tester.tap(find.text('Create your venue'));
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Kind'), findsOneWidget);
      expect(find.text('City'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      // Deliberately absent: each has its own screen once the venue exists.
      expect(find.text('Tagline (one line)'), findsNothing);
      expect(find.text('Description'), findsNothing);
    });

    testWidgets('an empty form is refused before the round trip',
        (tester) async {
      final backend = await openWithNoVenue(tester);

      await tester.tap(find.text('Create your venue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create venue'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsNWidgets(3));
      expect(
        backend.requests.where((r) => r.method == 'POST'),
        isEmpty,
      );
    });

    testWidgets('creating one posts what the server expects', (tester) async {
      final backend = await openWithNoVenue(tester);
      backend.on(
        'POST',
        '/api/merchant/establishments/',
        createdVenueJson(),
        status: 201,
      );
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(id: 9, name: 'Chez Aissatou')],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/establishments/9/spaces/', {
        'results': [],
      });

      await tester.tap(find.text('Create your venue'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Chez Aissatou');
      await tester.enterText(find.byType(TextFormField).at(1), 'Conakry');
      await tester.enterText(find.byType(TextFormField).at(2), 'Kaloum');
      await tester.tap(find.text('Create venue'));
      await tester.pumpAndSettle();

      final posted = backend.requests.lastWhere((r) => r.method == 'POST');
      final body = jsonDecode(posted.body) as Map<String, dynamic>;
      expect(body['name'], 'Chez Aissatou');
      expect(body['city'], 'Conakry');
      expect(body['address'], 'Kaloum');
      expect(body['type'], 'restaurant');
    });

    testWidgets('and lands on the seating plan, not the desk', (tester) async {
      // A venue with no tables cannot take a booking, so the next step is
      // the only step.
      final backend = await openWithNoVenue(tester);
      backend.on(
        'POST',
        '/api/merchant/establishments/',
        createdVenueJson(),
        status: 201,
      );
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(id: 9, name: 'Chez Aissatou')],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/establishments/9/spaces/', {
        'results': [],
      });

      await tester.tap(find.text('Create your venue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Chez Aissatou');
      await tester.enterText(find.byType(TextFormField).at(1), 'Conakry');
      await tester.enterText(find.byType(TextFormField).at(2), 'Kaloum');
      await tester.tap(find.text('Create venue'));
      await tester.pumpAndSettle();

      expect(find.text('No tables yet'), findsOneWidget);
      expect(
        find.textContaining('needs somewhere to sit'),
        findsOneWidget,
      );
    });

    testWidgets('the new venue becomes the one being worked', (tester) async {
      final backend = await openWithNoVenue(tester);
      backend.on(
        'POST',
        '/api/merchant/establishments/',
        createdVenueJson(),
        status: 201,
      );
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(id: 9, name: 'Chez Aissatou')],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/establishments/9/spaces/', {
        'results': [],
      });

      await tester.tap(find.text('Create your venue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Chez Aissatou');
      await tester.enterText(find.byType(TextFormField).at(1), 'Conakry');
      await tester.enterText(find.byType(TextFormField).at(2), 'Kaloum');
      await tester.tap(find.text('Create venue'));
      await tester.pumpAndSettle();

      // Back out of the seating plan and the desk underneath is the new
      // venue's, not the empty state that sent us here.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.textContaining('Chez Aissatou'), findsWidgets);
      expect(find.text('No venue yet'), findsNothing);
    });

    testWidgets('a server refusal is shown on the form', (tester) async {
      final backend = await openWithNoVenue(tester);
      backend.on(
        'POST',
        '/api/merchant/establishments/',
        {'name': ['An establishment with that name already exists.']},
        status: 400,
      );

      await tester.tap(find.text('Create your venue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Chez Fatou');
      await tester.enterText(find.byType(TextFormField).at(1), 'Conakry');
      await tester.enterText(find.byType(TextFormField).at(2), 'Kaloum');
      await tester.tap(find.text('Create venue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already exists'), findsOneWidget);
      // Still on the form, with what was typed intact.
      expect(find.text('Create venue'), findsOneWidget);
    });

    testWidgets('an account that already runs one can add another',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [
          venueJson(),
          venueJson(id: 8, name: 'Chez Fatou', city: 'Labé', role: 'manager'),
        ],
      });

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore()),
      );
      await tester.pumpAndSettle();

      // Two venues means the picker, which is where a third would start.
      expect(find.text('Choose a venue'), findsOneWidget);
      expect(find.text('New venue'), findsOneWidget);
    });

    testWidgets('the form reads in French', (tester) async {
      await openWithNoVenue(tester, language: 'fr');

      await tester.tap(find.text('Créer votre établissement'));
      await tester.pumpAndSettle();

      expect(find.text('Ville'), findsOneWidget);
      // Typographic apostrophe, matching the catalogue rather than a keyboard.
      expect(find.text('Créer l’établissement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the form fits a 360dp phone', (tester) async {
      await openWithNoVenue(tester);

      await tester.tap(find.text('Create your venue'));
      await tester.pumpAndSettle();

      for (final field in tester.widgetList(find.byType(TextFormField))) {
        final rect = tester.getRect(find.byWidget(field));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(phoneSize.width));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('marking guests arrived', () {
    /// The desk, with one booking whose time has already passed.
    Future<FakeBackend> openDesk(
      WidgetTester tester, {
      Map<String, dynamic>? reservation,
      String? language,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 1,
        'next': null,
        'results': [reservation ?? startedBooking()],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});

      await tester.pumpWidget(
        MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(language),
        ),
      );
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('a sitting that has begun can be closed', (tester) async {
      await openDesk(tester);

      expect(find.text('Mark arrived'), findsOneWidget);
    });

    testWidgets('one that has not begun cannot', (tester) async {
      // Nobody has arrived for a table that is not due, and letting it
      // through would free a slot by declaring tomorrow's guests gone.
      await openDesk(tester, reservation: futureBooking());

      expect(find.text('Mark arrived'), findsNothing);
    });

    testWidgets('marking arrived posts to the right place', (tester) async {
      final backend = await openDesk(tester);
      backend.on(
        'POST',
        '/api/reservations/1/complete/',
        startedBooking(status: 'completed'),
      );

      await tester.tap(find.text('Mark arrived'));
      await tester.pumpAndSettle();

      expect(
        backend.requests.any(
          (r) =>
              r.method == 'POST' &&
              r.url.path == '/api/reservations/1/complete/',
        ),
        isTrue,
      );
      expect(find.textContaining('marked as arrived'), findsOneWidget);
    });

    testWidgets('a closed booking offers nothing further', (tester) async {
      await openDesk(tester, reservation: startedBooking(status: 'completed'));

      expect(find.text('Mark arrived'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('a missed booking reads as missed, not cancelled',
        (tester) async {
      // The two mean opposite things: one is a customer who told the venue,
      // the other is a table held empty.
      await openDesk(tester, reservation: startedBooking(status: 'no_show'));

      expect(find.text('Missed'), findsOneWidget);
      expect(find.text('Cancelled'), findsNothing);
    });

    testWidgets('a server refusal is surfaced', (tester) async {
      final backend = await openDesk(tester);
      backend.on(
        'POST',
        '/api/reservations/1/complete/',
        {'detail': 'That booking has not started yet.'},
        status: 409,
      );

      await tester.tap(find.text('Mark arrived'));
      await tester.pumpAndSettle();

      expect(find.textContaining('has not started'), findsOneWidget);
    });

    testWidgets('the actions still fit a 360dp card', (tester) async {
      // Cancel, Mark arrived and Confirm together are wider than a phone,
      // which is why they wrap.
      await openDesk(tester, reservation: startedBooking(status: 'pending'));

      expect(find.text('Mark arrived'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      for (final label in ['Cancel', 'Mark arrived', 'Confirm']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.right, lessThanOrEqualTo(phoneSize.width), reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('it reads in French', (tester) async {
      await openDesk(tester, language: 'fr');

      expect(find.text('Marquer arrivé'), findsOneWidget);
    });
  });

  group('what became of a deposit', () {
    Map<String, dynamic> paidBookingWithOutcome(String outcome) => booking(
          id: 1,
          status: outcome == 'forfeited' ? 'no_show' : 'completed',
          paymentProvider: 'orange_money',
          isPaid: true,
          payment: {
            ...paymentJson(),
            'outcome': outcome,
            'outcome_display': switch (outcome) {
              'offset' => 'Taken off the bill',
              'forfeited' => 'Kept for a no-show',
              _ => 'Not settled yet',
            },
          },
        );

    Future<void> openDetail(WidgetTester tester, String outcome) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 1,
        'next': null,
        'results': [paidBookingWithOutcome(outcome)],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ReservationCard).first);
      await tester.pumpAndSettle();
    }

    testWidgets('a deposit taken off the bill says so', (tester) async {
      await openDetail(tester, 'offset');

      expect(find.text('Taken off the bill'), findsOneWidget);
    });

    testWidgets('a kept deposit says why it was kept', (tester) async {
      await openDetail(tester, 'forfeited');

      expect(find.text('Kept — nobody arrived'), findsOneWidget);
    });

    testWidgets('an unsettled one says it is not settled yet',
        (tester) async {
      await openDetail(tester, 'none');

      expect(find.text('Not settled yet'), findsOneWidget);
    });

    testWidgets('the payment itself still reads as completed', (tester) async {
      // Outcome is a separate axis: the money arrived either way, and a
      // merchant reconciling needs both answered.
      await openDetail(tester, 'forfeited');

      expect(find.text('Completed'), findsWidgets);
    });

    testWidgets('the dashboard separates kept from taken off the bill',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});
      backend.on('GET', '/api/dashboard/payments/', {
        'period': {'from': '2026-07-01', 'to': '2026-08-01'},
        'establishments': [
          {'id': 7, 'name': 'Le Petit Baobab'},
        ],
        'reservations': {'total': 2},
        'payments': {
          'collected': '100000.00',
          'awaiting': '0.00',
          'failed': '0.00',
          'forfeited': '50000.00',
          'offset': '50000.00',
          'completed_count': 2,
          'pending_count': 0,
          'failed_count': 0,
          'forfeited_count': 1,
        },
        'by_provider': [],
        'needs_attention': [],
      });

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.payments_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Kept from no-shows'), findsOneWidget);
      expect(find.text('Taken off bills'), findsOneWidget);
      expect(find.text('1 deposit'), findsOneWidget);
      // Collected still counts everything that arrived; splitting it would
      // understate what the venue actually took.
      expect(find.text('100000.00 GNF'), findsOneWidget);
    });

    testWidgets('a venue with no settled deposits is not shown the split',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});
      backend.on('GET', '/api/dashboard/payments/', {
        'period': {'from': '2026-07-01', 'to': '2026-08-01'},
        'establishments': [
          {'id': 7, 'name': 'Le Petit Baobab'},
        ],
        'reservations': {'total': 0},
        'payments': {
          'collected': '0.00',
          'awaiting': '0.00',
          'failed': '0.00',
          'forfeited': '0.00',
          'offset': '0.00',
          'completed_count': 0,
          'pending_count': 0,
          'failed_count': 0,
          'forfeited_count': 0,
        },
        'by_provider': [],
        'needs_attention': [],
      });

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.payments_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Kept from no-shows'), findsNothing);
    });
  });

  group('giving a kept deposit back', () {
    Map<String, dynamic> missedWithKeptDeposit({String outcome = 'forfeited'}) =>
        booking(
          id: 1,
          status: 'no_show',
          paymentProvider: 'orange_money',
          isPaid: true,
          payment: {
            ...paymentJson(),
            'outcome': outcome,
            'outcome_display': outcome == 'forfeited'
                ? 'Kept for a no-show'
                : 'Refunded',
          },
        );

    Future<FakeBackend> openDetail(
      WidgetTester tester, {
      Map<String, dynamic>? reservation,
      String? language,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 1,
        'next': null,
        'results': [reservation ?? missedWithKeptDeposit()],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});

      await tester.pumpWidget(
        MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(language),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ReservationCard).first);
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('a kept deposit can be given back', (tester) async {
      await openDetail(tester);

      expect(find.text('Give the deposit back'), findsOneWidget);
    });

    testWidgets('one already given back cannot be again', (tester) async {
      await openDetail(
        tester,
        reservation: missedWithKeptDeposit(outcome: 'refunded'),
      );

      expect(find.text('Give the deposit back'), findsNothing);
      expect(find.text('Refunded'), findsOneWidget);
    });

    testWidgets('a deposit taken off a bill offers nothing', (tester) async {
      // That money already went back, as a discount at the till.
      await openDetail(
        tester,
        reservation: booking(
          id: 1,
          status: 'completed',
          paymentProvider: 'orange_money',
          isPaid: true,
          payment: {
            ...paymentJson(),
            'outcome': 'offset',
            'outcome_display': 'Taken off the bill',
          },
        ),
      );

      expect(find.text('Give the deposit back'), findsNothing);
    });

    testWidgets('it says the booking stays missed before you tap',
        (tester) async {
      await openDetail(tester);

      await tester.tap(find.text('Give the deposit back'));
      await tester.pumpAndSettle();

      expect(find.textContaining('stays missed'), findsOneWidget);
      expect(find.textContaining('Only the money goes back'), findsOneWidget);
    });

    testWidgets('confirming posts and reports back', (tester) async {
      final backend = await openDetail(tester);
      backend.on(
        'POST',
        '/api/reservations/1/refund-deposit/',
        missedWithKeptDeposit(outcome: 'refunded'),
      );

      await tester.tap(find.text('Give the deposit back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Give the deposit back'));
      await tester.pumpAndSettle();

      expect(
        backend.requests.any(
          (r) =>
              r.method == 'POST' &&
              r.url.path == '/api/reservations/1/refund-deposit/',
        ),
        isTrue,
      );
      expect(find.text('Deposit given back.'), findsOneWidget);
      // And the screen now reflects it, without leaving the booking.
      expect(find.text('Refunded'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
    });

    testWidgets('backing out of the dialog sends nothing', (tester) async {
      final backend = await openDetail(tester);

      await tester.tap(find.text('Give the deposit back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        backend.requests.where((r) => r.method == 'POST'),
        isEmpty,
      );
    });

    testWidgets('a server refusal is surfaced', (tester) async {
      final backend = await openDetail(tester);
      backend.on(
        'POST',
        '/api/reservations/1/refund-deposit/',
        {'detail': 'The provider could not be reached.'},
        status: 502,
      );

      await tester.tap(find.text('Give the deposit back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Give the deposit back'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be reached'), findsOneWidget);
      // Still kept, because we do not know the provider took it.
      expect(find.text('Kept — nobody arrived'), findsOneWidget);
    });

    testWidgets('it reads in French', (tester) async {
      await openDetail(tester, language: 'fr');

      expect(find.text('Rendre l’acompte'), findsOneWidget);
    });
  });

  group('learning that new work arrived', () {
    Future<FakeBackend> openDesk(
      WidgetTester tester, {
      int newReservations = 0,
      int newOrders = 0,
      String? language,
      bool activityFails = false,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});
      if (activityFails) {
        backend.on(
          'GET',
          '/api/merchant/activity/',
          {'detail': 'nope'},
          status: 500,
        );
      } else {
        backend.on('GET', '/api/merchant/activity/', {
          'reservations': newReservations,
          'orders': newOrders,
          'total': newReservations + newOrders,
          'since': '2026-08-05T10:00:00Z',
        });
      }

      await tester.pumpWidget(
        MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(language),
        ),
      );
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('a quiet desk says nothing', (tester) async {
      await openDesk(tester);
      // Past the first poll.
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(find.textContaining('since you looked'), findsNothing);
    });

    testWidgets('new work is announced without moving the list',
        (tester) async {
      await openDesk(tester, newReservations: 2, newOrders: 1);

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(find.text('3 new since you looked'), findsOneWidget);
      expect(find.text('Show'), findsOneWidget);
    });

    testWidgets('one is singular', (tester) async {
      await openDesk(tester, newReservations: 1);

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(find.text('1 new since you looked'), findsOneWidget);
    });

    testWidgets('the refresh button carries the count too', (tester) async {
      // Hands full mid-service: the banner is the loud one, the badge is for
      // anyone already looking at the bar.
      await openDesk(tester, newOrders: 4);

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsWidgets);
      expect(find.text('4'), findsWidgets);
    });

    testWidgets('showing it clears the marker and reloads', (tester) async {
      final backend = await openDesk(tester, newReservations: 2);
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      final before =
          backend.requests.where((r) => r.url.path == '/api/reservations/').length;

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.textContaining('since you looked'), findsNothing);
      final after =
          backend.requests.where((r) => r.url.path == '/api/reservations/').length;
      expect(after, greaterThan(before));
    });

    testWidgets('the check asks about the venue being worked', (tester) async {
      final backend = await openDesk(tester, newReservations: 1);

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      final asked = backend.requests.firstWhere(
        (r) => r.url.path == '/api/merchant/activity/',
      );
      expect(asked.url.queryParameters['establishment'], '7');
      expect(asked.url.queryParameters['since'], isNotNull);
    });

    testWidgets('a failed check is not shown to the merchant', (tester) async {
      // The next one is a minute away; a toast every minute on a bad
      // connection would be worse than silence.
      await openDesk(tester, activityFails: true);

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(find.textContaining('since you looked'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it reads in French', (tester) async {
      await openDesk(tester, newReservations: 2, language: 'fr');

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('depuis votre dernier coup d’œil'),
        findsOneWidget,
      );
      expect(find.text('Afficher'), findsOneWidget);
    });

    testWidgets('the banner fits a 360dp phone', (tester) async {
      await openDesk(tester, newReservations: 12, newOrders: 7);

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.text('Show'));
      expect(rect.right, lessThanOrEqualTo(phoneSize.width));
      expect(tester.takeException(), isNull);
    });
  });

  group('being asked to slow down', () {
    testWidgets('a throttled sign-in says so rather than "wrong password"',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester);
      backend.on(
        'POST',
        '/api/auth/login/',
        {'detail': 'Request was throttled. Expected available in 42 seconds.'},
        status: 429,
      );

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'amadou');
      await tester.enterText(find.byType(TextFormField).last, 'correct');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Too many attempts. Wait a moment and try again.'),
          findsOneWidget);
      // Telling somebody their password is wrong when it is not sends them
      // to reset an account that was fine.
      expect(find.text('Wrong username or password.'), findsNothing);
      // And never the server's own English second-count.
      expect(find.textContaining('Expected available'), findsNothing);
    });

    testWidgets('it reads in French too', (tester) async {
      final (:auth, :backend) = buildAuth(tester);
      backend.on(
        'POST',
        '/api/auth/login/',
        {'detail': 'Request was throttled.'},
        status: 429,
      );

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore('fr')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'amadou');
      await tester.enterText(find.byType(TextFormField).last, 'correct');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Trop de tentatives'), findsOneWidget);
    });

    testWidgets('a genuinely wrong password still says that', (tester) async {
      final (:auth, :backend) = buildAuth(tester);
      backend.on(
        'POST',
        '/api/auth/login/',
        {'detail': 'Invalid credentials.'},
        status: 400,
      );

      await tester.pumpWidget(
        MerchantApp(auth: auth, localeStore: InMemoryLocaleStore()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'amadou');
      await tester.enterText(find.byType(TextFormField).last, 'wrong');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong username or password.'), findsOneWidget);
    });
  });

  group('reading your own reviews', () {
    Map<String, dynamic> reviewJson({
      int id = 1,
      int rating = 5,
      String comment = 'Lovely evening',
      String author = 'Mariama',
      bool isFlagged = false,
      bool isHidden = false,
    }) =>
        {
          'id': id,
          'rating': rating,
          'comment': comment,
          'author_display_name': author,
          'visit_date': '2026-08-01T19:00:00Z',
          'created_at': '2026-08-02T09:00:00Z',
          'is_flagged': isFlagged,
          'flagged_at': isFlagged ? '2026-08-02T10:00:00Z' : null,
          'flagged_reason': isFlagged ? 'Never came in' : '',
          'is_hidden': isHidden,
        };

    Future<FakeBackend> openReviews(
      WidgetTester tester, {
      List<Map<String, dynamic>>? reviews,
      Map<String, int>? distribution,
      double? average = 4.5,
      String role = 'owner',
      String? language,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/merchant/establishments/', {
        'results': [venueJson(role: role)],
      });
      backend.on('GET', '/api/reservations/', {
        'count': 0,
        'next': null,
        'results': [],
      });
      backend.on('GET', '/api/merchant/orders/', {'results': []});
      backend.on('GET', '/api/merchant/establishments/7/reviews/', {
        'count': (reviews ?? [reviewJson()]).length,
        'next': null,
        'results': reviews ?? [reviewJson()],
        'average_rating': average,
        'distribution': distribution ??
            {'1': 0, '2': 0, '3': 0, '4': 1, '5': 1},
      });

      await tester.pumpWidget(
        MerchantApp(
          auth: auth,
          localeStore: InMemoryLocaleStore(language),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('everyone who works there can reach them', (tester) async {
      // Knowing what customers said is floor knowledge, not a privilege.
      await openReviews(tester, role: 'staff');

      expect(find.text('Reviews'), findsOneWidget);
    });

    testWidgets('a review is shown with its stars and its words',
        (tester) async {
      await openReviews(tester);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('Lovely evening'), findsOneWidget);
      expect(find.text('Mariama'), findsOneWidget);
    });

    testWidgets('the spread is shown, not just the average', (tester) async {
      // One angry two-star among forty fives is a different business from a
      // steady drift downwards.
      await openReviews(
        tester,
        average: 4.2,
        distribution: {'1': 0, '2': 1, '3': 0, '4': 2, '5': 12},
      );

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('4.2'), findsOneWidget);
      expect(find.text('15 reviews'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('a venue with no reviews is told what happens', (tester) async {
      await openReviews(
        tester,
        reviews: [],
        distribution: {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
        average: null,
      );

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('No reviews yet'), findsOneWidget);
    });

    testWidgets('an owner can report one', (tester) async {
      await openReviews(tester, reviews: [reviewJson(rating: 1)]);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('Report this review'), findsOneWidget);
    });

    testWidgets('staff cannot', (tester) async {
      await openReviews(
        tester,
        role: 'staff',
        reviews: [reviewJson(rating: 1)],
      );

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('Report this review'), findsNothing);
    });

    testWidgets('reporting says plainly that it is not a delete button',
        (tester) async {
      // **The wording that keeps the ratings honest.** A venue must not
      // believe it just removed a review.
      await openReviews(tester, reviews: [reviewJson(rating: 1)]);

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report this review'));
      await tester.pumpAndSettle();

      expect(find.textContaining('stays visible to customers'), findsOneWidget);
      expect(
        find.textContaining('cannot take down its own reviews'),
        findsOneWidget,
      );
    });

    testWidgets('a reason is required', (tester) async {
      final backend = await openReviews(
        tester,
        reviews: [reviewJson(rating: 1)],
      );

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report this review'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      expect(find.text('Say what is wrong with it.'), findsOneWidget);
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('reporting posts the reason', (tester) async {
      final backend = await openReviews(
        tester,
        reviews: [reviewJson(rating: 1)],
      );
      backend.on(
        'POST',
        '/api/merchant/establishments/7/reviews/1/flag/',
        reviewJson(rating: 1, isFlagged: true),
      );

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report this review'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'This customer never came in',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      final posted = backend.requests.lastWhere((r) => r.method == 'POST');
      expect(
        jsonDecode(posted.body) as Map<String, dynamic>,
        {'reason': 'This customer never came in'},
      );
    });

    testWidgets('a reported review stays on screen, marked', (tester) async {
      // It is still visible to customers, so hiding it from the venue would
      // be a lie about what happened.
      await openReviews(
        tester,
        reviews: [reviewJson(rating: 1, isFlagged: true)],
      );

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.textContaining('waiting to be looked at'), findsOneWidget);
      expect(find.text('Report this review'), findsNothing);
    });

    testWidgets('one an admin took down says so', (tester) async {
      // So the merchant knows why it is missing from their average.
      await openReviews(
        tester,
        reviews: [reviewJson(rating: 1, isHidden: true)],
      );

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('Taken down'), findsOneWidget);
    });

    testWidgets('it reads in French', (tester) async {
      await openReviews(tester, language: 'fr');

      await tester.tap(find.text('Avis'));
      await tester.pumpAndSettle();

      expect(find.text('Signaler cet avis'), findsOneWidget);
    });

    testWidgets('the card fits a 360dp phone', (tester) async {
      await openReviews(
        tester,
        reviews: [
          reviewJson(
            comment: 'A very long comment about the evening that goes on and '
                'on and would certainly wrap on a narrow screen.',
            author: 'Mariama',
          ),
        ],
      );

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.text('Mariama'));
      expect(rect.right, lessThanOrEqualTo(phoneSize.width));
    });
  });
}
