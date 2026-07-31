import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import 'booking_store.dart';
import 'customer_auth.dart';
import 'directions.dart';
import 'favourites_controller.dart';
import 'image_source.dart';
import 'location_source.dart';
import 'screens/customer_home_screen.dart';

class CustomerApp extends StatefulWidget {
  const CustomerApp({
    super.key,
    required this.api,
    required this.store,
    this.tokenStore,
    this.imageSource,
    this.locationSource,
    this.directionsLauncher,
  });

  final SylibookingApi api;
  final BookingStore store;

  /// Injected so widget tests can drive these without a platform channel.
  final CustomerTokenStore? tokenStore;
  final ImageSource? imageSource;
  final LocationSource? locationSource;
  final DirectionsLauncher? directionsLauncher;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  late final CustomerAuth _auth;
  late final FavouritesController _favourites;

  @override
  void initState() {
    super.initState();
    // Built here rather than in the shell so they outlive a rebuild: the
    // account and the saved list are app state, not screen state.
    _auth = CustomerAuth(
      api: widget.api,
      store: widget.store,
      tokenStore: widget.tokenStore ?? SharedPreferencesCustomerTokenStore(),
    );
    _favourites = FavouritesController(
      api: widget.api,
      store: widget.store,
      auth: _auth,
    );
  }

  @override
  void dispose() {
    _favourites.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sylibooking',
      debugShowCheckedModeBanner: false,
      // The app's own look. Establishment branding is layered on top of this
      // by EstablishmentThemeScope, and only on a venue's own screens.
      theme: sylibookingAppTheme(),
      home: CustomerHomeScreen(
        api: widget.api,
        store: widget.store,
        auth: _auth,
        favourites: _favourites,
        imageSource: widget.imageSource ?? DeviceImageSource(),
        locationSource: widget.locationSource ?? const DeviceLocationSource(),
        directionsLauncher:
            widget.directionsLauncher ?? const DeviceDirectionsLauncher(),
      ),
    );
  }
}
