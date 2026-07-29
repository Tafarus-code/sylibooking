import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import '../directions.dart';
import '../image_source.dart';
import '../location_source.dart';
import 'establishment_screen.dart';
import 'my_bookings_screen.dart';

/// Discovery: what is open near me, and what kind of place is it.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
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
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Establishment> _establishments = const [];
  bool _loading = true;
  String? _error;
  EstablishmentType? _typeFilter;

  LatLng? _here;
  LocationStatus _locationStatus = LocationStatus.unknown;
  bool _sortByDistance = false;

  /// Sorting by distance is only offered once there is a position to sort by.
  bool get _canSortByDistance => _here != null;

  @override
  void initState() {
    super.initState();
    _load();
    _locateIfAlreadyAllowed();
  }

  /// Only asks the system for a fix if permission is already granted.
  ///
  /// Browsing must not open with a permission dialog: distance is a
  /// convenience, and a prompt before the customer has seen anything is the
  /// fastest way to get a permanent "no".
  Future<void> _locateIfAlreadyAllowed() async {
    if (!await widget.locationSource.hasPermission()) return;
    await _locate();
  }

  Future<void> _locate() async {
    final result = await widget.locationSource.current();
    if (!mounted) return;
    setState(() {
      _here = result.position;
      _locationStatus = result.status;
      // Nothing to sort by if the fix did not arrive.
      if (_here == null) _sortByDistance = false;
    });
  }

  /// Explains why before prompting, so a refusal is an informed one.
  Future<void> _askForLocation() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Show distances?'),
        content: const Text(
          'Sylibooking can show how far each place is and sort by what is '
          'nearest. Your location stays on your phone — it is never sent to '
          'us or to the venues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (!(agreed ?? false)) return;

    await _locate();
    if (!mounted || _here != null) return;

    // Nothing arrived. Say why, once, and carry on — browsing never depended
    // on this.
    final message = switch (_locationStatus) {
      LocationStatus.denied =>
        'No problem — browsing works without it. You can allow location later '
            'in your phone settings.',
      LocationStatus.servicesOff =>
        'Location is switched off on this phone. Turn it on to see distances.',
      _ => 'Could not get a location just now. Distances are unavailable.',
    };
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Distance from here, or null when either end has no coordinates.
  double? _distanceTo(Establishment establishment) {
    final here = _here;
    final there = establishment.position;
    if (here == null || there == null) return null;
    return distanceKm(here, there);
  }

  List<Establishment> get _visible {
    if (!_sortByDistance || _here == null) return _establishments;

    final sorted = [..._establishments];
    sorted.sort((a, b) {
      final da = _distanceTo(a);
      final db = _distanceTo(b);
      // Venues with no coordinates sink to the bottom rather than sorting as
      // if they were at the origin.
      if (da == null && db == null) return a.name.compareTo(b.name);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return sorted;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final search = _searchController.text.trim();
      final page = await widget.api.establishments(
        search: search.isEmpty ? null : search,
        type: switch (_typeFilter) {
          EstablishmentType.lounge => 'lounge',
          EstablishmentType.restaurant => 'restaurant',
          _ => null,
        },
      );
      if (!mounted) return;
      setState(() {
        _establishments = page.results;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    // Wait for a pause in typing rather than querying on every keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a table'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'My bookings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MyBookingsScreen(
                  api: widget.api,
                  store: widget.store,
                  imageSource: widget.imageSource,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search by name',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _load();
                            },
                          ),
                  ),
                ),
              ),
              // Scrolls rather than centring: three chips do not fit across a
              // 360dp phone, which is most of the market here.
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      for (final entry in [
                        (null, 'All'),
                        (EstablishmentType.lounge, 'Lounges'),
                        (EstablishmentType.restaurant, 'Restaurants'),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text(entry.$2),
                            selected: _typeFilter == entry.$1,
                            onSelected: (_) {
                              setState(() => _typeFilter = entry.$1);
                              _load();
                            },
                          ),
                        ),
                      // Sorting by distance appears only once there is a
                      // position to sort by; otherwise this is the way in.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _canSortByDistance
                            ? FilterChip(
                                avatar: const Icon(Icons.near_me, size: 16),
                                label: const Text('Nearest'),
                                selected: _sortByDistance,
                                onSelected: (selected) => setState(
                                  () => _sortByDistance = selected,
                                ),
                              )
                            : ActionChip(
                                avatar: const Icon(
                                  Icons.near_me_outlined,
                                  size: 16,
                                ),
                                label: const Text('Show distances'),
                                onPressed: _askForLocation,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load places',
        detail: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    if (_establishments.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off,
        title: 'Nothing found',
        detail: 'Try a different name, or clear the filters.',
      );
    }

    final visible = _visible;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final establishment = visible[index];
        return _EstablishmentTile(
          establishment: establishment,
          distanceKm: _distanceTo(establishment),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EstablishmentScreen(
                api: widget.api,
                store: widget.store,
                establishment: establishment,
                here: _here,
                directionsLauncher: widget.directionsLauncher,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EstablishmentTile extends StatelessWidget {
  const _EstablishmentTile({
    required this.establishment,
    required this.onTap,
    this.distanceKm,
  });

  final Establishment establishment;
  final VoidCallback onTap;

  /// Null when there is no fix, or the venue has no coordinates.
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLounge = establishment.type == EstablishmentType.lounge;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isLounge
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.secondaryContainer,
          child: Icon(
            isLounge ? Icons.local_fire_department : Icons.restaurant,
            color: isLounge
                ? theme.colorScheme.onTertiaryContainer
                : theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(establishment.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('${establishment.typeDisplay} · ${establishment.city}'),
            if (establishment.spaceCount != null)
              Text(
                '${establishment.spaceCount} '
                '${establishment.spaceCount == 1 ? "space" : "spaces"}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            // Both halves flex: "Open until 02:00 · 253 km away" does not fit
            // across a 360dp phone otherwise.
            Row(
              children: [
                Flexible(
                  child: _OpenIndicator(establishment: establishment),
                ),
                if (distanceKm case final km?) ...[
                  Text(
                    ' · ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      formatDistance(km),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Open or shut, at a glance, on every card.
///
/// A dot plus a word rather than colour alone — these are scanned down a list,
/// and colour on its own excludes anyone with a colour vision deficiency.
class _OpenIndicator extends StatelessWidget {
  const _OpenIndicator({required this.establishment});

  final Establishment establishment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Nothing recorded is not the same as shut; saying "Closed" would be a
    // guess, and pilot merchants will not all have filled their hours in.
    final unknown = establishment.today == null && !establishment.hasHours;
    if (unknown) {
      return Text(
        'Hours not listed',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final open = establishment.isOpenNow;
    final colour = open ? theme.colorScheme.primary : theme.colorScheme.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(open ? Icons.circle : Icons.circle_outlined, size: 10, color: colour),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            open ? establishment.openSummary : 'Closed',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colour,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
          child: Column(
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ],
    );
  }
}
