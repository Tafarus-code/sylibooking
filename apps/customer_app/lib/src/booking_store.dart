import 'package:shared_preferences/shared_preferences.dart';

/// Remembers what this device booked, and who it booked as.
///
/// Customers have no account in the MVP — a reservation is just a name and a
/// phone number. So the app keeps the ids it created locally and re-reads them
/// from the public detail endpoint. Clearing app data loses the list; the
/// booking itself still stands at the venue.
abstract class BookingStore {
  Future<List<int>> bookingIds();
  Future<void> remember(int id);

  /// Prefill for the next booking, so a returning customer types once.
  Future<({String name, String phone})?> lastCustomer();
  Future<void> rememberCustomer(String name, String phone);
}

class SharedPreferencesBookingStore implements BookingStore {
  static const _idsKey = 'sylibooking.customer.bookings';
  static const _nameKey = 'sylibooking.customer.name';
  static const _phoneKey = 'sylibooking.customer.phone';

  @override
  Future<List<int>> bookingIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_idsKey) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .toList();
  }

  @override
  Future<void> remember(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_idsKey) ?? [];
    if (existing.contains('$id')) return;
    await prefs.setStringList(_idsKey, [...existing, '$id']);
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
  InMemoryBookingStore({List<int>? ids, this.customer}) : _ids = [...?ids];

  final List<int> _ids;
  ({String name, String phone})? customer;

  @override
  Future<List<int>> bookingIds() async => List.unmodifiable(_ids);

  @override
  Future<void> remember(int id) async {
    if (!_ids.contains(id)) _ids.add(id);
  }

  @override
  Future<({String name, String phone})?> lastCustomer() async => customer;

  @override
  Future<void> rememberCustomer(String name, String phone) async {
    customer = (name: name, phone: phone);
  }
}
