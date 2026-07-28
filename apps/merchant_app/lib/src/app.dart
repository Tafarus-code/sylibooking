import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'screens/login_screen.dart';
import 'screens/reservations_screen.dart';

/// Root widget. Shows login or the reservation list depending on auth state.
class MerchantApp extends StatefulWidget {
  const MerchantApp({super.key, required this.auth});

  final AuthController auth;

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: widget.auth,
        builder: (context, _) => switch (widget.auth.state) {
          AuthState.unknown => const _Splash(),
          AuthState.signedOut => LoginScreen(auth: widget.auth),
          AuthState.signedIn => ReservationsScreen(
              // Rebuild the screen from scratch per session, so one merchant's
              // bookings never linger after another signs in.
              key: ValueKey(widget.auth.user?.id),
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
