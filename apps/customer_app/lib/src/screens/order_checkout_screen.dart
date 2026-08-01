import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
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
    _pickupTime = _slots.first;
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

  /// Collection slots, every fifteen minutes for the next three hours.
  ///
  /// A list of slots rather than a clock or a calendar: a customer collecting
  /// food is choosing between "in half an hour" and "in an hour", not picking
  /// a date. Spinning a time wheel to express that is three gestures too many.
  List<DateTime> get _slots {
    final earliest = DateTime.now().add(const Duration(minutes: 20));
    // Round up to the next quarter, so the list reads 18:15, 18:30, not 18:07.
    final start = DateTime(
      earliest.year,
      earliest.month,
      earliest.day,
      earliest.hour,
      (earliest.minute / 15).ceil() * 15,
    );
    return [
      for (var step = 0; step < 12; step++)
        start.add(Duration(minutes: 15 * step)),
    ];
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
    final l = L.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.checkout)),
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
              l.dishCount(widget.lines.length),
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
                      l.timedToYourBooking,
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
              decoration: InputDecoration(labelText: l.yourName),
              textInputAction: TextInputAction.next,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? l.counterNeedsName
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(labelText: l.phoneNumber),
              keyboardType: TextInputType.phone,
              validator: (value) {
                final phone = (value ?? '').trim();
                if (phone.isEmpty) return l.phoneRequired;
                if (phone.length < 8) return l.phoneTooShort;
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text(l.collectionTime, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _slots)
                  ChoiceChip(
                    label: Text(DateFormat('HH:mm', l.localeName).format(slot)),
                    selected: slot == _pickupTime,
                    onSelected: _submitting
                        ? null
                        : (_) => setState(() => _pickupTime = slot),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(l.payment, style: theme.textTheme.titleSmall),
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
                    title: Text(l.cashOnPickup),
                    subtitle: Text(l.cashOnPickupDetail),
                  ),
                  RadioListTile<PaymentProvider>(
                    value: PaymentProvider.orangeMoney,
                    title: Text(l.orangeMoney),
                    subtitle: Text(l.kitchenStartsWhenPaid),
                  ),
                  RadioListTile<PaymentProvider>(
                    value: PaymentProvider.mtnMoney,
                    title: Text(l.mtnMoney),
                    subtitle: Text(l.kitchenStartsWhenPaid),
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
                    ? l.placing
                    : _provider == PaymentProvider.cashOnArrival
                        ? l.placeOrder
                        : l.payAndOrder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
