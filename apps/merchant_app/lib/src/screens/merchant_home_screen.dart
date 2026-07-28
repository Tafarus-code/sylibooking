import 'package:flutter/material.dart';

import '../auth_controller.dart';
import 'payments_dashboard_screen.dart';
import 'reservations_screen.dart';

/// The signed-in shell: tonight's bookings, and the money behind them.
class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack rather than rebuilding: switching to payments and back
      // should not throw away the day's list and re-fetch it.
      body: IndexedStack(
        index: _index,
        children: [
          ReservationsScreen(auth: widget.auth),
          PaymentsDashboardScreen(auth: widget.auth),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Reservations',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Payments',
          ),
        ],
      ),
    );
  }
}
