import 'package:flutter/foundation.dart';
import 'package:shared_client/shared_client.dart';

import 'booking_store.dart';
import 'customer_auth.dart';

/// Venues the customer has saved.
///
/// Always written to the device, and also to the account when there is one.
/// That order matters: tapping the heart has to work instantly and offline,
/// so the local set is the truth the UI reads and the server is a copy that
/// catches up.
class FavouritesController extends ChangeNotifier {
  FavouritesController({
    required this.api,
    required this.store,
    required this.auth,
  }) {
    auth.addListener(_onAuthChanged);
  }

  final SylibookingApi api;
  final BookingStore store;
  final CustomerAuth auth;

  Set<int> _ids = {};
  bool _loaded = false;

  Set<int> get ids => Set.unmodifiable(_ids);
  bool get isEmpty => _ids.isEmpty;

  bool contains(int establishmentId) => _ids.contains(establishmentId);

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> load() async {
    // A copy, not the store's own set: stores hand back unmodifiable views,
    // and this controller mutates its set on every tap.
    _ids = {...await store.favouriteIds()};
    _loaded = true;
    notifyListeners();

    // Signed in, the account is the fuller list — it has whatever was saved
    // on another phone.
    if (auth.isSignedIn) await _pullFromAccount();
  }

  void _onAuthChanged() {
    if (auth.isSignedIn && _loaded) _pullFromAccount();
  }

  Future<void> _pullFromAccount() async {
    try {
      final saved = await api.favourites();
      final merged = {..._ids, ...saved.map((e) => e.id)};
      for (final id in merged.difference(_ids)) {
        await store.setFavourite(id, saved: true);
      }
      _ids = merged;
      notifyListeners();
    } on ApiException {
      // The local list still stands; nothing is lost.
    } on ApiUnreachableException {
      // As above.
    }
  }

  /// Save or unsave, locally first so the heart fills the moment it is tapped.
  Future<void> toggle(int establishmentId) async {
    final saved = !_ids.contains(establishmentId);
    if (saved) {
      _ids.add(establishmentId);
    } else {
      _ids.remove(establishmentId);
    }
    notifyListeners();

    await store.setFavourite(establishmentId, saved: saved);
    if (!auth.isSignedIn) return;

    try {
      if (saved) {
        await api.addFavourites([establishmentId]);
      } else {
        await api.removeFavourite(establishmentId);
      }
    } on ApiException {
      // The device is still right, and the next sign-in merges it up.
    } on ApiUnreachableException {
      // As above.
    }
  }
}
