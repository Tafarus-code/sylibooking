import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_client/shared_client.dart';

import '../l10n/app_localizations.dart';
import 'auth_controller.dart';
import 'image_source.dart';
import 'screens/login_screen.dart';
import 'screens/merchant_home_screen.dart';
import 'screens/venue_picker_screen.dart';
import 'token_store.dart';

/// Root widget. Shows login or the reservation list depending on auth state.
class MerchantApp extends StatefulWidget {
  const MerchantApp({
    super.key,
    required this.auth,
    this.imageSource,
    this.localeStore,
  });

  final AuthController auth;

  /// Injected so widget tests can drive uploads without a platform channel.
  final ImageSource? imageSource;

  /// Injected so widget tests can start the app in either language.
  final LocaleStore? localeStore;

  @override
  State<MerchantApp> createState() => _MerchantAppState();
}

class _MerchantAppState extends State<MerchantApp> {
  late final LocaleController _locale;

  @override
  void initState() {
    super.initState();
    _locale = LocaleController(
      store: widget.localeStore ?? SharedPreferencesLocaleStore(),
      // So the server's own messages — a refused status change, a venue that
      // takes no orders — arrive in the language on screen.
      api: widget.auth.api,
    )..load();
    // Only after the language is known: restore() is the first request out,
    // and one made too early would come back English.
    _locale.addListener(_restoreOnce);
  }

  bool _restored = false;

  void _restoreOnce() {
    if (_restored || !_locale.isLoaded) return;
    _restored = true;
    widget.auth.restore();
  }

  @override
  void dispose() {
    _locale.removeListener(_restoreOnce);
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
        // Same house style as the customer app; the chrome should not look
        // like two different products.
        theme: sylibookingAppTheme(),
        locale: _locale.locale,
        supportedLocales: L.supportedLocales,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: !_locale.isLoaded
            ? const _Splash()
            : ListenableBuilder(
                listenable: widget.auth,
                builder: (context, _) => switch (widget.auth.state) {
                  AuthState.unknown => const _Splash(),
                  AuthState.signedOut => LoginScreen(auth: widget.auth),
                  AuthState.choosingVenue =>
                    VenuePickerScreen(auth: widget.auth),
                  AuthState.signedIn => widget.auth.selectedVenue == null
                      ? NoVenueScreen(auth: widget.auth)
                      : MerchantHomeScreen(
                          imageSource: widget.imageSource ?? DeviceImageSource(),
                          localeController: _locale,
                          // Keyed on the venue as well as the user: switching
                          // venues must refetch, not show the previous venue's
                          // bookings.
                          key: ValueKey(
                            '${widget.auth.user?.id}-'
                            '${widget.auth.selectedVenueId}',
                          ),
                          auth: widget.auth,
                        ),
                },
              ),
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
