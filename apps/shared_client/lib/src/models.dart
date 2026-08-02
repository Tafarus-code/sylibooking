/// Dart mirrors of the DRF serializers in `backend/api/serializers.py`.
///
/// Every model parses from JSON only — the apps never construct these to send
/// back, they send plain maps, so there is no `toJson` to drift out of sync.
library;

import 'establishment_theme.dart';
import 'geo.dart';

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
    this.isActive = true,
  });

  final int id;
  final String name;
  final SpaceType type;
  final String typeDisplay;
  final int capacity;

  /// Whether the space can still be booked.
  ///
  /// Only the merchant list carries this. The customer payload omits retired
  /// spaces entirely rather than sending them flagged, so anything a customer
  /// is shown is bookable by construction — hence the default.
  final bool isActive;

  factory Space.fromJson(Map<String, dynamic> json) => Space(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        type: SpaceType.parse(json['type'] as String?),
        typeDisplay: json['type_display'] as String? ?? '',
        capacity: json['capacity'] as int? ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );
}

/// One weekday's opening hours.
class OpeningHours {
  const OpeningHours({
    required this.dayOfWeek,
    required this.dayDisplay,
    required this.isClosed,
    this.opens,
    this.closes,
    this.runsPastMidnight = false,
  });

  /// 0 is Monday, matching `DateTime.weekday - 1`.
  final int dayOfWeek;
  final String dayDisplay;
  final bool isClosed;

  /// `HH:MM` as sent by the API; null when closed.
  final String? opens;
  final String? closes;

  /// True when this interval runs into the following day, e.g. 18:00-02:00.
  final bool runsPastMidnight;

  /// "18:00 – 02:00", or "Closed".
  String get range {
    if (isClosed || opens == null || closes == null) return 'Closed';
    return '${_hhmm(opens!)} – ${_hhmm(closes!)}';
  }

  factory OpeningHours.fromJson(Map<String, dynamic> json) => OpeningHours(
        dayOfWeek: json['day_of_week'] as int? ?? 0,
        dayDisplay: json['day_display'] as String? ?? '',
        isClosed: json['is_closed'] as bool? ?? true,
        opens: json['opens'] as String?,
        closes: json['closes'] as String?,
        runsPastMidnight: json['runs_past_midnight'] as bool? ?? false,
      );
}

double? _toDouble(Object? value) => switch (value) {
      null => null,
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

/// Django sends times as `HH:MM:SS`; nobody wants to read the seconds.
String _hhmm(String value) =>
    value.length >= 5 ? value.substring(0, 5) : value;

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    this.description = '',
    this.imageUrl,
  });

  final int id;
  final String name;
  final String description;

  /// Guinean francs.
  final String price;

  /// Null for most items; a picture is optional.
  final String? imageUrl;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: '${json['price'] ?? ''}',
        imageUrl: json['image'] as String?,
      );
}

/// A menu category with its available items.
///
/// The API omits categories that have nothing available, so a group here
/// always has at least one item — the app never has to guard against an empty
/// section.
class MenuCategory {
  const MenuCategory({
    required this.category,
    required this.categoryDisplay,
    required this.items,
  });

