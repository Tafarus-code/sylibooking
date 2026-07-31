import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import 'order_checkout_screen.dart';

/// Build a basket from a restaurant's menu, then go and pay for it.
///
/// Pickup only: there is no address to enter and no delivery to schedule, so
/// the whole flow is what, when, and how it is paid for.
class OrderAheadScreen extends StatefulWidget {
  const OrderAheadScreen({
    super.key,
    required this.api,
    required this.store,
    required this.establishment,
    this.reservationReference,
  });

  final SylibookingApi api;
  final BookingStore store;
  final Establishment establishment;

  /// Set when the customer already has a table here, so the kitchen can time
  /// the food to the booking rather than to a counter pickup.
  final String? reservationReference;

  @override
  State<OrderAheadScreen> createState() => _OrderAheadScreenState();
}

class _OrderAheadScreenState extends State<OrderAheadScreen> {
  /// menu item id -> quantity. Only what has actually been chosen.
  final Map<int, int> _quantities = {};

  Establishment? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.establishment(widget.establishment.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => (_error = e.message, _loading = false).$1);
    } on ApiUnreachableException catch (e) {
      if (mounted) setState(() => (_error = e.message, _loading = false).$1);
    }
  }

  List<MenuCategory> get _menu => _detail?.menu ?? const [];

  int get _itemCount =>
      _quantities.values.fold(0, (running, count) => running + count);

  /// The basket total, from the menu prices as they stand right now.
  ///
  /// The server recalculates and snapshots its own figure when the order is
  /// placed; this is only what to show while choosing.
  double get _total {
    var total = 0.0;
    for (final category in _menu) {
      for (final item in category.items) {
        final quantity = _quantities[item.id] ?? 0;
        if (quantity == 0) continue;
        total += (double.tryParse(item.price) ?? 0) * quantity;
      }
    }
    return total;
  }

  void _setQuantity(MenuItem item, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _quantities.remove(item.id);
      } else {
        _quantities[item.id] = quantity;
      }
    });
  }

  Future<void> _checkout() async {
    final placed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderCheckoutScreen(
          api: widget.api,
          store: widget.store,
          establishment: _detail ?? widget.establishment,
          lines: [
            for (final entry in _quantities.entries)
              CartLine(menuItemId: entry.key, quantity: entry.value),
          ],
          reservationReference: widget.reservationReference,
        ),
      ),
    );

    // The order is placed and the basket is spent; drop back to the venue.
    if ((placed ?? false) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return EstablishmentThemeScope(
      presetKey: (_detail ?? widget.establishment).themePreset,
      child: Builder(builder: _scaffold),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order ahead')),
      body: _body(),
      bottomNavigationBar: _itemCount == 0
          ? null
          : _CartBar(
              itemCount: _itemCount,
              total: _total,
              onCheckout: _checkout,
            ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off,
        title: 'Could not load the menu',
        detail: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    if (_menu.isEmpty) {
      return const _Message(
        icon: Icons.restaurant_menu,
        title: 'Nothing to order yet',
        detail: 'This restaurant has not put its menu online. You can still '
            'book a table and order at it.',
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: contentInsets(context).copyWith(bottom: 24),
      children: [
        for (final category in _menu) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              category.categoryDisplay,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final item in category.items)
            _MenuRow(
              item: item,
              quantity: _quantities[item.id] ?? 0,
              onChanged: (quantity) => _setQuantity(item, quantity),
            ),
        ],
      ],
    );
  }
}

/// One dish with a stepper. Tapping + is the whole interaction.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.quantity,
    required this.onChanged,
  });

  final MenuItem item;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl case final url?) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) => const SizedBox(
                  width: 64,
                  height: 64,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: theme.textTheme.bodyLarge),
                if (item.description.isNotEmpty)
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${item.price} GNF',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Stepper(quantity: quantity, onChanged: onChanged, name: item.name),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.onChanged,
    required this.name,
  });

  final int quantity;
  final ValueChanged<int> onChanged;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (quantity == 0) {
      return OutlinedButton(
        onPressed: () => onChanged(1),
        child: Text('Add', semanticsLabel: 'Add $name'),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'One fewer $name',
          onPressed: () => onChanged(quantity - 1),
        ),
        Text('$quantity', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'One more $name',
          onPressed: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

/// The running basket, pinned at the bottom so it is never hunted for.
class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.itemCount,
    required this.total,
    required this.onCheckout,
  });

  final int itemCount;
  final double total;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$itemCount ${itemCount == 1 ? "item" : "items"}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '${NumberFormat('#,##0.00').format(total)} GNF',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onCheckout,
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Checkout'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
    );
  }
}
