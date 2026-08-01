import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../booking_store.dart';
import '../directions.dart';
import '../widgets/hours_section.dart';
import '../widgets/menu_section.dart';
import '../widgets/photos_section.dart';
import '../widgets/rating_stars.dart';
import '../widgets/reviews_section.dart';
import 'booking_form_screen.dart';
import 'order_ahead_screen.dart';
import 'photo_viewer_screen.dart';

/// Pick a day, a party size, and a time.
class EstablishmentScreen extends StatefulWidget {
  const EstablishmentScreen({
    super.key,
    required this.api,
    required this.store,
    required this.establishment,
    required this.directionsLauncher,
    this.here,
  });

  final SylibookingApi api;
  final BookingStore store;
  final Establishment establishment;
  final DirectionsLauncher directionsLauncher;

  /// The customer's position, when there is one.
  final LatLng? here;

  @override
  State<EstablishmentScreen> createState() => _EstablishmentScreenState();
}

class _EstablishmentScreenState extends State<EstablishmentScreen> {
  static const _maxPartySize = 12;
  static const _daysAhead = 14;

  late DateTime _day;
  int _partySize = 2;

  Establishment? _detail;
  List<TimeOption> _options = const [];
  bool _loading = true;
  String? _error;

  List<Review> _reviews = const [];
  List<Photo> _photos = const [];
  bool _loadingExtras = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    _load();
    _loadExtras();
  }

  /// Reviews and photos load alongside availability rather than blocking it:
  /// a customer is here to book, and the social proof can arrive a moment
  /// later without holding up the times.
  Future<void> _loadExtras() async {
    try {
      final reviews = await widget.api.reviews(widget.establishment.id);
      final photos = await widget.api.photos(widget.establishment.id);
      if (!mounted) return;
      setState(() {
        _reviews = reviews.results;
        _photos = photos.results;
        _loadingExtras = false;
      });
    } on ApiException {
      if (mounted) setState(() => _loadingExtras = false);
    } on ApiUnreachableException {
      if (mounted) setState(() => _loadingExtras = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // The detail call is only needed once; availability changes per pick.
      final detail = _detail ??
          await widget.api.establishment(widget.establishment.id);
      final grid = await widget.api.availability(
        widget.establishment.id,
        _day,
        partySize: _partySize,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _options = bookableTimes(grid, partySize: _partySize);
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

  /// How far the venue is, or null without both ends of the pair.
  double? get _distance {
    final here = widget.here;
    final there = (_detail ?? widget.establishment).position;
    if (here == null || there == null) return null;
    return distanceKm(here, there);
  }

  Future<void> _openDirections() async {
    final establishment = _detail ?? widget.establishment;
    final destination = establishment.position;
    if (destination == null) return;

    final opened = await widget.directionsLauncher.open(
      destination,
      label: establishment.name,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(L.of(context).noMapsApp)));
    }
  }

  /// Ordering ahead for collection, which only restaurants offer.
  void _openOrderAhead(Establishment establishment) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderAheadScreen(
          api: widget.api,
          store: widget.store,
          establishment: establishment,
        ),
      ),
    );
  }

  /// Opens the album full screen at the picture that was tapped.
  void _openPhoto(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(photos: _photos, initialIndex: index),
      ),
    );
  }

  Future<void> _openBooking(TimeOption option) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingFormScreen(
          api: widget.api,
          store: widget.store,
          establishment: widget.establishment,
          option: option,
          partySize: _partySize,
        ),
      ),
    );

    // Someone else may have taken a slot while the form was open.
    if ((booked ?? false) && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final establishment = _detail ?? widget.establishment;

    // The venue's branding is scoped to this screen alone. Browse, the
    // bottom of the stack, and every other screen keep the app's own theme,
    // so moving between venues never makes the app itself look different.
    return EstablishmentThemeScope(
      presetKey: establishment.themePreset,
      // Builder so the subtree reads the scoped theme rather than the outer
      // one this method was built with.
      child: Builder(
        builder: (context) => _scaffold(context, establishment),
      ),
    );
  }

  Widget _scaffold(BuildContext context, Establishment establishment) {
    final l = L.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(establishment.name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: contentInsets(context).copyWith(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${establishment.typeDisplay} · ${establishment.city}',
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (establishment.averageRating case final average?) ...[
                    const SizedBox(height: 6),
                    RatingStars(rating: average, size: 18),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    establishment.address,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_distance case final km?) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.near_me,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          formatDistance(km),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Directions need the venue's coordinates, not the
                  // customer's — offered even without a location fix.
                  if (establishment.hasPosition) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openDirections,
                      icon: const Icon(Icons.directions, size: 18),
                      label: Text(l.getDirections),
                    ),
                  ],
                  const SizedBox(height: 12),
                  HoursSection(establishment: establishment),
                  if (establishment.openingHours.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      establishment.openingHours,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_photos.isNotEmpty || _loadingExtras) ...[
              const SizedBox(height: 16),
              PhotosSection(
                photos: _photos,
                loading: _loadingExtras,
                onTapPhoto: _openPhoto,
              ),
            ],
            if (establishment.hasMenu) ...[
              const Divider(height: 32),
              // Restaurants only, and only when there is a menu to order
              // from. A lounge showing this would be an invitation the server
              // is going to refuse.
              if (establishment.type == EstablishmentType.restaurant)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: FilledButton.icon(
                    onPressed: () => _openOrderAhead(establishment),
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text(l.orderAhead),
                  ),
                ),
              MenuSection(menu: establishment.menu),
            ],
            const Divider(height: 32),
            ReviewsSection(
              establishment: establishment,
              reviews: _reviews,
              loading: _loadingExtras,
            ),
            const Divider(height: 32),
            _SectionLabel(l.partySize),
            _PartySizePicker(
              value: _partySize,
              max: _maxPartySize,
              onChanged: (value) {
                setState(() => _partySize = value);
                _load();
              },
            ),
            const SizedBox(height: 16),
            _SectionLabel(l.day),
            _DayPicker(
              selected: _day,
              days: _daysAhead,
              onChanged: (value) {
                setState(() => _day = value);
                _load();
              },
            ),
            const SizedBox(height: 16),
            _SectionLabel(l.availableTimes),
            _times(),
          ],
        ),
      ),
    );
  }

  Widget _times() {
    final l = L.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(l.tryAgain)),
          ],
        ),
      );
    }

    if (_options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Icon(
              Icons.event_busy,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l.nothingFreeForParty(_partySize),
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              l.tryAnotherDay,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in _options)
            ActionChip(
              label: Text(DateFormat.Hm().format(option.start)),
              avatar: option.isLastSpace
                  ? const Icon(Icons.priority_high, size: 16)
                  : null,
              tooltip: option.isLastSpace
                  ? l.lastSpaceFree
                  : l.spacesFree(option.freeSpaceCount),
              onPressed: () => _openBooking(option),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}

class _PartySizePicker extends StatelessWidget {
  const _PartySizePicker({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // Wrap, not a scroller: twelve small chips fit two rows on the narrowest
    // phone, so hiding half of them behind a sideways swipe bought nothing and
    // cost the customer the ability to see the choice at all.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var size = 1; size <= max; size++)
            ChoiceChip(
              label: Text('$size'),
              selected: value == size,
              onSelected: (_) => onChanged(size),
            ),
        ],
      ),
    );
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.selected,
    required this.days,
    required this.onChanged,
  });

  final DateTime selected;
  final int days;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // A dropdown, not a row of chips. Two weeks of dates never fitted across a
    // phone, and the ones past the edge were reachable only by a sideways
    // swipe — a gesture that is invisible, and impossible with a mouse.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<DateTime>(
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.calendar_today_outlined),
          isDense: true,
        ),
        items: [
          for (var offset = 0; offset < days; offset++)
            _dayItem(l, today.add(Duration(days: offset)), offset),
        ],
        onChanged: (day) {
          if (day != null) onChanged(day);
        },
      ),
    );
  }

  DropdownMenuItem<DateTime> _dayItem(L l, DateTime day, int offset) {
    // "Today" and "Tomorrow" carry more than a weekday name does, and those
    // are the two days most bookings are for.
    final label = switch (offset) {
      0 => l.today,
      1 => l.tomorrow,
      // Named in the app's language, not the phone's: a French UI showing
      // "Wednesday" is the half-translated look this whole change is against.
      _ => DateFormat.EEEE(l.localeName).format(day),
    };

    return DropdownMenuItem(
      value: day,
      child: Text(
        '$label · ${DateFormat.MMMd().format(day)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
