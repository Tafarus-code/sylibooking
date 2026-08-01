import 'dart:convert';

import 'package:http/http.dart' as http;

import 'customer_models.dart';
import 'models.dart';
import 'order_models.dart';

/// A non-2xx response from the API.
///
/// DRF returns errors as `{"field": ["message"], ...}` or `{"detail": "..."}`;
/// [message] flattens either into something showable in a snackbar.
class ApiException implements Exception {
  ApiException(this.statusCode, this.errors, {this.rawBody = ''});

  final int statusCode;
  final Map<String, dynamic> errors;
  final String rawBody;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isNotFound => statusCode == 404;

  String get message {
    if (errors.isEmpty) {
      return rawBody.isEmpty ? 'Request failed ($statusCode)' : rawBody;
    }
    if (errors['detail'] case final detail?) return detail.toString();

    // Non-field errors first, then "field: message" for the rest.
    final parts = <String>[];
    for (final entry in errors.entries) {
      final value = entry.value;
      final text = value is List ? value.join(' ') : value.toString();
      parts.add(
        entry.key == 'non_field_errors' ? text : '${entry.key}: $text',
      );
    }
    return parts.join('\n');
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thrown when the API cannot be reached at all.
class ApiUnreachableException implements Exception {
  ApiUnreachableException(this.cause);

  final Object cause;

  String get message =>
      'Could not reach the server. Check the connection and the API address.';

  @override
  String toString() => 'ApiUnreachableException: $cause';
}

/// HTTP client for the Sylibooking API, shared by both apps.
///
/// Holds an auth token once [login] succeeds, or accepts a stored one via
/// [token] so a returning user is not asked to sign in again.
class SylibookingApi {
  SylibookingApi({required this.baseUrl, http.Client? httpClient, this.token})
      : _http = httpClient ?? http.Client();

  /// Root of the API, e.g. `http://10.0.2.2:8000/api`. No trailing slash.
  final String baseUrl;
  final http.Client _http;

  String? token;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (isAuthenticated) 'Authorization': 'Token $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
        '$baseUrl$path',
      ).replace(queryParameters: query?.isEmpty ?? true ? null : query);

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } on Object catch (error) {
      throw ApiUnreachableException(error);
    }

