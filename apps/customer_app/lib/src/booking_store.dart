import 'package:shared_preferences/shared_preferences.dart';

/// Remembers what this device booked, and who it booked as.
///
/// Customers have no account in the MVP — a reservation is just a name and a
/// phone number. So the app keeps the ids it created locally and re-reads them
/// from the public detail endpoint. Clearing app data loses the list; the
/// booking itself still stands at the venue.
abstract class BookingStore {
  Future<List<String>> bookingReferences();
  Future<void> remember(String reference);

  /// Orders are kept the same way and for the same reason: no account, so the
  /// reference on this device is the only way back to them.
  Future<List<String>> orderReferences();
  Future<void> rememberOrder(String reference);

  /// Prefill for the next booking, so a returning customer types once.
  Future<({String name, String phone})?> lastCustomer();
  Future<void> rememberCustomer(String name, String phone);
}

class SharedPreferencesBookingStore implements BookingStore {
  // Deliberately a new key: the old one held sequential ids, which the API no
  // longer accepts from customers. Anything stored under it is unusable, so it
  // is left behind rather than migrated.
  static const _referencesKey = 'sylibooking.customer.booking_refs';
  static const _orderReferencesKey = 'sylibooking.customer.order_refs';
  static const _nameKey = 'sylibooking.customer.name';
  static const _phoneKey = 'sylibooking.customer.phone';

  @override
  Future<List<String>> bookingReferences() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_referencesKey) ?? [];
  }

  @override
  Future<void> remember(String reference) async {
    if (reference.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_referencesKey) ?? [];
    if (existing.contains(reference)) return;
    await prefs.setStringList(_referencesKey, [...existing, reference]);
  }

  @override
  Future<List<String>> orderReferences() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_orderReferencesKey) ?? [];
  }

  @override
  Future<void> rememberOrder(String reference) async {
    if (reference.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_orderReferencesKey) ?? [];
    if (existing.contains(reference)) return;
    await prefs.setStringList(_orderReferencesKey, [...existing, reference]);
  }

  @override
  Future<({String name, String phone})?> lastCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_nameKey);
    final phone = prefs.getString(_phoneKey);
    if (name == null || phone == null) return null;
    return (name: name, phone: phone);
  }

  @override
  Future<void> rememberCustomer(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
    await prefs.setString(_phoneKey, phone);
  }
}

/// Used in widget tests, which have no platform channels.
class InMemoryBookingStore implements BookingStore {
  InMemoryBookingStore({
    List<String>? references,
    List<String>? orders,
    this.customer,
  })  : _references = [...?references],
        _orders = [...?orders];

  final List<String> _references;
  final List<String> _orders;
  ({String name, String phone})? customer;

  @override
  Future<List<String>> bookingReferences() async =>
      List.unmodifiable(_references);

  @override
  Future<void> remember(String reference) async {
    if (reference.isEmpty) return;
    if (!_references.contains(reference)) _references.add(reference);
  }

  @override
  Future<List<String>> orderReferences() async => List.unmodifiable(_orders);

  @override
  Future<void> rememberOrder(String reference) async {
    if (reference.isEmpty) return;
    if (!_orders.contains(reference)) _orders.add(reference);
  }

  @override
  Future<({String name, String phone})?> lastCustomer() async => customer;

  @override
  Future<void> rememberCustomer(String name, String phone) async {
    customer = (name: name, phone: phone);
  }
}
