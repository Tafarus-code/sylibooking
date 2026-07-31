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
              OrderProgress(status: order.status),
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
                    style: sylibookingPriceStyle(context),
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

/// Placed → Preparing → Ready, across the screen rather than down it.
///
/// Horizontal because there are exactly three steps and they are a journey:
/// the shape itself says "you are here, two to go", which a vertical list of
/// ticks does not.
class OrderProgress extends StatelessWidget {
  const OrderProgress({super.key, required this.status});

  final OrderStatus status;

  static const steps = [
    (OrderStatus.placed, 'Placed'),
    (OrderStatus.preparing, 'Preparing'),
    (OrderStatus.ready, 'Ready'),
  ];

  /// What the customer should be doing about the stage they are at.
  static String captionFor(OrderStatus status) => switch (status) {
        OrderStatus.placed => 'The restaurant has your order',
        OrderStatus.preparing => 'It is being cooked',
        OrderStatus.ready => 'Collect it at the counter',
        OrderStatus.completed => 'Collected. Enjoy it.',
        OrderStatus.cancelled => 'This order was cancelled',
        OrderStatus.unknown => '',
      };

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

    Color colourFor(int index) => index <= _reached
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return Column(
      children: [
        Row(
          children: [
            for (final (index, _) in steps.indexed) ...[
              if (index > 0)
                Expanded(
                  // The connector fills between the dots, so the row stretches
                  // to the screen instead of clustering in the middle.
                  child: Container(height: 3, color: colourFor(index)),
                ),
              Icon(
                index <= _reached
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 26,
                color: index <= _reached
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (index, step) in steps.indexed)
              Expanded(
                child: Text(
                  step.$2,
                  textAlign: switch (index) {
                    0 => TextAlign.start,
                    2 => TextAlign.end,
                    _ => TextAlign.center,
                  },
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight:
                        index == _reached ? FontWeight.w700 : FontWeight.w400,
                    color: index <= _reached
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          captionFor(status),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
