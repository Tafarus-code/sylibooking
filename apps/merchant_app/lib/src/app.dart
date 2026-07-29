import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import 'auth_controller.dart';
import 'image_source.dart';
import 'screens/login_screen.dart';
import 'screens/merchant_home_screen.dart';
import 'screens/venue_picker_screen.dart';

/// Root widget. Shows login or the reservation list depending on auth state.
class MerchantApp extends StatefulWidget {
  const MerchantApp({
    super.key,
    required this.auth,
    this.imageSource,
  });

  final AuthController auth;

  /// Injected so widget tests can drive uploads without a platform channel.
  final ImageSource? imageSource;

  @override
  State<MerchantApp> createState() => _MerchantAppState();
}

class _MerchantAppState extends State<MerchantApp> {
  @override
  void initState() {
    super.initState();
    widget.auth.restore();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sylibooking Merchant',
      debugShowCheckedModeBanner: false,
      // Same house style as the customer app; the chrome should not look
      // like two different products.
      theme: sylibookingAppTheme(),
      home: ListenableBuilder(
        listenable: widget.auth,
        builder: (context, _) => switch (widget.auth.state) {
          AuthState.unknown => const _Splash(),
          AuthState.signedOut => LoginScreen(auth: widget.auth),
          AuthState.choosingVenue => VenuePickerScreen(auth: widget.auth),
          AuthState.signedIn => widget.auth.selectedVenue == null
              ? NoVenueScreen(auth: widget.auth)
              : MerchantHomeScreen(
                  imageSource:
                      widget.imageSource ?? DeviceImageSource(),
                  // Keyed on the venue as well as the user: switching venues
                  // must refetch, not show the previous venue's bookings.
                  key: ValueKey(
                    '${widget.auth.user?.id}-${widget.auth.selectedVenueId}',
                  ),
                  auth: widget.auth,
                ),
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
