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
  });

  final int id;
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

  factory Reservation.fromJson(Map<String, dynamic> json) => Reservation(
        id: json['id'] as int,
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
