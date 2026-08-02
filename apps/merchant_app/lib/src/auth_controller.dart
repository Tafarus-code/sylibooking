import 'package:flutter/foundation.dart';
import 'package:shared_client/shared_client.dart';

import 'token_store.dart';

enum AuthState {
  unknown,
  signedOut,

  /// Signed in, but the account has several venues and none is chosen yet.
  choosingVenue,
  signedIn,
}

/// Holds who is signed in, and keeps the token in sync with storage.
class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.tokenStore});

  final SylibookingApi api;
  final TokenStore tokenStore;

  AuthState state = AuthState.unknown;
  MerchantUser? user;
  String? errorMessage;

  /// Set when the sign-in was refused for the credentials themselves.
  /// The wording belongs to the screen, which has a BuildContext; this
  /// only says which case it was.
  bool badCredentials = false;
  bool busy = false;

  /// Venues this account may work in, with the role at each.
  List<MerchantVenue> venues = const [];

  /// The venue every screen operates on. Never null once signed in.
  MerchantVenue? selectedVenue;

  /// A switcher is worth showing only to someone with somewhere to switch to.
  bool get hasMultipleVenues => venues.length > 1;

  /// What the signed-in user may do at the selected venue.
  MerchantRole get role => selectedVenue?.role ?? MerchantRole.unknown;

  int? get selectedVenueId => selectedVenue?.id;

  /// Load the venue list and decide whether a choice is needed.
  ///
  /// One venue means no choice to make, so single-venue merchants never meet
  /// UI built for people who run several.
  Future<void> _loadVenues() async {
    venues = await api.merchantVenues();

    if (venues.isEmpty) {
      selectedVenue = null;
      state = AuthState.signedIn;
      return;
    }
    if (venues.length == 1) {
      selectedVenue = venues.first;
      state = AuthState.signedIn;
      return;
    }
    selectedVenue = null;
    state = AuthState.choosingVenue;
  }

  /// Reload the venue list and work in the one just created.
  ///
  /// The creator is made its owner server-side, so the reloaded list will
  /// contain it; selecting by id rather than trusting the response keeps the
  /// role and permissions coming from the same place as every other venue.
  ///
  /// Returns whether it is now the selected venue. False means the reload
  /// did not bring it back — the venue exists, but nothing downstream may
  /// assume there is one selected.
  Future<bool> adoptVenue(int establishmentId) async {
    await _loadVenues();
    var adopted = false;
    for (final venue in venues) {
      if (venue.id == establishmentId) {
        selectedVenue = venue;
        state = AuthState.signedIn;
        adopted = true;
        break;
      }
    }
    notifyListeners();
    return adopted;
  }

  void selectVenue(MerchantVenue venue) {
    selectedVenue = venue;
    state = AuthState.signedIn;
    notifyListeners();
  }

  /// Back to the picker, for an account that runs more than one venue.
  void changeVenue() {
    if (!hasMultipleVenues) return;
    state = AuthState.choosingVenue;
    notifyListeners();
  }

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
      await _loadVenues();
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
    badCredentials = false;
    notifyListeners();

    try {
      final result = await api.login(username.trim(), password);
      await tokenStore.write(result.token);
      user = result.user;
      await _loadVenues();
      return true;
    } on ApiException catch (e) {
      badCredentials = e.statusCode == 400;
      errorMessage = badCredentials ? null : e.message;
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
      venues = const [];
      selectedVenue = null;
      state = AuthState.signedOut;
      busy = false;
      notifyListeners();
    }
  }
}
