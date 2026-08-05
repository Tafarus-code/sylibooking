import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';

/// Ringing up an order for somebody standing at the counter.
///
/// Built for one hand and a queue behind the customer. Tapping a dish adds
/// one; tapping it again adds another. No cart to open, no checkout step, no
/// fields to fill in — a name is offered because it is what gets called out
/// when the food is up, and nothing else is asked for at all.
///
/// Staff may do this. The person taking the money is the person entering it,
/// and routing it through a manager is how a queue ends up on a paper pad.
class WalkInOrderScreen extends StatefulWidget {
  const WalkInOrderScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<WalkInOrderScreen> createState() => _WalkInOrderScreenState();
}

class _WalkInOrderScreenState extends State<WalkInOrderScreen> {
  final _name = TextEditingController();

  List<MerchantMenuItem> _menu = const [];
  final Map<int, int> _quantities = {};
  bool _loading = true;
  bool _sending = false;
  String? _error;

  int get _venueId => widget.auth.selectedVenueId!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.auth.api.merchantMenu(_venueId);
      if (!mounted) return;
      setState(() {
        // Only what can actually be sold right now: a sold-out dish on a
        // counter screen is a conversation the server will end with a 400.
        _menu = items.where((item) => item.isAvailable).toList();
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

  double get _total {
    var sum = 0.0;
    for (final item in _menu) {
      final quantity = _quantities[item.id] ?? 0;
      if (quantity == 0) continue;
      sum += (double.tryParse(item.price) ?? 0) * quantity;
    }
    return sum;
  }

  bool get _hasAnything => _quantities.values.any((q) => q > 0);

  void _add(MerchantMenuItem item) {
    setState(() {
      _quantities[item.id] = (_quantities[item.id] ?? 0) + 1;
    });
  }

  void _remove(MerchantMenuItem item) {
    setState(() {
      final left = (_quantities[item.id] ?? 0) - 1;
      if (left <= 0) {
        _quantities.remove(item.id);
      } else {
        _quantities[item.id] = left;
      }
    });
  }

  Future<void> _send() async {
    final l = L.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await widget.auth.api.createWalkInOrder(
        establishmentId: _venueId,
        customerName: _name.text,
        items: [
          for (final entry in _quantities.entries)
            (menuItemId: entry.key, quantity: entry.value),
        ],
      );
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.walkInSent)));
      navigator.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.messageOr(whenThrottled: l.tooManyAttempts);
        _sending = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.walkInTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _menuList(l)),
                // The running total and the one button, pinned: a counter
                // screen should never need scrolling to finish an order.
                Material(
                  elevation: 8,
                  color: theme.colorScheme.surface,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_error != null) ...[
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Text(
                                l.walkInTotal,
                                style: theme.textTheme.titleMedium,
                              ),
                              const Spacer(),
                              Text(
                                l.amountGnf(_total.toStringAsFixed(0)),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: (!_hasAnything || _sending)
                                ? null
                                : _send,
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: _sending
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(l.walkInSend),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _menuList(L l) {
    final theme = Theme.of(context);

    if (_error != null && _menu.isEmpty) {
      return ListView(
        padding: contentInsets(context, minHorizontal: 32)
            .copyWith(top: 72, bottom: 32),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: Text(l.tryAgain)),
        ],
      );
    }

    if (_menu.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l.walkInNoMenu,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final byCategory = <String, List<MerchantMenuItem>>{};
    for (final item in _menu) {
      byCategory.putIfAbsent(item.categoryDisplay, () => []).add(item);
    }

    return ListView(
      padding: contentInsets(context, maxWidth: ContentWidth.list)
          .copyWith(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            l.walkInIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _name,
            enabled: !_sending,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l.walkInName,
              hintText: l.walkInNameHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (!_hasAnything)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l.walkInEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final entry in byCategory.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              entry.key,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final item in entry.value)
            _DishRow(
              item: item,
              quantity: _quantities[item.id] ?? 0,
              onAdd: _sending ? null : () => _add(item),
              onRemove: _sending ? null : () => _remove(item),
            ),
        ],
      ],
    );
  }
}

/// One dish, and how many of it are going in.
class _DishRow extends StatelessWidget {
  const _DishRow({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final MerchantMenuItem item;
  final int quantity;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        // The whole row adds one. A counter is not the place to hunt for a
        // small plus sign.
        onTap: onAdd,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: theme.textTheme.titleSmall),
                    Text(
                      l.amountGnf(item.price),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (quantity > 0) ...[
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$quantity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              IconButton(
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
