import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../booking_store.dart';
import '../favourites_controller.dart';
import '../directions.dart';
import '../image_source.dart';
import '../location_source.dart';
import '../widgets/browse_header.dart';
import '../widgets/establishment_card.dart';
import 'establishment_screen.dart';

/// Discovery: what is open near me, and what kind of place is it.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.api,
    required this.store,
    required this.favourites,
    required this.imageSource,
    required this.locationSource,
    required this.directionsLauncher,
  });

  final SylibookingApi api;
  final BookingStore store;
  final FavouritesController favourites;
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

  /// Filtered client-side: the API has no open-now filter, and adding one
  /// would mean the server deciding "now" for a list the client caches.
  bool _openOnly = false;

  /// Sentinels so the chip row can carry filters of different kinds.
  static const _openNowFilter = 'open-now';
  static const _nearestFilter = 'nearest';

  /// From the last booking on this device; there are no customer accounts.
  String? _customerName;

  /// Cover photo per venue, fetched lazily so the list is not blocked on it.
  final Map<int, String?> _covers = {};

  /// Sorting by distance is only offered once there is a position to sort by.
  bool get _canSortByDistance => _here != null;

  @override
  void initState() {
    super.initState();
    _load();
    _locateIfAlreadyAllowed();
    _loadCustomerName();
  }

  Future<void> _loadCustomerName() async {
    final last = await widget.store.lastCustomer();
    if (last == null || !mounted) return;
    setState(() => _customerName = last.name);
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
    final l = L.of(context);
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.showDistancesTitle),
        content: Text(l.showDistancesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.allow),
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
      LocationStatus.denied => l.locationDenied,
      LocationStatus.servicesOff => l.locationServicesOff,
      _ => l.locationUnavailable,
    };
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Fetch a venue's first photo once, for the card's cover.
  ///
  /// Deliberately after the list is on screen: the names and times are what a
  /// customer is scanning, and they should not wait on images.
  void _ensureCover(Establishment establishment) {
    if (_covers.containsKey(establishment.id)) return;
    _covers[establishment.id] = null;

    widget.api.photos(establishment.id).then((page) {
      if (!mounted || page.results.isEmpty) return;
      setState(() => _covers[establishment.id] = page.results.first.imageUrl);
    }).catchError((Object _) {
      // No cover is a normal state, not an error worth showing.
    });
  }

  /// Distance from here, or null when either end has no coordinates.
  double? _distanceTo(Establishment establishment) {
    final here = _here;
    final there = establishment.position;
    if (here == null || there == null) return null;
    return distanceKm(here, there);
  }

  List<Establishment> get _visible {
    var shown = _establishments;
    if (_openOnly) {
      shown = shown.where((e) => e.isOpenNow).toList();
    }
    if (!_sortByDistance || _here == null) return shown;

    final sorted = [...shown];
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
        // The catalogue is throttled per connection now. DRF's own wording
        // for that is English and counts seconds; this says the same thing
        // in the customer's language and without the arithmetic.
        _error = e.messageOr(whenThrottled: L.of(context).browsingTooFast);
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
    final l = L.of(context);

    // Chrome: this screen stays on the app theme no matter which venues, and
    // therefore which presets, appear in the list below.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        // Header, filters and list share one measure, so the search field does
        // not stretch to a desktop's full width while the cards stay centred.
        child: ContentColumn(
          maxWidth: ContentWidth.list,
          child: Column(
          children: [
            BrowseHeader(
              controller: _searchController,
              onChanged: _onSearchChanged,
              customerName: _customerName,
              onClear: () {
                _searchController.clear();
                _load();
              },
            ),
            BrowseFilters(
              options: [
                (null, l.filterAll),
                (EstablishmentType.restaurant, l.filterRestaurants),
                (EstablishmentType.lounge, l.filterLounges),
                (_openNowFilter, l.filterOpenNow),
                (
                  _nearestFilter,
                  _canSortByDistance ? l.filterNearest : l.filterShowDistances,
                ),
              ],
              isSelected: (value) => switch (value) {
                _openNowFilter => _openOnly,
                _nearestFilter => _sortByDistance,
                final EstablishmentType? type => _typeFilter == type,
                _ => false,
              },
              onSelected: (value) {
                switch (value) {
                  case _openNowFilter:
                    setState(() => _openOnly = !_openOnly);
                  case _nearestFilter:
                    if (_canSortByDistance) {
                      setState(() => _sortByDistance = !_sortByDistance);
                    } else {
                      _askForLocation();
                    }
                  case final EstablishmentType? type:
                    setState(() => _typeFilter = type);
                    _load();
                }
              },
            ),
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(onRefresh: _load, child: _body()),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final l = L.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off,
        title: l.couldNotLoadPlaces,
        detail: _error!,
        action: FilledButton(onPressed: _load, child: Text(l.tryAgain)),
      );
    }

    final visible = _visible;

    if (visible.isEmpty) {
      // "Open now" filters client-side, so the list can empty out even when the
      // fetch returned venues. Name that case rather than showing blank space.
      return _EmptyState(
        icon: Icons.search_off,
        title: l.nothingFound,
        detail: _openOnly && _establishments.isNotEmpty
            ? l.nothingOpenRightNow
            : l.nothingFoundDetail,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // One column on a phone, more as the window allows. Driven by the card
        // width the design wants, not by a device guess.
        final columns = columnsForWidth(constraints.maxWidth);

        if (columns == 1) {
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: visible.length,
            itemBuilder: (context, index) => _card(visible[index]),
          );
        }

        // Tall enough for the cover plus two lines of text under it. A grid
        // cell is a fixed box, so this leans generous: empty space at the
        // bottom of a card is survivable, a clipped rating line is not.
        final cellWidth = constraints.maxWidth / columns;
        var cellHeight = cellWidth / 0.92;

        // Except on a short window, where a card taller than the viewport
        // means never seeing a whole one. The card gives the cover back the
        // height instead of overflowing.
        final ceiling = constraints.maxHeight * 0.75;
        if (constraints.hasBoundedHeight && cellHeight > ceiling) {
          cellHeight = ceiling;
        }

        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: cellWidth / cellHeight,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) => _card(visible[index]),
        );
      },
    );
  }

  Widget _card(Establishment establishment) {
    _ensureCover(establishment);
    // Listens per card: the heart has to fill the instant it is tapped, and
    // rebuilding the whole list for that would lose the scroll position on a
    // long one.
    return ListenableBuilder(
      listenable: widget.favourites,
      builder: (context, _) => EstablishmentCard(
        establishment: establishment,
        coverUrl: _covers[establishment.id],
        distanceKm: _distanceTo(establishment),
        isFavourite: widget.favourites.contains(establishment.id),
        onToggleFavourite: () => widget.favourites.toggle(establishment.id),
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
      ),
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
