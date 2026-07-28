import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import 'booking_confirmed_screen.dart';

/// Name, phone, confirm. Payment is on arrival in the MVP.
class BookingFormScreen extends StatefulWidget {
  const BookingFormScreen({
    super.key,
    required this.api,
    required this.store,
    required this.establishment,
    required this.option,
    required this.partySize,
  });

  final SylibookingApi api;
  final BookingStore store;
  final Establishment establishment;
  final TimeOption option;
  final int partySize;

  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  bool _submitting = false;
  String? _error;
  PaymentProvider _paymentProvider = PaymentProvider.cashOnArrival;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final last = await widget.store.lastCustomer();
    if (last == null || !mounted) return;
    setState(() {
      _name.text = last.name;
      _phone.text = last.phone;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final reservation = await widget.api.createReservation(
        spaceId: widget.option.space.id,
        customerName: _name.text.trim(),
        customerPhone: _phone.text.trim(),
        when: widget.option.start,
        partySize: widget.partySize,
        paymentProvider: _paymentProvider,
      );

      await widget.store.remember(reservation.reference);
      await widget.store.rememberCustomer(_name.text.trim(), _phone.text.trim());

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BookingConfirmedScreen(
            api: widget.api,
            reservation: reservation,
            establishment: widget.establishment,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // The usual failure here is someone else taking the slot first.
        _error = e.message;
        _submitting = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final option = widget.option;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm booking')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.establishment.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      icon: Icons.event,
                      label: DateFormat.yMMMMEEEEd().format(option.start),
                    ),
                    _DetailRow(
                      icon: Icons.schedule,
                      label: DateFormat.Hm().format(option.start),
                    ),
                    _DetailRow(
                      icon: Icons.people_outline,
                      label: '${widget.partySize} '
                          '${widget.partySize == 1 ? "guest" : "guests"}',
                    ),
                    _DetailRow(
                      icon: Icons.table_bar,
                      label: '${option.space.name} '
                          '(${option.space.typeDisplay})',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'The venue needs a name for the booking'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              enabled: !_submitting,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+224 620 00 00 00',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.isEmpty) {
                  return 'The venue will call to confirm';
                }
                if (digits.length < 8) return 'That number looks too short';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text('How would you like to pay?',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            RadioGroup<PaymentProvider>(
              groupValue: _paymentProvider,
              onChanged: (value) {
                // RadioGroup requires a handler, so ignore taps mid-submit
                // rather than passing null.
                if (_submitting) return;
                setState(
                  () =>
                      _paymentProvider = value ?? PaymentProvider.cashOnArrival,
                );
              },
              child: Column(
                children: [
                  for (final choice in const [
                    (
                      PaymentProvider.cashOnArrival,
                      'Pay on arrival',
                      'Nothing is charged now. The venue confirms your table.',
                      Icons.storefront,
                    ),
                    (
                      PaymentProvider.orangeMoney,
                      'Orange Money',
                      'Pay a deposit now — your table is confirmed straight '
                          'away.',
                      Icons.account_balance_wallet_outlined,
                    ),
                    (
                      PaymentProvider.mtnMoney,
                      'MTN Mobile Money',
                      'Pay a deposit now — your table is confirmed straight '
                          'away.',
                      Icons.account_balance_wallet_outlined,
                    ),
                  ])
                    RadioListTile<PaymentProvider>(
                      value: choice.$1,
                      title: Row(
                        children: [
                          Icon(choice.$4, size: 18),
                          const SizedBox(width: 8),
                          // Expanded so "MTN Mobile Money" still fits beside
                          // the radio on a 360dp screen.
                          Expanded(child: Text(choice.$2)),
                        ],
                      ),
                      subtitle: Text(
                        choice.$3,
                        style: theme.textTheme.bodySmall,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _paymentProvider.isMobileMoney
                          ? 'Pay and reserve'
                          : 'Reserve',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
          ],
        ),
      );
}
