import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import 'establishment_screen.dart';
import 'my_bookings_screen.dart';

/// Discovery: what is open near me, and what kind of place is it.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.api, required this.store});

  final SylibookingApi api;
  final BookingStore store;

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

  @override
  void initState() {
    super.initState();
    _load();
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

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _establishments.length,
      itemBuilder: (context, index) {
        final establishment = _establishments[index];
        return _EstablishmentTile(
          establishment: establishment,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EstablishmentScreen(
                api: widget.api,
                store: widget.store,
                establishment: establishment,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EstablishmentTile extends StatelessWidget {
  const _EstablishmentTile({required this.establishment, required this.onTap});

  final Establishment establishment;
  final VoidCallback onTap;

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
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
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
