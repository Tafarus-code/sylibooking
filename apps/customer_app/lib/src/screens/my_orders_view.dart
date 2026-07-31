import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import '../customer_auth.dart';
import 'order_tracking_screen.dart';

/// Orders this device has placed, split into what is still coming and what is
/// already done.
///
/// Reads from the account when there is one, so a new phone sees the history;
/// otherwise from the references kept on this device, which is how the app
/// has always worked.
class MyOrdersView extends StatefulWidget {
  const MyOrdersView({
    super.key,
    required this.api,
    required this.store,
    required this.auth,
  });

  final SylibookingApi api;
  final BookingStore store;
  final CustomerAuth auth;

  @override
  State<MyOrdersView> createState() => _MyOrdersViewState();
}

class _MyOrdersViewState extends State<MyOrdersView> {
  List<Order> _orders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    widget.auth.addListener(_load);
  }

  @override
  void dispose() {
    widget.auth.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final orders = widget.auth.isSignedIn
          ? (await widget.api.customerHistory()).orders
          : await _fromThisDevice();
      if (!mounted) return;
      setState(() {
        _orders = orders;
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

  /// One call per remembered reference. Fine for a handful; an account is the
  /// answer for anyone with more than that.
  Future<List<Order>> _fromThisDevice() async {
    final references = await widget.store.orderReferences();
    final orders = <Order>[];
    for (final reference in references) {
      try {
        orders.add(await widget.api.orderByReference(reference));
      } on ApiException {
        // An order the venue deleted is skipped, not fatal.
      }
    }
    orders.sort((a, b) => b.pickupTime.compareTo(a.pickupTime));
    return orders;
  }

  List<Order> get _active =>
      _orders.where((order) => order.status.isOpen).toList();
  List<Order> get _past =>
      _orders.where((order) => !order.status.isOpen).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _Empty(
        icon: Icons.cloud_off,
        title: 'Could not load your orders',
        detail: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    if (_orders.isEmpty) {
      return const _Empty(
        icon: Icons.receipt_long_outlined,
        title: 'No orders yet',
        detail: 'Order ahead from a restaurant and it will show up here, '
            'with its progress while the kitchen works on it.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentInsets(context, maxWidth: ContentWidth.list)
            .copyWith(bottom: 24),
        children: [
          if (_active.isNotEmpty) ...[
            _Heading('Active · ${_active.length}'),
            for (final order in _active) _tile(order),
          ],
          if (_past.isNotEmpty) ...[
            _Heading('Past · ${_past.length}'),
            for (final order in _past) _tile(order),
          ],
        ],
      ),
    );
  }

  Widget _tile(Order order) => OrderTile(
        order: order,
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderTrackingScreen(
                api: widget.api,
                reference: order.reference,
                placed: order,
              ),
            ),
          );
          // It may have moved on while the tracking screen was open.
          await _load();
        },
      );
}

/// One order in the list: where, when, and how far along it is.
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(order.establishmentName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${order.itemCount} '
              '${order.itemCount == 1 ? "item" : "items"} · '
              '${DateFormat('EEE d MMM, HH:mm').format(order.pickupTime)}',
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(child: OrderStatusPill(order: order)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${order.total} GNF',
                    overflow: TextOverflow.ellipsis,
                    style: sylibookingPriceStyle(context, fontSize: 13),
                  ),
                ),
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

/// Where the kitchen has got to, in the customer's words.
class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (label, icon, background, foreground) = switch (order.status) {
      OrderStatus.placed when order.isAwaitingPayment => (
          'Waiting on payment',
          Icons.hourglass_top,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      OrderStatus.placed => (
          'Placed',
          Icons.receipt_long,
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      OrderStatus.preparing => (
          'Being prepared',
          Icons.local_fire_department,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      OrderStatus.ready => (
          'Ready to collect',
          Icons.check_circle,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      OrderStatus.completed => (
          'Collected',
          Icons.done_all,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      OrderStatus.cancelled => (
          'Cancelled',
          Icons.cancel,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      OrderStatus.unknown => (
          'Unknown',
          Icons.help_outline,
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
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
