/// Dart mirrors of the DRF serializers in `backend/api/serializers.py`.
///
/// Every model parses from JSON only — the apps never construct these to send
/// back, they send plain maps, so there is no `toJson` to drift out of sync.
library;

enum EstablishmentType {
  lounge,
  restaurant,
  unknown;

  static EstablishmentType parse(String? value) => switch (value) {
        'lounge' => EstablishmentType.lounge,
        'restaurant' => EstablishmentType.restaurant,
        _ => EstablishmentType.unknown,
      };
}

enum SpaceType {
  table,
  vipRoom,
  terrace,
  unknown;

  static SpaceType parse(String? value) => switch (value) {
        'table' => SpaceType.table,
        'vip_room' => SpaceType.vipRoom,
        'terrace' => SpaceType.terrace,
        _ => SpaceType.unknown,
      };
}

/// Mirrors `Reservation.Status`.
enum ReservationStatus {
  pending,
  confirmed,
  cancelled,
  completed,
  unknown;

  static ReservationStatus parse(String? value) => switch (value) {
        'pending' => ReservationStatus.pending,
        'confirmed' => ReservationStatus.confirmed,
        'cancelled' => ReservationStatus.cancelled,
        'completed' => ReservationStatus.completed,
        _ => ReservationStatus.unknown,
      };

  String get wireValue => switch (this) {
        ReservationStatus.pending => 'pending',
        ReservationStatus.confirmed => 'confirmed',
        ReservationStatus.cancelled => 'cancelled',
        ReservationStatus.completed => 'completed',
        ReservationStatus.unknown => '',
      };

  /// Whether the merchant can still act on a booking in this state.
  bool get isOpen =>
      this == ReservationStatus.pending || this == ReservationStatus.confirmed;
}

class Space {
  const Space({
    required this.id,
    required this.name,
    required this.type,
    required this.typeDisplay,
    required this.capacity,
  });

  final int id;
  final String name;
  final SpaceType type;
  final String typeDisplay;
  final int capacity;

  factory Space.fromJson(Map<String, dynamic> json) => Space(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        type: SpaceType.parse(json['type'] as String?),
        typeDisplay: json['type_display'] as String? ?? '',
        capacity: json['capacity'] as int? ?? 0,
      );
}

class Establishment {
  const Establishment({
    required this.id,
    required this.name,
    required this.type,
    required this.typeDisplay,
    required this.city,
    required this.address,
    this.openingHours = '',
    this.spaceCount,
    this.spaces = const [],
  });

  final int id;
  final String name;
  final EstablishmentType type;
  final String typeDisplay;
  final String city;
  final String address;
  final String openingHours;

  /// Present on the list endpoint only.
  final int? spaceCount;

  /// Present on the detail endpoint only.
  final List<Space> spaces;