    if (response.statusCode == 204 || response.body.isEmpty) {
      if (response.statusCode >= 400) {
        throw ApiException(response.statusCode, const {});
      }
      return null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (response.statusCode >= 400) {
        throw ApiException(response.statusCode, const {},
            rawBody: response.body);
      }
      rethrow;
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        decoded is Map<String, dynamic> ? decoded : {'detail': decoded},
        rawBody: response.body,
      );
    }
    return decoded;
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) =>
      _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) => _send(
        () => _http.post(
          _uri(path),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        ),
      );

  Future<dynamic> _patch(String path, Map<String, dynamic> body) => _send(
        () => _http.patch(_uri(path), headers: _headers, body: jsonEncode(body)),
      );

  /// Takes a list body: the hours endpoint replaces a whole week at once.
  Future<dynamic> _put(String path, Object body) => _send(
        () => _http.put(_uri(path), headers: _headers, body: jsonEncode(body)),
      );

  Future<dynamic> _delete(String path) =>
      _send(() => _http.delete(_uri(path), headers: _headers));

  // --- Auth ---------------------------------------------------------------

  /// Exchange credentials for a token, which is then kept on this client.
  Future<LoginResult> login(String username, String password) async {
    final json = await _post('/auth/login/', {
      'username': username,
      'password': password,
    });
    final result = LoginResult.fromJson(json as Map<String, dynamic>);
    token = result.token;
    return result;
  }

  /// Check a stored token is still valid, and refresh the user's venues.
  Future<MerchantUser> me() async {
    final json = await _get('/auth/me/');
    return MerchantUser.fromJson(json as Map<String, dynamic>);
  }

  /// Invalidate the token server-side, then forget it locally.
  Future<void> logout() async {
    try {
      await _post('/auth/logout/');
    } on ApiException catch (e) {
      // An already-invalid token is a successful logout as far as the app is
      // concerned; anything else is worth surfacing.
      if (!e.isUnauthorized) rethrow;
    } finally {
      token = null;
    }
  }

  // --- Establishments -----------------------------------------------------

  Future<Page<Establishment>> establishments({
    String? city,
    String? type,
    String? search,
  }) async {
    final json = await _get('/establishments/', {
      'city': ?city,
      'type': ?type,
      'search': ?search,
    });
    return Page.fromJson(json as Map<String, dynamic>, Establishment.fromJson);
  }

  Future<Establishment> establishment(int id) async {
    final json = await _get('/establishments/$id/');
    return Establishment.fromJson(json as Map<String, dynamic>);
  }

  /// Slot grid for one day. [date] is used date-only.
  Future<List<SpaceAvailability>> availability(
    int establishmentId,
    DateTime date, {
    int? partySize,
  }) async {
    final json = await _get('/establishments/$establishmentId/availability/', {
      'date': formatDate(date),
      if (partySize != null) 'party_size': '$partySize',
    });
    final spaces = (json as Map<String, dynamic>)['spaces'] as List<dynamic>;
    return spaces
        .map((e) => SpaceAvailability.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Reservations -------------------------------------------------------

  /// Merchant-side listing for one venue.
  ///
  /// [establishmentId] is required — listings are no longer merged across
  /// venues, and the server refuses one the caller has no membership in.
  /// [date] matches one day; [from]/[to] match an inclusive range.
  Future<Page<Reservation>> reservations({
    required int establishmentId,
    ReservationStatus? status,
    DateTime? date,
    DateTime? from,
    DateTime? to,
    int? page,
  }) async {
    final json = await _get('/reservations/', {
      'establishment': '$establishmentId',
      if (status != null) 'status': status.wireValue,
      if (date != null) 'date': formatDate(date),
      if (from != null) 'date_from': formatDate(from),
      if (to != null) 'date_to': formatDate(to),
      if (page != null) 'page': '$page',
    });
    return Page.fromJson(json as Map<String, dynamic>, Reservation.fromJson);
  }

  /// Every reservation in a range, following pagination.
  ///
  /// A week at a busy venue exceeds one page, and a merchant scrolling their
  /// calendar should not silently see only the first twenty.
  Future<List<Reservation>> allReservations({
    required int establishmentId,
    ReservationStatus? status,
    DateTime? date,
    DateTime? from,
    DateTime? to,
    int maxPages = 20,
  }) async {
    final all = <Reservation>[];
    for (var pageNumber = 1; pageNumber <= maxPages; pageNumber++) {
      final page = await reservations(
        establishmentId: establishmentId,
        status: status,
        date: date,
        from: from,
        to: to,
        page: pageNumber,
      );
      all.addAll(page.results);
      if (page.next == null || page.results.isEmpty) break;
    }
    return all;
  }

  /// One booking by id. Merchant-only — scoped to the caller's own venues.
  /// Customers use [reservationByReference] instead.
  Future<Reservation> reservation(int id) async {
    final json = await _get('/reservations/$id/');
    return Reservation.fromJson(json as Map<String, dynamic>);
  }

  /// One booking by its reference. Needs no account: holding the reference is
  /// what proves the booking is yours.
  Future<Reservation> reservationByReference(String reference) async {
    final json = await _get('/reservations/ref/$reference/');
    return Reservation.fromJson(json as Map<String, dynamic>);
  }

  /// Customer cancels their own booking, freeing the slot.
  ///
  /// Cancelling twice succeeds rather than erroring. A booking that has
  /// already started throws [ApiException] with `isConflict`.
  Future<Reservation> cancelReservationByReference(String reference) async {
    final json = await _post('/reservations/ref/$reference/cancel/');
    return Reservation.fromJson(json as Map<String, dynamic>);
  }

  /// Book a slot.
  ///
  /// [paymentProvider] defaults to cash on arrival, which leaves the booking
  /// pending for the merchant to confirm. A mobile money provider opens a
  /// payment; the booking confirms only once that payment completes. The
  /// amount is decided by the server — it is deliberately not a parameter.
  Future<Reservation> createReservation({
    required int spaceId,
    required String customerName,
    required String customerPhone,
    required DateTime when,
    required int partySize,
    PaymentProvider paymentProvider = PaymentProvider.cashOnArrival,
  }) async {
    final json = await _post('/reservations/', {
      'space': spaceId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'datetime': when.toUtc().toIso8601String(),
      'party_size': partySize,
      'payment_provider': paymentProvider.wireValue,
    });
    return Reservation.fromJson(json as Map<String, dynamic>);
  }

  /// Ask where a booking's payment stands.
  ///
  /// The server polls the provider and applies the result, so a payment that
  /// settled since the last call confirms the booking here.
  Future<PaymentStatusResult> paymentStatus(String reference) async {
    final json = await _get('/reservations/ref/$reference/payment/');
    return PaymentStatusResult.fromJson(json as Map<String, dynamic>);
  }

  Future<Reservation> confirmReservation(int id) async {
    final json = await _post('/reservations/$id/confirm/');
    return Reservation.fromJson(json as Map<String, dynamic>);
  }

  Future<Reservation> cancelReservation(int id) async {
    final json = await _post('/reservations/$id/cancel/');
    return Reservation.fromJson(json as Map<String, dynamic>);
  }

  // --- Customer accounts (optional) ----------------------------------------

  /// Make an account. Signup signs you in, so a token comes back with it.
  Future<CustomerSession> registerCustomer({
    required String username,
    required String password,
    String name = '',
    // Optional, and the only way back in after a forgotten password.
    String phone = '',
    String email = '',
  }) async {
    final json = await _post('/customer/register/', {
      'username': username,
      'password': password,
      'name': name,
      'phone': phone,
      'email': email,
    });
    final session = CustomerSession.fromJson(json as Map<String, dynamic>);
    token = session.token;
    return session;
  }

  /// Sign in an existing customer. Shares the merchant login endpoint —
  /// one user table, and a customer is simply a user with no venues.
  Future<CustomerSession> signInCustomer({
    required String username,
    required String password,
  }) async {
    final json = await _post('/auth/login/', {
      'username': username,
      'password': password,
    });
    final map = json as Map<String, dynamic>;
    final session = CustomerSession(
      token: map['token'] as String,
      customer: CustomerAccount.fromJson(
        map['user'] as Map<String, dynamic>,
      ),
    );
    token = session.token;
    return session;
  }

  /// Ask for a reset code. The answer is the same whether or not the account
  /// exists, so the app must not treat "sent" as proof of anything.
  Future<PasswordResetRequest> requestPasswordReset(String identifier) async {
    final json = await _post('/customer/password-reset/', {
      'identifier': identifier,
    });
    return PasswordResetRequest.fromJson(json as Map<String, dynamic>);
  }

  /// Use the code. Succeeds or throws with a message worth showing.
  Future<String> confirmPasswordReset({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    final json = await _post('/customer/password-reset/confirm/', {
      'identifier': identifier,
      'code': code,
      'new_password': newPassword,
    });
    return (json as Map<String, dynamic>)['detail'] as String? ?? '';
  }

  Future<CustomerAccount> customerMe() async {
    final json = await _get('/customer/me/');
    return CustomerAccount.fromJson(json as Map<String, dynamic>);
  }

  /// Hand this phone's bookings and orders to the account just signed into.
  Future<({int reservations, int orders})> claim({
    List<String> reservationReferences = const [],
    List<String> orderReferences = const [],
  }) async {
    final json = await _post('/customer/claim/', {
      'reservation_references': reservationReferences,
      'order_references': orderReferences,
    });
    final map = json as Map<String, dynamic>;
    return (
      reservations: map['reservations'] as int? ?? 0,
      orders: map['orders'] as int? ?? 0,
    );
  }

  /// Everything this account has booked or ordered, from the server rather
  /// than from this phone — which is the whole point of having one.
  Future<({List<Reservation> reservations, List<Order> orders})>
      customerHistory() async {
    final json = await _get('/customer/history/') as Map<String, dynamic>;
    return (
      reservations: (json['reservations'] as List<dynamic>? ?? [])
          .map((e) => Reservation.fromJson(e as Map<String, dynamic>))
          .toList(),
      orders: (json['orders'] as List<dynamic>? ?? [])
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<Establishment>> favourites() async {
    final json = await _get('/customer/favourites/') as Map<String, dynamic>;
    return (json['results'] as List<dynamic>? ?? [])
        .map((e) => Establishment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Save one venue, or merge a phone's whole list up at sign-in.
  Future<List<Establishment>> addFavourites(List<int> establishmentIds) async {
    final json = await _post('/customer/favourites/', {
      'establishments': establishmentIds,
    }) as Map<String, dynamic>;
    return (json['results'] as List<dynamic>? ?? [])
        .map((e) => Establishment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeFavourite(int establishmentId) async {
    await _delete('/customer/favourites/$establishmentId/');
  }

  // --- Ordering ahead -------------------------------------------------------

  /// Place a pickup order. No account: the reference that comes back is the
  /// only handle on it, exactly as with a booking.
  Future<Order> createOrder({
    required int establishmentId,
    required String customerName,
    required String customerPhone,
    required DateTime pickupTime,
    required List<CartLine> items,
    PaymentProvider paymentProvider = PaymentProvider.cashOnArrival,
    String? reservationReference,
  }) async {
    final json = await _post('/orders/', {
      'establishment': establishmentId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'pickup_time': pickupTime.toUtc().toIso8601String(),
      'items': [for (final line in items) line.toJson()],
      'payment_provider': paymentProvider.wireValue,
      'reservation_reference': ?reservationReference,
    });
    return Order.fromJson(json as Map<String, dynamic>);
  }

  /// Follow an order. The server polls the payment provider on the way, so
  /// refreshing this screen is what settles a payment that went through.
  Future<Order> orderByReference(String reference) async {
    final json = await _get('/orders/ref/$reference/');
    return Order.fromJson(json as Map<String, dynamic>);
  }

  /// The kitchen queue for one venue, for the day being worked.
  Future<List<Order>> merchantOrders({
    required int establishmentId,
    DateTime? date,
  }) async {
    final json = await _get('/merchant/orders/', {
      'establishment': '$establishmentId',
      if (date != null) 'date': formatDate(date),
    });
    final results = (json as Map<String, dynamic>)['results'] as List<dynamic>;
    return results
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Order> setOrderStatus(int orderId, OrderStatus status) async {
    final json = await _post('/merchant/orders/$orderId/status/', {
      'status': status.wireValue,
    });
    return Order.fromJson(json as Map<String, dynamic>);
  }

  // --- Reviews and photos -------------------------------------------------

  Future<Page<Review>> reviews(int establishmentId, {int? page}) async {
    final json = await _get('/establishments/$establishmentId/reviews/', {
      if (page != null) 'page': '$page',
    });
    return Page.fromJson(json as Map<String, dynamic>, Review.fromJson);
  }

  /// Leave a review for a completed visit.
  ///
  /// [reservationReference] is the credential: customers have no accounts, so
  /// holding the reference is what proves the visit happened. The server
  /// rejects anything not completed, not at this venue, or already reviewed.
  Future<Review> createReview({
    required int establishmentId,
    required String reservationReference,
    required int rating,
    String comment = '',
  }) async {
    final json = await _post('/establishments/$establishmentId/reviews/', {
      'reservation_reference': reservationReference,
      'rating': rating,
      'comment': comment,
    });
    return Review.fromJson(json as Map<String, dynamic>);
  }

  Future<Page<Photo>> photos(int establishmentId, {int? page}) async {
    final json = await _get('/establishments/$establishmentId/photos/', {
      if (page != null) 'page': '$page',
    });
    return Page.fromJson(json as Map<String, dynamic>, Photo.fromJson);
  }

  /// Upload a photo.
  ///
  /// Pass [reservationReference] as a customer, or authenticate as staff of
  /// the establishment. [bytes] and [filename] come from the image picker.
  Future<Photo> uploadPhoto({
    required int establishmentId,
    required List<int> bytes,
    required String filename,
    String? reservationReference,
    String caption = '',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/establishments/$establishmentId/photos/'),
    );
    if (isAuthenticated) {
      request.headers['Authorization'] = 'Token $token';
    }
    if (reservationReference != null) {
      request.fields['reservation_reference'] = reservationReference;
    }
    if (caption.isNotEmpty) request.fields['caption'] = caption;
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: filename),
    );

    final json = await _send(() async {
      final streamed = await _http.send(request);
      return http.Response.fromStream(streamed);
    });
    return Photo.fromJson(json as Map<String, dynamic>);
  }

  // --- Merchant venues ----------------------------------------------------

  /// The venues this user has a membership in, with their role at each.
  Future<List<MerchantVenue>> merchantVenues() async {
    final json = await _get('/merchant/establishments/');
    final results = (json as Map<String, dynamic>)['results'] as List<dynamic>;
    return results
        .map((e) => MerchantVenue.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a venue. The caller becomes its owner.
  Future<Establishment> createEstablishment({
    required String name,
    required String type,
    required String city,
    required String address,
    String tagline = '',
    String description = '',
  }) async {
    final json = await _post('/merchant/establishments/', {
      'name': name,
      'type': type,
      'city': city,
      'address': address,
      'tagline': tagline,
      'description': description,
    });
    return Establishment.fromJson(json as Map<String, dynamic>);
  }

  /// The venue's editable profile. Any member may read it.
  Future<Establishment> merchantProfile(int establishmentId) async {
    final json = await _get('/merchant/establishments/$establishmentId/');
    return Establishment.fromJson(json as Map<String, dynamic>);
  }

  /// Owner and manager only; the server returns 403 for staff.
  Future<Establishment> updateProfile(
    int establishmentId,
    Map<String, dynamic> fields,
  ) async {
    final json = await _patch(
      '/merchant/establishments/$establishmentId/',
      fields,
    );
    return Establishment.fromJson(json as Map<String, dynamic>);
  }

  // --- Merchant hours -----------------------------------------------------

  Future<List<OpeningHours>> merchantHours(int establishmentId) async {
    final json = await _get('/merchant/establishments/$establishmentId/hours/');
    final results = (json as Map<String, dynamic>)['results'] as List<dynamic>;
    return results
        .map((e) => OpeningHours.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Replace the whole week. A week is edited as a unit, so this is a PUT.
  Future<List<OpeningHours>> replaceHours(
    int establishmentId,
    List<Map<String, dynamic>> week,
  ) async {
    final json = await _put(
      '/merchant/establishments/$establishmentId/hours/',
      week,
    );
    final results = (json as Map<String, dynamic>)['results'] as List<dynamic>;
    return results
        .map((e) => OpeningHours.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Merchant menu ------------------------------------------------------

  /// Every item including unavailable ones. Any member may read it.
  Future<List<MerchantMenuItem>> merchantMenu(int establishmentId) async {
    final json = await _get('/merchant/establishments/$establishmentId/menu/');
    final results = (json as Map<String, dynamic>)['results'] as List<dynamic>;
    return results
        .map((e) => MerchantMenuItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MerchantMenuItem> createMenuItem(
    int establishmentId,
    Map<String, dynamic> fields,
  ) async {
    final json = await _post(
      '/merchant/establishments/$establishmentId/menu/',
      fields,
    );
    return MerchantMenuItem.fromJson(json as Map<String, dynamic>);
  }

  /// Attach or replace an item's picture.
  ///
  /// Separate from [updateMenuItem] because it is multipart; the rest of the
  /// item is JSON, and mixing the two would make every text edit an upload.
  Future<MerchantMenuItem> uploadMenuItemImage({
    required int establishmentId,
    required int itemId,
    required List<int> bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'PATCH',
      _uri('/merchant/establishments/$establishmentId/menu/$itemId/'),
    );
    if (isAuthenticated) {
      request.headers['Authorization'] = 'Token $token';
    }
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: filename),
    );

    final json = await _send(() async {
      final streamed = await _http.send(request);
      return http.Response.fromStream(streamed);
    });
    return MerchantMenuItem.fromJson(json as Map<String, dynamic>);
  }

  Future<MerchantMenuItem> updateMenuItem(
    int establishmentId,
    int itemId,
    Map<String, dynamic> fields,
  ) async {
    final json = await _patch(
      '/merchant/establishments/$establishmentId/menu/$itemId/',
      fields,
    );
    return MerchantMenuItem.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deleteMenuItem(int establishmentId, int itemId) async {
    await _delete('/merchant/establishments/$establishmentId/menu/$itemId/');
  }

  /// Mark an item sold out, or back on. Staff may do this; it is the one
  /// menu change their role allows.
  Future<MerchantMenuItem> setMenuItemAvailability(
    int establishmentId,
    int itemId,
    bool isAvailable,
  ) async {
    final json = await _patch(
      '/merchant/establishments/$establishmentId/menu/$itemId/availability/',
      {'is_available': isAvailable},
    );
    return MerchantMenuItem.fromJson(json as Map<String, dynamic>);
  }

  // --- Merchant staff -----------------------------------------------------

  /// Owner only; the server returns 403 for manager and staff alike.
  Future<List<Membership>> merchantStaff(int establishmentId) async {
    final json = await _get('/merchant/establishments/$establishmentId/staff/');
    final results = (json as Map<String, dynamic>)['results'] as List<dynamic>;
    return results
        .map((e) => Membership.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Membership> addStaff(
    int establishmentId, {
    required String username,
    required MerchantRole role,
  }) async {
    final json = await _post(
      '/merchant/establishments/$establishmentId/staff/',
      {'username': username, 'role': role.name.toLowerCase()},
    );
    return Membership.fromJson(json as Map<String, dynamic>);
  }

  Future<Membership> changeStaffRole(
    int establishmentId,
    int membershipId,
    MerchantRole role,
  ) async {
    final json = await _patch(
      '/merchant/establishments/$establishmentId/staff/$membershipId/',
      {'role': role.name.toLowerCase()},
    );
    return Membership.fromJson(json as Map<String, dynamic>);
  }

  Future<void> removeStaff(int establishmentId, int membershipId) async {
    await _delete(
      '/merchant/establishments/$establishmentId/staff/$membershipId/',
    );
  }

  // --- Merchant dashboard -------------------------------------------------

  /// Takings, outstanding money, and bookings worth chasing, for one venue.
  ///
  /// [establishmentId] is required: figures are no longer merged across
  /// venues, and the server refuses a venue the caller has no part in.
  Future<PaymentDashboard> paymentDashboard({
    required int establishmentId,
    DateTime? from,
    DateTime? to,
  }) async {
    final json = await _get('/dashboard/payments/', {
      'establishment': '$establishmentId',
      if (from != null) 'date_from': formatDate(from),
      if (to != null) 'date_to': formatDate(to),
    });
    return PaymentDashboard.fromJson(json as Map<String, dynamic>);
  }

  void close() => _http.close();
}

/// `YYYY-MM-DD` in local time, which is what the API's `date` params expect.
String formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}