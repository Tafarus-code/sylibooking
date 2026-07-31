import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import 'order_tracking_screen.dart';

/// Who is collecting, when, and how it is paid for.
class OrderCheckoutScreen extends StatefulWidget {
  const OrderCheckoutScreen({
    super.key,
    required this.api,
    required this.store,
    required this.establishment,
    required this.lines,
    this.reservationReference,
  });

  final SylibookingApi api;
  final BookingStore store;
  final Establishment establishment;
  final List<CartLine> lines;
  final String? reservationReference;

  @override
  State<OrderCheckoutScreen> createState() => _OrderCheckoutScreenState();
}

class _OrderCheckoutScreenState extends State<OrderCheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  /// Half an hour out, rounded up — the shortest notice a kitchen can work to.
  late DateTime _pickupTime;
  PaymentProvider _provider = PaymentProvider.cashOnArrival;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final soon = DateTime.now().add(const Duration(minutes: 30));
    _pickupTime = DateTime(
      soon.year,
      soon.month,
      soon.day,
      soon.hour,
      soon.minute >= 30 ? 30 : 0,
    ).add(const Duration(minutes: 30));
    _prefill();
  }

  Future<void> _prefill() async {
    final last = await widget.store.lastCustomer();
    if (last == null || !mounted) return;
    setState(() {
      _nameController.text = last.name;
      _phoneController.text = last.phone;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_pickupTime),
      helpText: 'Collection time',
    );
    if (time == null) return;

    var chosen = DateTime(
      _pickupTime.year,
      _pickupTime.month,
      _pickupTime.day,
      time.hour,
      time.minute,
    );
    // A time already gone today means tomorrow: nobody collects in the past.
    if (chosen.isBefore(DateTime.now())) {
      chosen = chosen.add(const Duration(days: 1));
    }
    setState(() => _pickupTime = chosen);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final order = await widget.api.createOrder(
        establishmentId: widget.establishment.id,
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        pickupTime: _pickupTime,
        items: widget.lines,
        paymentProvider: _provider,
        reservationReference: widget.reservationReference,
      );

      await widget.store.rememberOrder(order.reference);
      await widget.store.rememberCustomer(
        _nameController.text.trim(),
        _phoneController.text.trim(),
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(
            api: widget.api,
            reference: order.reference,
            placed: order,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _submitting = false;
        });
      }
    } on ApiUnreachableException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: contentInsets(context, vertical: 16, minHorizontal: 16),
          children: [
            Text(
              widget.establishment.name,
              style: theme.textTheme.titleLarge,
            ),
            Text(
              '${widget.lines.length} '
              '${widget.lines.length == 1 ? "dish" : "dishes"} · collect at '
              'the counter',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.reservationReference != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.event_seat_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Timed to your table booking',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Your name'),
              textInputAction: TextInputAction.next,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'The counter needs a name to call out.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone number'),
              keyboardType: TextInputType.phone,
              validator: (value) {
                final phone = (value ?? '').trim();
                if (phone.isEmpty) return 'A number to reach you on.';
                if (phone.length < 8) return 'That number looks too short.';
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text('Collection time', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat('EEEE HH:mm').format(_pickupTime)),
            ),
            const SizedBox(height: 20),
            Text('Payment', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            RadioGroup<PaymentProvider>(
              groupValue: _provider,
              onChanged: (value) {
                if (_submitting) return;
                setState(() => _provider = value ?? _provider);
              },
              child: Column(
                children: [
                  RadioListTile<PaymentProvider>(
                    value: PaymentProvider.cashOnArrival,
                    title: const Text('Cash on pickup'),
                    subtitle: const Text('Pay at the counter when you collect'),
                  ),
                  RadioListTile<PaymentProvider>(
                    value: PaymentProvider.orangeMoney,
                    title: const Text('Orange Money'),
                    subtitle: const Text(
                      'The kitchen starts once the payment clears',
                    ),
                  ),
                  RadioListTile<PaymentProvider>(
                    value: PaymentProvider.mtnMoney,
                    title: const Text('MTN Mobile Money'),
                    subtitle: const Text(
                      'The kitchen starts once the payment clears',
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting
                    ? 'Placing…'
                    : _provider == PaymentProvider.cashOnArrival
                        ? 'Place order'
                        : 'Pay and order',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
