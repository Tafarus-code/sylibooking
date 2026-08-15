import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_client/shared_client.dart';

import '../l10n/app_localizations.dart';
import 'auth_controller.dart';
import 'export_sink.dart';
import 'image_source.dart';
import 'printing/ticket_printer.dart';
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
    this.printer,
    this.exportSink,
  });

  final AuthController auth;

  /// Injected so widget tests can drive uploads without a platform channel.
  final ImageSource? imageSource;

  /// Where kitchen tickets go. Null means the console printer, which is what
  /// runs until a venue owns hardware — see printing/ticket_printer.dart.
  final TicketPrinter? printer;

  /// Where an exported CSV goes. Null means the file sink.
  final ExportSink? exportSink;

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
        // The merchant app's own look — Indigo Ledger. The two apps no longer
        // share one house style: a customer browsing lounges at night and a
        // manager working a counter in daylight are different rooms, and the
        // palettes now say so.
        //
        // Not one of the five venue presets, one of which is called "Indigo
        // Soir" — see the note at the top of baseline_theme.dart.
        theme: merchantBaselineTheme(),
        locale: _locale.locale,
        supportedLocales: L.supportedLocales,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // The client writes two sentences of its own — a stalled request and
        // an unreachable one — and has no catalogue to write them from. Handed
        // down here, where the language is settled, for the same reason the
        // locale controller hands down `languageCode`.
        builder: (context, child) {
          widget.auth.api.networkText = ApiNetworkText(
            slow: L.of(context).connectionSlow,
            unreachable: L.of(context).connectionFailed,
          );
          // The canvas, once, under everything — the same arrangement the
          // customer app uses, and for the same reason: a sibling of the
          // navigator is painted once and survives every push. It covers the
          // tablet and the phone layouts alike, because both are Scaffolds
          // made transparent by the baseline theme.
          //
          // Nothing is ever blurred over this one. See FrostedPanel.
          return Stack(
            children: [
              const Positioned.fill(child: MerchantBaselineBackground()),
              child ?? const SizedBox.shrink(),
            ],
          );
        },
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
                          printer: widget.printer,
                          exportSink: widget.exportSink,
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
