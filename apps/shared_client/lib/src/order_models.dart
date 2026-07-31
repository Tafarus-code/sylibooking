import 'models.dart';

/// Where an order has got to in the kitchen.
enum OrderStatus {
  placed,
  preparing,
  ready,
  completed,
  cancelled,
  unknown;

  static OrderStatus parse(String? value) => switch (value) {
        'placed' => OrderStatus.placed,
        'preparing' => OrderStatus.preparing,
        'ready' => OrderStatus.ready,
        'completed' => OrderStatus.completed,
        'cancelled' => OrderStatus.cancelled,
        _ => OrderStatus.unknown,
      };

  String get wireValue => switch (this) {
        OrderStatus.placed => 'placed',
        OrderStatus.preparing => 'preparing',
        OrderStatus.ready => 'ready',
        OrderStatus.completed => 'completed',
        OrderStatus.cancelled => 'cancelled',
        OrderStatus.unknown => '',
      };

  /// Still moving through the kitchen, as opposed to finished either way.
  bool get isOpen =>
      this == OrderStatus.placed ||
      this == OrderStatus.preparing ||
      this == OrderStatus.ready;
}

/// One line of an order, at the price it cost when it was placed.
class OrderLine {
  const OrderLine({
    required this.id,
    required this.menuItemId,
    required this.menuItemName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final int id;
  final int menuItemId;
  final String menuItemName;
  final int quantity;

  /// Snapshotted by the server. Never the live menu price.
  final String unitPrice;
  final String lineTotal;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        id: json['id'] as int,
        menuItemId: json['menu_item'] as int? ?? 0,
        menuItemName: json['menu_item_name'] as String? ?? '',
        quantity: json['quantity'] as int? ?? 0,
        unitPrice: '${json['unit_price_at_order'] ?? ''}',
        lineTotal: '${json['line_total'] ?? ''}',
      );
}

/// Food ordered ahead and collected at the counter.
class Order {
  const Order({
    required this.id,
    required this.reference,
    required this.establishmentId,
    required this.establishmentName,
    required this.customerName,
    required this.customerPhone,
    required this.pickupTime,
    required this.status,
    required this.statusDisplay,
    required this.items,
    required this.total,
    required this.isPaid,
    required this.canAdvance,
    this.reservationId,
    this.paymentProvider,
    this.paymentProviderDisplay = '',
    this.paymentStatus,
    this.nextStatus = OrderStatus.unknown,
  });

  final int id;

  /// How a customer with no account proves the order is theirs.
  final String reference;
  final int establishmentId;
  final String establishmentName;

  /// Set when the order is tied to a table booking; null for a plain pickup.
  final int? reservationId;
  final String customerName;
  final String customerPhone;
  final DateTime pickupTime;
  final OrderStatus status;
  final String statusDisplay;
  final List<OrderLine> items;
  final String total;
  final PaymentProvider? paymentProvider;
  final String paymentProviderDisplay;
  final PaymentStatus? paymentStatus;
  final bool isPaid;

  /// What the server would allow right now, so the app can grey a button out
  /// for the same reason the API would refuse it.
  final bool canAdvance;
  final OrderStatus nextStatus;

  bool get isForATable => reservationId != null;

  /// True when the money has to arrive before the kitchen may start.
  bool get isAwaitingPayment =>
      paymentProvider != null &&
      paymentProvider != PaymentProvider.cashOnArrival &&
      !isPaid;

  int get itemCount =>
      items.fold(0, (running, item) => running + item.quantity);

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as int,
        reference: '${json['reference'] ?? ''}',
        establishmentId: json['establishment'] as int? ?? 0,
        establishmentName: json['establishment_name'] as String? ?? '',
        reservationId: json['reservation'] as int?,
        customerName: json['customer_name'] as String? ?? '',
        customerPhone: json['customer_phone'] as String? ?? '',
        pickupTime:
            DateTime.parse(json['pickup_time'] as String).toLocal(),
        status: OrderStatus.parse(json['status'] as String?),
        statusDisplay: json['status_display'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: '${json['total'] ?? ''}',
        paymentProvider: json['payment_provider'] == null
            ? null
            : PaymentProvider.parse(json['payment_provider'] as String?),
        paymentProviderDisplay:
            json['payment_provider_display'] as String? ?? '',
        paymentStatus: json['payment_status'] == null
            ? null
            : PaymentStatus.parse(json['payment_status'] as String?),
        isPaid: json['is_paid'] as bool? ?? false,
        canAdvance: json['can_advance'] as bool? ?? false,
        nextStatus: OrderStatus.parse(json['next_status'] as String?),
      );
}

/// A dish and how many of it, on its way to the server.
///
/// Carries no price: what a dish costs is the menu's to say, and the server
/// snapshots it. A cart that could name its own prices would be a shop where
/// customers write their own receipts.
class CartLine {
  const CartLine({required this.menuItemId, required this.quantity});

  final int menuItemId;
  final int quantity;

  Map<String, dynamic> toJson() => {
        'menu_item': menuItemId,
        'quantity': quantity,
      };
}
