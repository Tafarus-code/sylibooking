import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import '../directions.dart';
import '../favourites_controller.dart';
import '../widgets/establishment_card.dart';
import 'establishment_screen.dart';

/// Venues the customer has saved.
///
/// Works signed out — the list lives on the phone. An account only makes it
/// portable, which is said plainly at the bottom rather than being demanded
/// up front.
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({
    super.key,
    required this.api,
    required this.store,
    required this.favourites,
    required this.directionsLauncher,
    this.signedIn = false,
  });

  final SylibookingApi api;
  final BookingStore store;
  final FavouritesController favourites;
  final DirectionsLauncher directionsLauncher;
  final bool signedIn;

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  List<Establishment> _venues = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    widget.favourites.addListener(_load);
  }

  @override
  void dispose() {
    widget.favourites.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final ids = widget.favourites.ids;
    if (ids.isEmpty) {
      setState(() {
        _venues = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Fetched one by one from the ids on the device, so the list is right
      // whether or not there is an account behind it.
      final venues = <Establishment>[];
      for (final id in ids) {
        try {
          venues.add(await widget.api.establishment(id));
        } on ApiException {
          // A venue that has closed drops off the list quietly.
        }
      }
      if (!mounted) return;
      setState(() {
        _venues = venues;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourites')),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final theme = Theme.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _Empty(
        icon: Icons.cloud_off,
        title: 'Could not load your favourites',
        detail: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    if (_venues.isEmpty) {
      return const _Empty(
        icon: Icons.favorite_border,
        title: 'Nothing saved yet',
        detail: 'Tap the heart on a place you like and it will wait for you '
            'here.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsForWidth(constraints.maxWidth);

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: contentInsets(context, maxWidth: ContentWidth.list),
          children: [
            if (columns == 1)
              for (final venue in _venues) _card(venue)
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 0.92,
                ),
                itemCount: _venues.length,
                itemBuilder: (context, index) => _card(_venues[index]),
              ),
            if (!widget.signedIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text(
                  'Saved on this phone. Make an account from Profile and they '
                  'follow you to the next one.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _card(Establishment venue) => EstablishmentCard(
        establishment: venue,
        isFavourite: true,
        onToggleFavourite: () => widget.favourites.toggle(venue.id),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EstablishmentScreen(
              api: widget.api,
              store: widget.store,
              establishment: venue,
              directionsLauncher: widget.directionsLauncher,
            ),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({
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
          padding: contentInsets(context, minHorizontal: 32)
              .copyWith(top: 72, bottom: 32),
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
