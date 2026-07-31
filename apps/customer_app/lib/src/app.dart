import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_client/shared_client.dart';

import '../l10n/app_localizations.dart';
import 'booking_store.dart';
import 'customer_auth.dart';
import 'directions.dart';
import 'favourites_controller.dart';
import 'image_source.dart';
import 'locale_controller.dart';
import 'location_source.dart';
import 'screens/customer_home_screen.dart';

class CustomerApp extends StatefulWidget {
  const CustomerApp({
    super.key,
    required this.api,
    required this.store,
    this.tokenStore,
    this.localeStore,
    this.imageSource,
    this.locationSource,
    this.directionsLauncher,
  });

  final SylibookingApi api;
  final BookingStore store;

  /// Injected so widget tests can drive these without a platform channel.
  final CustomerTokenStore? tokenStore;
  final LocaleStore? localeStore;
  final ImageSource? imageSource;
  final LocationSource? locationSource;
  final DirectionsLauncher? directionsLauncher;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  late final CustomerAuth _auth;
  late final FavouritesController _favourites;
  late final LocaleController _locale;

  @override
  void initState() {
    super.initState();
    // Built here rather than in the shell so they outlive a rebuild: the
    // account, the saved list and the language are app state, not screen
    // state.
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
    _locale = LocaleController(
      store: widget.localeStore ?? SharedPreferencesLocaleStore(),
    )..load();
  }

  @override
  void dispose() {
    _favourites.dispose();
    _auth.dispose();
    _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _locale,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => L.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        // The app's own look. Establishment branding is layered on top of
        // this by EstablishmentThemeScope, and only on a venue's own screens.
        theme: sylibookingAppTheme(),
        // Null follows the phone, which in this market is usually already
        // French. The toggle is for when the phone is wrong, not a first step.
        locale: _locale.locale,
        supportedLocales: L.supportedLocales,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: CustomerHomeScreen(
          api: widget.api,
          store: widget.store,
          auth: _auth,
          favourites: _favourites,
          localeController: _locale,
          imageSource: widget.imageSource ?? DeviceImageSource(),
          locationSource: widget.locationSource ?? const DeviceLocationSource(),
          directionsLauncher:
              widget.directionsLauncher ?? const DeviceDirectionsLauncher(),
        ),
      ),
    );
  }
}
