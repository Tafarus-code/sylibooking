import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';
import '../image_source.dart';
import 'manage_screen.dart';
import 'payments_dashboard_screen.dart';
import 'reservations_screen.dart';

/// The signed-in shell: tonight's bookings, and the money behind them.
class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({
    super.key,
    required this.auth,
    required this.imageSource,
  });

  final AuthController auth;
  final ImageSource imageSource;

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: const [
        AdaptiveDestination(
          label: 'Reservations',
          icon: Icons.event_note_outlined,
          selectedIcon: Icons.event_note,
        ),
        AdaptiveDestination(
          label: 'Payments',
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments,
        ),
        AdaptiveDestination(
          label: 'Manage',
          icon: Icons.tune_outlined,
          selectedIcon: Icons.tune,
        ),
      ],
      // IndexedStack rather than rebuilding: switching to payments and back
      // should not throw away the day's list and re-fetch it.
      body: IndexedStack(
        index: _index,
        children: [
          ReservationsScreen(auth: widget.auth),
          PaymentsDashboardScreen(auth: widget.auth),
          ManageScreen(auth: widget.auth, imageSource: widget.imageSource),
        ],
      ),
    );
  }
}
