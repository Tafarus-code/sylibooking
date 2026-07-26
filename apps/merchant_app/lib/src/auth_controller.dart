import 'package:flutter/foundation.dart';
import 'package:shared_client/shared_client.dart';

import 'token_store.dart';

enum AuthState { unknown, signedOut, signedIn }

/// Holds who is signed in, and keeps the token in sync with storage.
class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.tokenStore});

  final SylibookingApi api;
  final TokenStore tokenStore;

  AuthState state = AuthState.unknown;
  MerchantUser? user;
  String? errorMessage;
  bool busy = false;

  /// Called on launch: reuse a stored token if the server still accepts it.
  Future<void> restore() async {
    final stored = await tokenStore.read();
    if (stored == null || stored.isEmpty) {
      state = AuthState.signedOut;
      notifyListeners();
      return;
    }

    api.token = stored;
    try {
      user = await api.me();
      state = AuthState.signedIn;
    } on ApiException catch (e) {
      // A rejected token means the session is over; anything else (a 500, say)
      // should not silently sign the merchant out mid-service.
      if (e.isUnauthorized) {
        await tokenStore.clear();
        api.token = null;
        state = AuthState.signedOut;
      } else {
        errorMessage = e.message;
        state = AuthState.signedOut;
      }
    } on ApiUnreachableException catch (e) {
      errorMessage = e.message;
      state = AuthState.signedOut;
    }
    notifyListeners();
  }

  Future<bool> signIn(String username, String password) async {
    busy = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await api.login(username.trim(), password);
      await tokenStore.write(result.token);
      user = result.user;
      state = AuthState.signedIn;
      return true;
    } on ApiException catch (e) {
      errorMessage = e.statusCode == 400
          ? 'Wrong username or password.'
          : e.message;
      return false;
    } on ApiUnreachableException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    busy = true;
    notifyListeners();
    try {
      await api.logout();
    } on ApiUnreachableException {
      // Sign out locally regardless — the merchant asked to be signed out.
    } finally {
      await tokenStore.clear();
      api.token = null;
      user = null;
      state = AuthState.signedOut;
      busy = false;
      notifyListeners();
    }
  }
}
