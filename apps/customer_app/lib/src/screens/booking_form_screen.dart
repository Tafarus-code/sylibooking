import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
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

  /// Read here rather than passed in: these are async paths that already
  /// guard `mounted`, and threading a localisation object through each of
  /// them would be noise.
  String get _throttledText => L.of(context).tooManyAttempts;
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
        _error = e.messageOr(whenThrottled: _throttledText);
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
    final l = L.of(context);
    final theme = Theme.of(context);
    final option = widget.option;

    return Scaffold(
      appBar: AppBar(title: Text(l.confirmBooking)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: contentInsets(context, vertical: 16, minHorizontal: 16),
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
                    // Beside the time, because it qualifies the time: this is
                    // how long the table is held if the guests are late.
                    if (widget.establishment.noShowWindowMinutes
                        case final held?) ...[
                      const SizedBox(height: 8),
                      Text(
                        l.tableHeldFor(held),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
              decoration: InputDecoration(
                labelText: l.yourName,
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l.nameRequiredBooking
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              enabled: !_submitting,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l.phoneNumber,
                hintText: '+224 620 00 00 00',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.isEmpty) {
                  return l.phoneRequiredBooking;
                }
                if (digits.length < 8) return l.phoneTooShortBooking;
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
            Text(l.howWouldYouLikeToPay,
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
                  // No longer const: the labels come from the current
                  // language now, not from the source file.
                  for (final choice in [
                    (
                      PaymentProvider.cashOnArrival,
                      l.payOnArrival,
                      l.payOnArrivalDetail,
                      Icons.storefront,
                    ),
                    (
                      PaymentProvider.orangeMoney,
                      l.orangeMoney,
                      l.payDepositDetail,
                      Icons.account_balance_wallet_outlined,
                    ),
                    (
                      PaymentProvider.mtnMoney,
                      l.mtnMoney,
                      l.payDepositDetail,
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
            // Only when a deposit is actually being taken. Said before the
            // money moves, because a forfeiture the customer did not see
            // coming is a dispute rather than a policy.
            if (_paymentProvider != PaymentProvider.cashOnArrival &&
                widget.establishment.depositAmount != null) ...[
              const SizedBox(height: 12),
              // The window is the venue's own — 30 minutes at a restaurant,
              // 90 at a lounge — and the server captures it on the booking at
              // the moment it is made. The old copy said "in that time"
              // without ever saying how long that was, which is the half of
              // the sentence a dispute turns on.
              DepositDisclosure(
                deposit: widget.establishment.depositAmount!,
                windowMinutes: widget.establishment.noShowWindowMinutes ?? 30,
                headline: (deposit, _) => l.depositHeadline(deposit),
                detail: (_, minutes) => l.depositDetail(minutes),
                margin: EdgeInsets.zero,
              ),
            ],
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
                          ? l.payAndReserve
                          : l.reserve,
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
