import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';
import 'orders_screen.dart';
import 'reservations_screen.dart';

/// The two halves of the front desk: who is coming, and what to cook.
enum DeskTab {
  reservations('Réservations'),
  orders('Commandes');

  const DeskTab(this.label);

  final String label;
}

/// One screen for the venue being worked, with a switcher between its two
/// queues.
///
/// Orders sit beside reservations rather than in their own navigation
/// destination because they are the same job: a person turning up at a time,
/// and something owed to them when they do.
class VenueDeskScreen extends StatefulWidget {
  const VenueDeskScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<VenueDeskScreen> createState() => _VenueDeskScreenState();
}

class _VenueDeskScreenState extends State<VenueDeskScreen> {
  DeskTab _tab = DeskTab.reservations;

  /// Bumped by the refresh button. Each view watches it and reloads, so one
  /// button in the bar serves whichever queue is on screen.
  int _reloadToken = 0;

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final venue = auth.selectedVenue;
    final name = venue?.name ?? 'No venue';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reservations'),
            Text(
              // The role is shown because it decides what the rest of the app
              // will let this person do.
              venue == null ? name : '$name · ${venue.roleDisplay}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          // Only for accounts that actually have somewhere to switch to.
          if (auth.hasMultipleVenues)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: auth.changeVenue,
              tooltip: 'Switch venue',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _reloadToken++),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut,
            tooltip: 'Sign out',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<DeskTab>(
              segments: [
                for (final tab in DeskTab.values)
                  ButtonSegment(value: tab, label: Text(tab.label)),
              ],
              selected: {_tab},
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
        ),
      ),
      // The venue's own branding, on the venue's own screens. The bar above
      // and the navigation below stay on the app theme, so switching venues
      // recolours the work without recolouring the app around it.
      body: EstablishmentThemeScope(
        presetKey: venue?.themePreset,
        // IndexedStack: flipping between the two queues must not throw either
        // of them away and refetch, nor lose the date range on the other side.
        child: IndexedStack(
          index: _tab.index,
          children: [
            ReservationsView(auth: auth, reloadToken: _reloadToken),
            OrdersView(auth: auth, reloadToken: _reloadToken),
          ],
        ),
      ),
    );
  }
}
