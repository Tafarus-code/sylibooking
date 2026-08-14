import 'package:flutter/foundation.dart';
import 'package:shared_client/shared_client.dart';

import 'booking_store.dart';

/// Where a customer stands with the optional account.
enum CustomerAuthState { unknown, signedOut, signedIn }

/// Signing in, and what follows from it.
///
/// The app has always worked without an account and still does. This
/// controller exists so that *choosing* to have one is worth something: the
/// history stops being tied to one handset, and the favourites follow the
/// person.
class CustomerAuth extends ChangeNotifier {
  CustomerAuth({
    required this.api,
    required this.store,
    required this.tokenStore,
  });

  final SylibookingApi api;
  final BookingStore store;
  final CustomerTokenStore tokenStore;

  CustomerAuthState _state = CustomerAuthState.unknown;
  CustomerAccount? _customer;
  bool _busy = false;
  String? _error;

  CustomerAuthState get state => _state;
  CustomerAccount? get customer => _customer;
  bool get busy => _busy;
  String? get error => _error;
  bool get isSignedIn => _state == CustomerAuthState.signedIn;

  /// Called on start. A stored token that no longer works is discarded
  /// quietly — being silently signed out beats an error on a splash screen.
  Future<void> restore() async {
    final token = await tokenStore.read();
    if (token == null || token.isEmpty) {
      _set(CustomerAuthState.signedOut);
      return;
    }

    api.token = token;
    try {
      _customer = await api.customerMe();
      _set(CustomerAuthState.signedIn);
    } on ApiException {
      await tokenStore.clear();
      api.token = null;
      _set(CustomerAuthState.signedOut);
    } on ApiUnreachableException {
      // Offline at start is not signed out: keep the token and let the next
      // call decide, rather than throwing the account away over one timeout.
      _set(CustomerAuthState.signedIn);
    }
  }

  Future<bool> register({
    required String username,
    required String password,
    required String name,
    String phone = '',
    String email = '',
  }) =>
      _authenticate(
        () => api.registerCustomer(
          username: username,
          password: password,
          name: name,
          phone: phone,
          email: email,
        ),
      );

  Future<bool> signIn({
    required String username,
    required String password,
  }) =>
      _authenticate(
        () => api.signInCustomer(username: username, password: password),
      );

  Future<bool> _authenticate(Future<CustomerSession> Function() call) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final session = await call();
      await tokenStore.write(session.token);
      _customer = session.customer;
      _busy = false;
      _set(CustomerAuthState.signedIn);

      // Everything this phone did before the account existed now belongs to
      // it. Best effort: a failure here must not turn a successful sign-in
      // into an error message.
      await _adoptWhatIsOnThisPhone();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
    } on ApiUnreachableException catch (e) {
      _error = e.message;
    }

    _busy = false;
    api.token = null;
    notifyListeners();
    return false;
  }

  Future<void> _adoptWhatIsOnThisPhone() async {
    try {
      await api.claim(
        reservationReferences: await store.bookingReferences(),
        orderReferences: await store.orderReferences(),
      );
      final local = await store.favouriteIds();
      if (local.isNotEmpty) await api.addFavourites(local.toList());
    } on ApiException {
      // Nothing was lost: the references are still on the phone and the
      // next sign-in will try again.
    } on ApiUnreachableException {
      // As above.
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.logout();
    } on ApiException {
      // A dead token is a successful sign-out as far as the app cares.
    } on ApiUnreachableException {
      // As above — the local state is what the customer sees.
    }
    await tokenStore.clear();
    api.token = null;
    _customer = null;
    // The device keeps its own favourites and references, so signing out
    // leaves someone where they would have been without an account, not
    // empty-handed.
    _set(CustomerAuthState.signedOut);
  }

  /// Update the details this account carries.
  ///
  /// Returns null on success, or a message to show.
  Future<String?> updateProfile({
    String? name,
    String? phone,
    String? email,
  }) async {
    try {
      _customer = await api.updateCustomerProfile(
        name: name,
        phone: phone,
        email: email,
      );
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on ApiUnreachableException catch (e) {
      return e.message;
    }
  }

  /// Close the account for good, then leave this phone signed out.
  ///
  /// The local bookings and favourites on the device are deliberately kept:
  /// closing an account is not the same as wiping the phone, and someone who
  /// closes theirs is exactly back where an account-less customer already is.
  Future<String?> closeAccount({required String password}) async {
    try {
      await api.closeCustomerAccount(password: password);
    } on ApiException catch (e) {
      return e.message;
    } on ApiUnreachableException catch (e) {
      return e.message;
    }

    await tokenStore.clear();
    api.token = null;
    _customer = null;
    _set(CustomerAuthState.signedOut);
    return null;
  }

  void _set(CustomerAuthState state) {
    _state = state;
    notifyListeners();
  }
}
