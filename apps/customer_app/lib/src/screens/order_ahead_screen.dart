import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import '../widgets/menu_section.dart';
import 'order_checkout_screen.dart';

/// Build a basket from a restaurant's menu, then go and pay for it.
///
/// Part of the restaurant's own page rather than app chrome, so it sits inside
/// that venue's theme scope and carries its branding — the customer has not
/// left the restaurant, they have started ordering from it.
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

  /// Every dish in the basket, for the review sheet.
  List<({MenuItem item, int quantity})> get _basket => [
        for (final category in _menu)
          for (final item in category.items)
            if ((_quantities[item.id] ?? 0) > 0)
              (item: item, quantity: _quantities[item.id]!),
      ];

  Future<void> _reviewCart() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _CartSheet(
        basket: _basket,
        total: _total,
        onChanged: (item, quantity) {
          _setQuantity(item, quantity);
          // The sheet is built from this state, so it has to be rebuilt too.
          (sheetContext as Element).markNeedsBuild();
          if (_itemCount == 0) Navigator.of(sheetContext).pop();
        },
      ),
    );
    if (mounted) setState(() {});
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
          : CartBar(
              itemCount: _itemCount,
              total: _total,
              onReview: _reviewCart,
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
      padding: contentInsets(context).copyWith(top: 8, bottom: 24),
      children: [
        // The same component the venue page uses, with steppers switched on.
        // A second menu layout would have drifted from the first inside a
        // slice.
        MenuSection(
          menu: _menu,
          quantityFor: (item) => _quantities[item.id] ?? 0,
          onQuantityChanged: _setQuantity,
        ),
      ],
    );
  }
}

/// The running basket, pinned at the bottom so it is never hunted for.
class CartBar extends StatelessWidget {
  const CartBar({
    super.key,
    required this.itemCount,
    required this.total,
    required this.onReview,
    required this.onCheckout,
  });

  final int itemCount;
  final double total;
  final VoidCallback onReview;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 3,
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: InkWell(
          // The whole bar opens the basket; the button skips straight to
          // paying. Tapping a total to see what makes it up is the thing
          // people try first.
          onTap: onReview,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$itemCount ${itemCount == 1 ? "item" : "items"} · tap '
                        'to review',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${NumberFormat('#,##0.00').format(total)} GNF',
                        style: sylibookingPriceStyle(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onCheckout,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Checkout'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What is in the basket, and a last chance to change it.
class _CartSheet extends StatelessWidget {
  const _CartSheet({
    required this.basket,
    required this.total,
    required this.onChanged,
  });

  final List<({MenuItem item, int quantity})> basket;
  final double total;
  final void Function(MenuItem item, int quantity) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your basket', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final line in basket)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(line.item.name)),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: 'One fewer ${line.item.name}',
                            onPressed: () =>
                                onChanged(line.item, line.quantity - 1),
                          ),
                          Text('${line.quantity}'),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'One more ${line.item.name}',
                            onPressed: () =>
                                onChanged(line.item, line.quantity + 1),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text('Total', style: theme.textTheme.titleMedium),
                ),
                Text(
                  '${NumberFormat('#,##0.00').format(total)} GNF',
                  style: sylibookingPriceStyle(context),
                ),
              ],
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
