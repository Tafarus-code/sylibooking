import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';
import '../labels.dart';
import 'orders_screen.dart';
import 'reservations_screen.dart';

/// The two halves of the front desk: who is coming, and what to cook.
enum DeskTab {
  reservations,
  orders;

  /// Both labels stay French in either language: they are the words merchants
  /// already use on the floor, and the switcher is read at a glance.
  String label(L l) =>
      this == DeskTab.reservations ? l.tabReservations : l.tabOrders;
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

  /// When the queues on screen were last fetched. Everything created after
  /// this is work the merchant has not seen.
  DateTime _loadedAt = DateTime.now();

  /// What has landed since. Shown as a quiet marker rather than dropped into
  /// the list: a list that reorders under someone's finger mid-service is
  /// worse than one that is a minute stale.
  MerchantActivity _waiting = const MerchantActivity();

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Until push notifications exist — they need Firebase and a signing
    // story — asking now and then is how the desk finds out at all.
    _poll = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkForNewWork(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkForNewWork() async {
    final venueId = widget.auth.selectedVenueId;
    if (venueId == null) return;

    try {
      final activity = await widget.auth.api.merchantActivity(
        establishmentId: venueId,
        since: _loadedAt,
      );
      if (!mounted) return;
      setState(() => _waiting = activity);
    } on ApiException {
      // A failed check is not worth telling the merchant about; the next
      // one is a minute away.
    } on ApiUnreachableException {
      // Likewise.
    }
  }

  void _reload() {
    setState(() {
      _reloadToken++;
      _loadedAt = DateTime.now();
      _waiting = const MerchantActivity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final l = L.of(context);
    final venue = auth.selectedVenue;
    final name = venue?.name ?? l.noVenue;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.navReservations),
            Text(
              // The role is shown because it decides what the rest of the app
              // will let this person do.
              venue == null ? name : '$name · ${venue.role.name(l)}',
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
              tooltip: l.switchVenue,
            ),
          IconButton(
            // Badged rather than replaced: the merchant decides when the
            // list moves.
            icon: Badge(
              isLabelVisible: _waiting.isAnything,
              label: Text('${_waiting.total}'),
              child: const Icon(Icons.refresh),
            ),
            onPressed: _reload,
            tooltip: l.refresh,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut,
            tooltip: l.signOut,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<DeskTab>(
              segments: [
                for (final tab in DeskTab.values)
                  ButtonSegment(
                    value: tab,
                    // A segment is a fixed-height pill: a label that wraps
                    // gets its second line clipped rather than growing.
                    label:
                        Text(tab.label(l), maxLines: 1, softWrap: false),
                  ),
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
      body: Column(
        children: [
          // A badge on an icon is easy to miss with your hands full. This is
          // one line, and it does not move anything until it is tapped.
          if (_waiting.isAnything)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: InkWell(
                onTap: _reload,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active_outlined,
                        size: 18,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.newSinceYouLooked(_waiting.total),
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                        ),
                      ),
                      Text(
                        l.showNewWork,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: _queues(venue)),
        ],
      ),
    );
  }

  Widget _queues(MerchantVenue? venue) {
    final auth = widget.auth;
    return EstablishmentThemeScope(
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
    );
  }
}
