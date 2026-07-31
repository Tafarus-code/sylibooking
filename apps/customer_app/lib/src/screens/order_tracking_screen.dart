import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

/// Where the order has got to: placed, preparing, ready.
///
/// Polls while it is on screen, because the kitchen moving an order along is
/// the one piece of news a waiting customer actually wants.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({
    super.key,
    required this.api,
    required this.reference,
    this.placed,
  });

  final SylibookingApi api;
  final String reference;

  /// The order as it came back from creation, so the screen has something to
  /// show before the first refresh lands.
  final Order? placed;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Order? _order;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _order = widget.placed;
    _refresh();
    // Slow enough not to hammer the server, quick enough that "Ready" reaches
    // someone standing outside the restaurant.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final order = await widget.api.orderByReference(widget.reference);
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
      });
      // Nothing more will change once it is finished either way.
      if (!order.status.isOpen) _poll?.cancel();
    } on ApiException catch (e) {
      if (mounted && _order == null) setState(() => _error = e.message);
    } on ApiUnreachableException catch (e) {
      if (mounted && _order == null) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _order;

    return Scaffold(
      appBar: AppBar(title: const Text('Your order')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: contentInsets(context, vertical: 16, minHorizontal: 16),
          children: [
            if (order == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Text(_error!, textAlign: TextAlign.center),
                ),
              )
            else ...[
              Text(order.establishmentName, style: theme.textTheme.titleLarge),
              Text(
                'Collect at ${DateFormat('EEEE HH:mm').format(order.pickupTime)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _Timeline(status: order.status),
              if (order.isAwaitingPayment) ...[
                const SizedBox(height: 16),
                _Notice(
                  icon: Icons.hourglass_top,
                  text: 'Waiting for your ${order.paymentProviderDisplay} '
                      'payment. The kitchen starts once it clears.',
                ),
              ],
              if (order.status == OrderStatus.cancelled) ...[
                const SizedBox(height: 16),
                _Notice(
                  icon: Icons.cancel_outlined,
                  text: 'This order was cancelled. Nothing is owed.',
                ),
              ],
              const SizedBox(height: 24),
              Text('What you ordered', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final line in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text('${line.quantity}×  '),
                      Expanded(child: Text(line.menuItemName)),
                      Text('${line.lineTotal} GNF'),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('Total', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    '${order.total} GNF',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.paymentProviderDisplay,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placed → Preparing → Ready, with where it has got to marked.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.status});

  final OrderStatus status;

  static const _steps = [
    (OrderStatus.placed, 'Placed', 'The restaurant has your order'),
    (OrderStatus.preparing, 'Preparing', 'It is being cooked'),
    (OrderStatus.ready, 'Ready', 'Collect it at the counter'),
  ];

  int get _reached => switch (status) {
        OrderStatus.placed => 0,
        OrderStatus.preparing => 1,
        OrderStatus.ready => 2,
        OrderStatus.completed => 2,
        _ => -1,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        for (final (index, step) in _steps.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Icon(
                    index <= _reached
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: index <= _reached
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  if (index < _steps.length - 1)
                    Container(
                      width: 2,
                      height: 28,
                      color: index < _reached
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.$2,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: index <= _reached
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      step.$3,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
