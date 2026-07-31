import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import '../customer_auth.dart';
import '../directions.dart';
import '../favourites_controller.dart';
import '../image_source.dart';
import '../location_source.dart';
import 'browse_screen.dart';
import 'favourites_screen.dart';
import 'my_activity_screen.dart';
import 'profile_screen.dart';

/// The four-tab shell: browse, bookings, favourites, profile.
///
/// All chrome. It is themed by the app's own ThemeData and never by an
/// establishment's preset, however many branded venues are listed inside it.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    required this.api,
    required this.store,
    required this.auth,
    required this.favourites,
    required this.imageSource,
    required this.locationSource,
    required this.directionsLauncher,
  });

  final SylibookingApi api;
  final BookingStore store;
  final CustomerAuth auth;
  final FavouritesController favourites;
  final ImageSource imageSource;
  final LocationSource locationSource;
  final DirectionsLauncher directionsLauncher;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.auth.restore();
    widget.favourites.load();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: const [
        AdaptiveDestination(
          label: 'Browse',
          icon: Icons.search,
          selectedIcon: Icons.search,
        ),
        AdaptiveDestination(
          label: 'Bookings',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
        ),
        AdaptiveDestination(
          label: 'Favourites',
          icon: Icons.favorite_border,
          selectedIcon: Icons.favorite,
        ),
        AdaptiveDestination(
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
        ),
      ],
      // IndexedStack: switching tabs should not re-fetch the list or lose the
      // customer's place in it.
      body: IndexedStack(
        index: _index,
        children: [
          BrowseScreen(
            api: widget.api,
            store: widget.store,
            favourites: widget.favourites,
            imageSource: widget.imageSource,
            locationSource: widget.locationSource,
            directionsLauncher: widget.directionsLauncher,
          ),
          MyActivityScreen(
            api: widget.api,
            store: widget.store,
            auth: widget.auth,
            imageSource: widget.imageSource,
          ),
          ListenableBuilder(
            listenable: widget.auth,
            builder: (context, _) => FavouritesScreen(
              api: widget.api,
              store: widget.store,
              favourites: widget.favourites,
              directionsLauncher: widget.directionsLauncher,
              signedIn: widget.auth.isSignedIn,
            ),
          ),
          ProfileScreen(auth: widget.auth),
        ],
      ),
    );
  }
}