  final String category;
  final String categoryDisplay;
  final List<MenuItem> items;

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
        category: json['category'] as String? ?? '',
        categoryDisplay: json['category_display'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A user's standing at one establishment.
enum MerchantRole {
  owner,
  manager,
  staff,
  unknown;

  static MerchantRole parse(String? value) => switch (value) {
        'owner' => MerchantRole.owner,
        'manager' => MerchantRole.manager,
        'staff' => MerchantRole.staff,
        _ => MerchantRole.unknown,
      };

  /// Editing the venue: hours, menu, photos, description.
  bool get canEditProfile =>
      this == MerchantRole.owner || this == MerchantRole.manager;

  /// Adding, removing or re-roling members. Owner alone.
  bool get canManageStaff => this == MerchantRole.owner;

  /// Marking a dish sold out — the one thing staff may change on the menu.
  bool get canToggleMenuAvailability => this != MerchantRole.unknown;
}

/// An establishment as it appears in the merchant's own venue list.
class MerchantVenue {
  const MerchantVenue({
    required this.id,
    required this.name,
    required this.city,
    required this.role,
    required this.roleDisplay,
    this.type = '',
    this.tagline = '',
    this.themePreset = defaultThemePresetKey,
  });

  final int id;
  final String name;
  final String city;
  final String type;
  final String tagline;

  /// The venue's chosen branding, so its own screens in the merchant app can
  /// be themed the way a customer sees them.
  final String themePreset;

  /// What this user may do here. The server enforces the same rules; this is
  /// only so the app does not offer a control that would be refused.
  final MerchantRole role;
  final String roleDisplay;

  factory MerchantVenue.fromJson(Map<String, dynamic> json) => MerchantVenue(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        city: json['city'] as String? ?? '',
        type: json['type'] as String? ?? '',
        tagline: json['tagline'] as String? ?? '',
        themePreset:
            json['theme_preset'] as String? ?? defaultThemePresetKey,
        role: MerchantRole.parse(json['role'] as String?),
        roleDisplay: json['role_display'] as String? ?? '',
      );
}

/// A menu item as the merchant sees it — unavailable ones included.
class MerchantMenuItem {
  const MerchantMenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.isAvailable,
    this.description = '',
    this.imageUrl,
  });

  final int id;
  final String name;
  final String description;

  /// `food`, `drink` or `chicha_flavor`.
  final String category;
  final String price;
  final bool isAvailable;

  /// Null for most items — a picture is optional.
  final String? imageUrl;

  String get categoryDisplay => switch (category) {
        'food' => 'Food',
        'drink' => 'Drink',
        'chicha_flavor' => 'Chicha flavour',
        _ => category,
      };

  MerchantMenuItem copyWith({bool? isAvailable}) => MerchantMenuItem(
        id: id,
        name: name,
        description: description,
        category: category,
        price: price,
        isAvailable: isAvailable ?? this.isAvailable,
        imageUrl: imageUrl,
      );

  factory MerchantMenuItem.fromJson(Map<String, dynamic> json) =>
      MerchantMenuItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? '',
        price: '${json['price'] ?? ''}',
        isAvailable: json['is_available'] as bool? ?? true,
        imageUrl: json['image_url'] as String?,
      );
}

/// Someone's membership of a venue, as shown on the staff screen.
class Membership {
  const Membership({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
    required this.roleDisplay,
  });

  final int id;
  final int userId;
  final String username;
  final String fullName;
  final MerchantRole role;
  final String roleDisplay;

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
        id: json['id'] as int,
        userId: json['user'] as int? ?? 0,
        username: json['username'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        role: MerchantRole.parse(json['role'] as String?),
        roleDisplay: json['role_display'] as String? ?? '',
      );
}

class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.author,
    required this.createdAt,
    this.comment = '',
  });

  final int id;
  final int rating;
  final String comment;

  /// First name only — the API deliberately publishes no more than that.
  final String author;
  final DateTime createdAt;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as int,
        rating: json['rating'] as int? ?? 0,
        comment: json['comment'] as String? ?? '',
        author: json['author'] as String? ?? 'Guest',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class Photo {
  const Photo({
    required this.id,
    required this.imageUrl,
    required this.uploadedByRole,
    required this.uploadedByRoleDisplay,
    this.caption = '',
  });

  final int id;
  final String imageUrl;

  /// `customer` or `merchant` — a venue's own photo is not a guest snapshot.
  final String uploadedByRole;
  final String uploadedByRoleDisplay;
  final String caption;

  bool get isFromMerchant => uploadedByRole == 'merchant';

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
        id: json['id'] as int,
        imageUrl: json['image'] as String? ?? '',
        uploadedByRole: json['uploaded_by_role'] as String? ?? '',
        uploadedByRoleDisplay:
            json['uploaded_by_role_display'] as String? ?? '',
        caption: json['caption'] as String? ?? '',
      );
}

/// One provider's line on the merchant dashboard.
class ProviderTotals {
  const ProviderTotals({
    required this.provider,
    required this.providerDisplay,
    required this.bookings,
    required this.collected,
    required this.awaiting,
  });

  final String provider;
  final String providerDisplay;
  final int bookings;
  final String collected;
  final String awaiting;

