import 'package:shared_preferences/shared_preferences.dart';

/// Where the auth token is kept between launches.
///
/// An interface so widget tests can run without platform channels.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SharedPreferencesTokenStore implements TokenStore {
  static const _key = 'sylibooking.merchant.token';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> write(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, token);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Used in tests, and as a fallback if storage is unavailable.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