  factory Establishment.fromJson(Map<String, dynamic> json) => Establishment(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        type: EstablishmentType.parse(json['type'] as String?),
        typeDisplay: json['type_display'] as String? ?? '',
        city: json['city'] as String? ?? '',
        address: json['address'] as String? ?? '',
        openingHours: json['opening_hours'] as String? ?? '',
        spaceCount: json['space_count'] as int?,
        spaces: (json['spaces'] as List<dynamic>? ?? [])
            .map((e) => Space.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Reservation {
  const Reservation({
    required this.id,
    required this.reference,
    required this.spaceId,
    required this.spaceName,
    required this.establishmentId,
    required this.establishmentName,
    required this.customerName,
    required this.customerPhone,
    required this.dateTime,
    required this.partySize,
    required this.status,
    required this.statusDisplay,
    this.canCancel = false,
    this.payment,
  });

  final int id;

  /// Unguessable handle proving this booking is the caller's. Customers have
  /// no accounts, so this is how they read or cancel it later.
  final String reference;

  final int spaceId;
  final String spaceName;
  final int? establishmentId;
  final String establishmentName;
  final String customerName;
  final String customerPhone;

  /// Always held in local time; the API sends UTC.
  final DateTime dateTime;
  final int partySize;
  final ReservationStatus status;
  final String statusDisplay;

  /// Whether the customer may still cancel this themselves. The server decides
  /// — a booking that has started or already happened is the venue's to undo.
  final bool canCancel;

  /// The most recent payment, or null for a cash-on-arrival booking.
  final Payment? payment;

  factory Reservation.fromJson(Map<String, dynamic> json) => Reservation(
        id: json['id'] as int,
        reference: json['reference'] as String? ?? '',
        spaceId: json['space'] as int,
        spaceName: json['space_name'] as String? ?? '',
        establishmentId: json['establishment'] as int?,
        establishmentName: json['establishment_name'] as String? ?? '',
        customerName: json['customer_name'] as String? ?? '',
        customerPhone: json['customer_phone'] as String? ?? '',
        dateTime: DateTime.parse(json['datetime'] as String).toLocal(),
        partySize: json['party_size'] as int? ?? 0,
        status: ReservationStatus.parse(json['status'] as String?),
        statusDisplay: json['status_display'] as String? ?? '',
        canCancel: json['can_cancel'] as bool? ?? false,
        payment: json['payment'] == null
            ? null
            : Payment.fromJson(json['payment'] as Map<String, dynamic>),
      );
}

/// How a booking is being paid for. Mirrors `Payment.Provider`.
enum PaymentProvider {
  cashOnArrival,
  orangeMoney,
  mtnMoney,
  unknown;

  static PaymentProvider parse(String? value) => switch (value) {
        'cash_on_arrival' => PaymentProvider.cashOnArrival,
        'orange_money' => PaymentProvider.orangeMoney,
        'mtn_money' => PaymentProvider.mtnMoney,
        _ => PaymentProvider.unknown,
      };

  String get wireValue => switch (this) {
        PaymentProvider.cashOnArrival => 'cash_on_arrival',
        PaymentProvider.orangeMoney => 'orange_money',
        PaymentProvider.mtnMoney => 'mtn_money',
        PaymentProvider.unknown => '',
      };

  /// Settled through an external provider rather than in person, which is what
  /// makes a booking confirm on payment instead of waiting for the merchant.
  bool get isMobileMoney =>
      this == PaymentProvider.orangeMoney || this == PaymentProvider.mtnMoney;
}

/// Mirrors `Payment.Status`.
enum PaymentStatus {
  pending,
  completed,
  failed,
  unknown;

  static PaymentStatus parse(String? value) => switch (value) {
        'pending' => PaymentStatus.pending,
        'completed' => PaymentStatus.completed,
        'failed' => PaymentStatus.failed,
        _ => PaymentStatus.unknown,
      };

  /// Still moving — worth polling again.
  bool get isSettled =>
      this == PaymentStatus.completed || this == PaymentStatus.failed;
}

class Payment {
  const Payment({
    required this.id,
    required this.provider,
    required this.providerDisplay,
    required this.amount,
    required this.status,
    required this.statusDisplay,
    this.providerReference,
  });

  final int id;
  final PaymentProvider provider;
  final String providerDisplay;

  /// Guinean francs. Set server-side — the client never chooses what it owes.
  final String amount;
  final PaymentStatus status;
  final String statusDisplay;
  final String? providerReference;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as int,
        provider: PaymentProvider.parse(json['provider'] as String?),
        providerDisplay: json['provider_display'] as String? ?? '',
        amount: '${json['amount'] ?? ''}',
        status: PaymentStatus.parse(json['status'] as String?),
        statusDisplay: json['status_display'] as String? ?? '',
        providerReference: json['provider_reference'] as String?,
      );
}

/// What the payment-status endpoint returns: the booking and its payment,
/// both after the server has polled the provider.
class PaymentStatusResult {
  const PaymentStatusResult({
    required this.reservation,
    this.payment,
    this.detail,
  });

  final Reservation reservation;

  /// Null for a cash-on-arrival booking, which has nothing to settle.
  final Payment? payment;
  final String? detail;

  bool get isPaid => payment?.status == PaymentStatus.completed;

  factory PaymentStatusResult.fromJson(Map<String, dynamic> json) =>
      PaymentStatusResult(
        reservation:
            Reservation.fromJson(json['reservation'] as Map<String, dynamic>),
        payment: json['payment'] == null
            ? null
            : Payment.fromJson(json['payment'] as Map<String, dynamic>),
        detail: json['detail'] as String?,
      );
}

class Slot {
  const Slot({required this.start, required this.available});

  final DateTime start;
  final bool available;

  factory Slot.fromJson(Map<String, dynamic> json) => Slot(
        start: DateTime.parse(json['start'] as String).toLocal(),
        available: json['available'] as bool? ?? false,
      );
}

class SpaceAvailability {
  const SpaceAvailability({required this.space, required this.slots});

  final Space space;
  final List<Slot> slots;

  factory SpaceAvailability.fromJson(Map<String, dynamic> json) =>
      SpaceAvailability(
        space: Space.fromJson(json['space'] as Map<String, dynamic>),
        slots: (json['slots'] as List<dynamic>? ?? [])
            .map((e) => Slot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One page of a DRF `PageNumberPagination` response.
class Page<T> {
  const Page({required this.count, required this.results, this.next});

  final int count;
  final List<T> results;
  final String? next;

  factory Page.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) =>
      Page(
        count: json['count'] as int? ?? 0,
        next: json['next'] as String?,
        results: (json['results'] as List<dynamic>? ?? [])
            .map((e) => parse(e as Map<String, dynamic>))
            .toList(),
      );
}

class MerchantUser {
  const MerchantUser({
    required this.id,
    required this.username,
    required this.establishments,
    this.firstName = '',
    this.lastName = '',
    this.isSuperuser = false,
  });

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final bool isSuperuser;

  /// Venues this user may manage. Empty means they will see no bookings.
  final List<Establishment> establishments;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? username : full;
  }

  factory MerchantUser.fromJson(Map<String, dynamic> json) => MerchantUser(
        id: json['id'] as int,
        username: json['username'] as String? ?? '',
        firstName: json['first_name'] as String? ?? '',
        lastName: json['last_name'] as String? ?? '',
        isSuperuser: json['is_superuser'] as bool? ?? false,
        establishments: (json['establishments'] as List<dynamic>? ?? [])
            .map((e) => Establishment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class LoginResult {
  const LoginResult({required this.token, required this.user});

  final String token;
  final MerchantUser user;

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        token: json['token'] as String,
        user: MerchantUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