  factory ProviderTotals.fromJson(Map<String, dynamic> json) => ProviderTotals(
        provider: json['provider'] as String? ?? '',
        providerDisplay: json['provider_display'] as String? ?? '',
        bookings: json['bookings'] as int? ?? 0,
        collected: '${json['collected'] ?? '0.00'}',
        awaiting: '${json['awaiting'] ?? '0.00'}',
      );
}

/// A booking whose money has not arrived and whose date has not passed.
class AttentionItem {
  const AttentionItem({
    required this.reservationId,
    required this.customerName,
    required this.dateTime,
    required this.spaceName,
    required this.establishmentName,
    required this.paymentProviderDisplay,
    this.paymentStatus,
  });

  final int reservationId;
  final String customerName;
  final DateTime dateTime;
  final String spaceName;
  final String establishmentName;
  final String paymentProviderDisplay;
  final PaymentStatus? paymentStatus;

  factory AttentionItem.fromJson(Map<String, dynamic> json) => AttentionItem(
        reservationId: json['id'] as int,
        customerName: json['customer_name'] as String? ?? '',
        dateTime: DateTime.parse(json['datetime'] as String).toLocal(),
        spaceName: json['space_name'] as String? ?? '',
        establishmentName: json['establishment_name'] as String? ?? '',
        paymentProviderDisplay:
            json['payment_provider_display'] as String? ?? '',
        paymentStatus: json['payment_status'] == null
            ? null
            : PaymentStatus.parse(json['payment_status'] as String?),
      );
}

/// What the merchant took, what is still owed, and what to chase.
class PaymentDashboard {
  const PaymentDashboard({
    required this.from,
    required this.to,
    required this.collected,
    required this.awaiting,
    required this.failed,
    required this.completedCount,
    required this.pendingCount,
    required this.failedCount,
    required this.reservationCounts,
    required this.byProvider,
    required this.needsAttention,
  });

  final DateTime from;
  final DateTime to;

  /// Amounts as strings: nothing on the client rounds money.
  final String collected;
  final String awaiting;
  final String failed;

  final int completedCount;
  final int pendingCount;
  final int failedCount;

  /// Keyed by reservation status, plus `total`.
  final Map<String, int> reservationCounts;
  final List<ProviderTotals> byProvider;
  final List<AttentionItem> needsAttention;

  int get totalReservations => reservationCounts['total'] ?? 0;

  factory PaymentDashboard.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? {};
    final payments = json['payments'] as Map<String, dynamic>? ?? {};
    final reservations = json['reservations'] as Map<String, dynamic>? ?? {};

