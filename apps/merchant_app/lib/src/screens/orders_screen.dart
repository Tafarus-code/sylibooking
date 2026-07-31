import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';

/// The kitchen queue: tickets grouped by where they have got to.
///
/// Grouped rather than sorted, because a kitchen works by stage — everything
/// waiting to be started, everything on, everything on the pass — and a single
/// list ordered by time mixes all three together.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Order> _orders = const [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  /// The stages a ticket passes through, in the order the pass reads them.
  static const _stages = [
    (OrderStatus.ready, 'Ready to collect'),
    (OrderStatus.preparing, 'Being prepared'),
    (OrderStatus.placed, 'New orders'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  int? get _venueId => widget.auth.selectedVenueId;

  Future<void> _load() async {
    final venueId = _venueId;
    if (venueId == null) {
      setState(() {
        _loading = false;
        _orders = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final orders = await widget.auth.api.merchantOrders(
        establishmentId: venueId,
      );
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

  Future<void> _advance(Order order, OrderStatus to) async {
    setState(() => _busyId = order.id);
    try {
      final updated = await widget.auth.api.setOrderStatus(order.id, to);
      if (!mounted) return;
      setState(() {
        _orders = [
          for (final existing in _orders)
            if (existing.id == updated.id) updated else existing,
        ];
        _busyId = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      // The server refusing is the interesting case — an unpaid mobile money
      // order, or a stage someone else already moved past.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _cancel(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text(
          '${order.customerName} will not be able to collect it, and nothing '
          'will be owed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _advance(order, OrderStatus.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh the queue',
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load the queue',
        detail: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    if (_venueId == null) {
      return const _EmptyState(
        icon: Icons.storefront_outlined,
        title: 'No venue selected',
        detail: 'Pick a venue to see its kitchen queue.',
      );
    }

    final open = _orders.where((order) => order.status.isOpen).toList();
    if (open.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Nothing in the queue',
        detail: 'Orders placed for today land here as they come in.',
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: contentInsets(
        context,
        maxWidth: ContentWidth.list,
      ).copyWith(bottom: 24),
      children: [
        for (final (stageStatus, label) in _stages)
          ..._stage(
            label,
            open.where((order) => order.status == stageStatus).toList(),
          ),
      ],
    );
  }

  List<Widget> _stage(String label, List<Order> orders) {
    if (orders.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          '$label · ${orders.length}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final order in orders)
        OrderTicket(
          order: order,
          busy: _busyId == order.id,
          onAdvance: () => _advance(order, order.nextStatus),
          onCancel: () => _cancel(order),
        ),
    ];
  }
}

/// One kitchen ticket: who, when, what, and the one button that moves it on.
class OrderTicket extends StatelessWidget {
  const OrderTicket({
    super.key,
    required this.order,
    required this.busy,
    required this.onAdvance,
    required this.onCancel,
  });

  final Order order;
  final bool busy;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;

  String get _advanceLabel => switch (order.status) {
        OrderStatus.placed => 'Start preparing',
        OrderStatus.preparing => 'Mark ready',
        OrderStatus.ready => 'Collected',
        _ => 'Move on',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.customerName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  DateFormat('HH:mm').format(order.pickupTime),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (order.isForATable) ...[
                  Icon(
                    Icons.event_seat_outlined,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'At their table',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Text(' · ', style: theme.textTheme.bodySmall),
                ],
                Flexible(
                  child: Text(
                    order.customerPhone,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final line in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${line.quantity}×',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(child: Text(line.menuItemName)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // Both halves flex: "Paid (MTN Mobile Money)" next to a six-figure
            // total does not fit across a 360dp phone otherwise.
            Row(
              children: [
                Flexible(child: _PaymentChip(order: order)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${order.total} GNF',
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (!order.canAdvance && order.isAwaitingPayment) ...[
              const SizedBox(height: 8),
              Text(
                'Waiting on the ${order.paymentProviderDisplay} payment. '
                'The kitchen cannot start until it clears.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 4),
            // Wrap, not a Row: "Cancel" beside "Start preparing" is wider than
            // a 360dp card, and a second line is better than a clipped button.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: busy ? null : onCancel,
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy || !order.canAdvance ? null : onAdvance,
                  child: Text(_advanceLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cash or mobile money, and whether the money has actually landed.
class _PaymentChip extends StatelessWidget {
  const _PaymentChip({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (label, icon, background, foreground) = switch (order) {
      _ when order.isPaid => (
          'Paid (${order.paymentProviderDisplay})',
          Icons.check_circle,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      _ when order.isAwaitingPayment => (
          'Unpaid',
          Icons.hourglass_top,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      _ => (
          'Cash on pickup',
          Icons.local_atm,
          Colors.transparent,
          scheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: background == Colors.transparent
            ? Border.all(color: scheme.outlineVariant)
            : null,
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
          padding: contentInsets(context, minHorizontal: 32).copyWith(
            top: 72,
            bottom: 32,
          ),
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
