import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import '../directions.dart';
import '../image_source.dart';
import '../location_source.dart';
import 'browse_screen.dart';
import 'my_bookings_screen.dart';

/// The four-tab shell: browse, bookings, favourites, profile.
///
/// All chrome. It is themed by the app's own ThemeData and never by an
/// establishment's preset, however many branded venues are listed inside it.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    required this.api,
    required this.store,
    required this.imageSource,
    required this.locationSource,
    required this.directionsLauncher,
  });

  final SylibookingApi api;
  final BookingStore store;
  final ImageSource imageSource;
  final LocationSource locationSource;
  final DirectionsLauncher directionsLauncher;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack: switching tabs should not re-fetch the list or lose the
      // customer's place in it.
      body: IndexedStack(
        index: _index,
        children: [
          BrowseScreen(
            api: widget.api,
            store: widget.store,
            imageSource: widget.imageSource,
            locationSource: widget.locationSource,
            directionsLauncher: widget.directionsLauncher,
          ),
          MyBookingsScreen(
            api: widget.api,
            store: widget.store,
            imageSource: widget.imageSource,
          ),
          const _NotYetScreen(
            title: 'Favourites',
            icon: Icons.favorite_border,
            detail:
                'Saving a place for later needs somewhere to save it to, which '
                'means customer accounts. Not built yet.',
          ),
          const _NotYetScreen(
            title: 'Profile',
            icon: Icons.person_outline,
            detail:
                'Bookings are kept on this phone and identified by their '
                'reference, so there is no account to show yet.',
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favourites',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// A tab the mockup calls for and the product does not have yet.
///
/// Says so plainly rather than showing an empty list that looks broken.
class _NotYetScreen extends StatelessWidget {
  const _NotYetScreen({
    required this.title,
    required this.icon,
    required this.detail,
  });

  final String title;
  final IconData icon;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('$title is coming', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