    return PaymentDashboard(
      from: DateTime.parse(period['from'] as String),
      to: DateTime.parse(period['to'] as String),
      collected: '${payments['collected'] ?? '0.00'}',
      awaiting: '${payments['awaiting'] ?? '0.00'}',
      failed: '${payments['failed'] ?? '0.00'}',
      completedCount: payments['completed_count'] as int? ?? 0,
      pendingCount: payments['pending_count'] as int? ?? 0,
      failedCount: payments['failed_count'] as int? ?? 0,
      reservationCounts: {
        for (final entry in reservations.entries)
          if (entry.value is int) entry.key: entry.value as int,
      },
      byProvider: (json['by_provider'] as List<dynamic>? ?? [])
          .map((e) => ProviderTotals.fromJson(e as Map<String, dynamic>))
          .toList(),
      needsAttention: (json['needs_attention'] as List<dynamic>? ?? [])
          .map((e) => AttentionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
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
    this.isOpenNow = false,
    this.closesAt,
    this.today,
    this.hours = const [],
    this.menu = const [],
    this.averageRating,
    this.reviewCount = 0,
    this.tagline = '',
    this.description = '',
    this.latitude,
    this.longitude,
    this.themePreset = 'ember',
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

  /// Computed server-side, so both apps agree and the overnight arithmetic
  /// lives in one place. Present on list and detail.
  final bool isOpenNow;

  /// When the interval in progress ends, e.g. `02:00:00`. Null when closed.
  final String? closesAt;

  /// The current day's hours. Null when the merchant never set that day.
  final OpeningHours? today;

  /// All seven days, detail only. Empty when the API did not send them.
  final List<OpeningHours> hours;

  /// Available items by category, detail only. Categories with nothing
  /// available are already omitted by the API.
  final List<MenuCategory> menu;

  /// Mean of visible ratings, or null when nobody has reviewed yet. Computed
  /// server-side so hidden reviews never count.
  final double? averageRating;
  final int reviewCount;

  bool get hasReviews => reviewCount > 0;

  /// One-line hook and a longer blurb, both merchant-editable.
  final String tagline;
  final String description;

  /// Null for venues whose coordinates were never recorded, which is most of
  /// them at first — nothing may assume a position exists.
  final double? latitude;
  final double? longitude;

  /// Which curated branding preset this venue uses. Only the key travels;
  /// the colours and fonts live in the shared design file.
  final String themePreset;

  bool get hasMenu => menu.isNotEmpty;
  bool get hasHours => hours.isNotEmpty;

  /// Many venues have no coordinates recorded, so distance is never assumed.
  LatLng? get position {
    final lat = latitude;
    final lon = longitude;
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  bool get hasPosition => position != null;

  /// "Open until 02:00", "Closed today", or "Hours not listed".
  /// Just the closing time, "02:00", with no words around it.
  ///
  /// The words are the app's to choose and to translate; this package should
  /// not be shipping English copy to two apps in two languages.
  String get closesAtDisplay => closesAt == null ? '' : _hhmm(closesAt!);

  String get openSummary {
    if (isOpenNow) {
      final until = closesAt == null ? null : _hhmm(closesAt!);
      return until == null ? 'Open now' : 'Open until $until';
    }
    if (today == null) return 'Hours not listed';
    if (today!.isClosed) return 'Closed today';
    final opensAt = today!.opens;
    return opensAt == null ? 'Closed now' : 'Closed · opens ${_hhmm(opensAt)}';
  }

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
        isOpenNow: json['is_open_now'] as bool? ?? false,
        closesAt: json['closes_at'] as String?,
        today: json['today'] == null
            ? null
            : OpeningHours.fromJson(json['today'] as Map<String, dynamic>),
        hours: (json['hours'] as List<dynamic>? ?? [])
            .map((e) => OpeningHours.fromJson(e as Map<String, dynamic>))
            .toList(),
        menu: (json['menu'] as List<dynamic>? ?? [])
            .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
        averageRating: (json['average_rating'] as num?)?.toDouble(),
        reviewCount: json['review_count'] as int? ?? 0,
        tagline: json['tagline'] as String? ?? '',
        description: json['description'] as String? ?? '',
        // DRF serialises DecimalField as a string, so accept either.
        latitude: _toDouble(json['latitude']),
        longitude: _toDouble(json['longitude']),
        themePreset: json['theme_preset'] as String? ?? 'ember',
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
    this.canConfirm = false,
    this.paymentProvider = PaymentProvider.cashOnArrival,
    this.paymentProviderDisplay = '',
    this.paymentStatus,
    this.isPaid = false,
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

  /// Whether the merchant may confirm this now. The server enforces the same
  /// rule, so a client that ignores this gets a 409.
  final bool canConfirm;

  /// How the booking is being paid, cash included.
  final PaymentProvider paymentProvider;
  final String paymentProviderDisplay;

  /// Null when there is nothing to settle — that is, cash on arrival.
  final PaymentStatus? paymentStatus;

  final bool isPaid;

  /// The most recent payment, or null for a cash-on-arrival booking.
  final Payment? payment;

  /// True when money is owed through a provider and has not arrived.
  ///
  /// The distinction that matters on a merchant's screen: an unpaid mobile
  /// money booking is not the same as a cash booking, even though neither has
  /// been paid yet.
  bool get isAwaitingPayment =>
      paymentProvider.isMobileMoney && !isPaid;

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
        canConfirm: json['can_confirm'] as bool? ?? false,
        paymentProvider: PaymentProvider.parse(
          json['payment_provider'] as String?,
        ),
        paymentProviderDisplay:
            json['payment_provider_display'] as String? ?? '',
        paymentStatus: json['payment_status'] == null
            ? null
            : PaymentStatus.parse(json['payment_status'] as String?),
        isPaid: json['is_paid'] as bool? ?? false,
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
