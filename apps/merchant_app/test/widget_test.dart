import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merchant_app/src/app.dart';
import 'package:merchant_app/src/auth_controller.dart';
import 'package:merchant_app/src/token_store.dart';
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

({AuthController auth, FakeBackend backend}) buildAuth(
  WidgetTester tester, {
  String? storedToken,
}) {
  // A merchant reads this on a phone in a dim lounge, not on an 800x600
  // desktop surface. Testing at 360x900 is what surfaced two overflow bugs in
  // the customer app, so this app is held to the same width.
  tester.view.physicalSize = const Size(1080, 2700);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final backend = FakeBackend();
  final auth = AuthController(
    api: SylibookingApi(
      baseUrl: 'http://localhost:8000/api',
      httpClient: backend.client,
    ),
    tokenStore: InMemoryTokenStore(storedToken),
  );
  return (auth: auth, backend: backend);
}

void main() {
  group('login screen', () {
    testWidgets('is shown when there is no stored token', (tester) async {
      final (:auth, :backend) = buildAuth(tester);

      await tester.pumpWidget(MerchantApp(auth: auth));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Reservations'), findsNothing);
    });

    testWidgets('validates empty fields before calling the API',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester);

      await tester.pumpWidget(MerchantApp(auth: auth));
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

      await tester.pumpWidget(MerchantApp(auth: auth));
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

      await tester.pumpWidget(MerchantApp(auth: auth));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'amadou');
      await tester.enterText(find.byType(TextFormField).last, 'pw');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Reservations'), findsOneWidget);
      expect(find.text('Le Petit Baobab'), findsOneWidget);
      expect(find.text('Mariama Diallo'), findsOneWidget);
    });

    testWidgets('a stored token skips the login screen', (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', {'count': 0, 'results': []});

      await tester.pumpWidget(MerchantApp(auth: auth));
      await tester.pumpAndSettle();

      expect(find.text('Reservations'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('a rejected stored token falls back to login', (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'expired');
      backend.on('GET', '/api/auth/me/', {'detail': 'Invalid token.'},
          status: 401);

      await tester.pumpWidget(MerchantApp(auth: auth));
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

      await tester.pumpWidget(MerchantApp(auth: auth));
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

      await tester.pumpWidget(MerchantApp(auth: auth));
      await tester.pumpAndSettle();

      expect(find.text('Could not load reservations'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a user with no venue is told why the list is empty',
        (tester) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user(establishments: []));
      backend.on('GET', '/api/reservations/', {'count': 0, 'results': []});

      await tester.pumpWidget(MerchantApp(auth: auth));
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

      expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
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

      await tester.pumpWidget(MerchantApp(auth: auth));
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

      await tester.pumpWidget(MerchantApp(auth: auth));
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

  group('signing out', () {
    Future<FakeBackend> signedIn(
      WidgetTester tester, {
      required Object reservationsBody,
    }) async {
      final (:auth, :backend) = buildAuth(tester, storedToken: 'stored-token');
      backend.on('GET', '/api/auth/me/', user());
      backend.on('GET', '/api/reservations/', reservationsBody);

      await tester.pumpWidget(MerchantApp(auth: auth));
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
}
