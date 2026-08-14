import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';

/// The receipt.
///
/// A cash booking is a request the venue still has to accept. A booking paid
/// by mobile money is already confirmed — unless the payment has not settled
/// yet, in which case this screen polls until it does.
class BookingConfirmedScreen extends StatefulWidget {
  const BookingConfirmedScreen({
    super.key,
    required this.api,
    required this.reservation,
    required this.establishment,
  });

  final SylibookingApi api;
  final Reservation reservation;
  final Establishment establishment;

  @override
  State<BookingConfirmedScreen> createState() => _BookingConfirmedScreenState();
}

class _BookingConfirmedScreenState extends State<BookingConfirmedScreen> {
  static const _pollInterval = Duration(seconds: 3);
  static const _maxPolls = 10;

  late Reservation _reservation = widget.reservation;
  Payment? _payment;
  Timer? _poll;
  int _polls = 0;
  bool _gaveUp = false;

  @override
  void initState() {
    super.initState();
    _payment = widget.reservation.payment;
    if (_needsPolling) _startPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Only a mobile money payment that has not settled is worth waiting on.
  bool get _needsPolling {
    final payment = _payment;
    return payment != null && !payment.status.isSettled;
  }

  void _startPolling() {
    _poll = Timer.periodic(_pollInterval, (_) async {
      if (!mounted) return;
      if (_polls >= _maxPolls) {
        // Stop pestering the server; the booking still exists and My bookings
        // will show the outcome whenever the customer next looks.
        _poll?.cancel();
        if (mounted) setState(() => _gaveUp = true);
        return;
      }
      _polls++;

      try {
        final result =
            await widget.api.paymentStatus(widget.reservation.reference);
        if (!mounted) return;
        setState(() {
          _reservation = result.reservation;
          _payment = result.payment;
        });
        if (!_needsPolling) _poll?.cancel();
      } on ApiException {
        // Transient; the next tick tries again.
      } on ApiUnreachableException {
        // Same.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);
    final payment = _payment;
    final failed = payment?.status == PaymentStatus.failed;
    final settling = _needsPolling && !_gaveUp;
    final venue = widget.establishment.name;

    final (icon, colour, headline, blurb) = switch (payment?.status) {
      null => (
          Icons.check_circle,
          theme.colorScheme.primary,
          l.requestSent,
          l.willConfirmShortly(venue, _reservation.customerPhone),
        ),
      PaymentStatus.completed => (
          Icons.check_circle,
          theme.colorScheme.primary,
          l.tableConfirmed,
          l.paidAndConfirmed(venue),
        ),
      PaymentStatus.failed => (
          Icons.error_outline,
          theme.colorScheme.error,
          l.paymentDidNotGoThrough,
          l.stillHeldAsRequest(venue),
        ),
      _ => (
          Icons.hourglass_top,
          theme.colorScheme.tertiary,
          _gaveUp ? l.stillWaitingOnPayment : l.waitingForPaymentTitle,
          _gaveUp ? l.notComeThroughYet : l.approveOnYourPhone,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l.booked),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: contentInsets(context, vertical: 24, minHorizontal: 24),
        children: [
          const SizedBox(height: 16),
          if (settling)
            const Center(
              child: SizedBox(
                height: 72,
                width: 72,
                child: CircularProgressIndicator(),
              ),
            )
          else
            Icon(icon, size: 72, color: colour),
          const SizedBox(height: 16),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            blurb,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l.bookingLabel, style: theme.textTheme.labelLarge),
                      Text(
                        '#${_reservation.id}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _Row(
                    'When',
                    '${DateFormat.yMMMEd().format(_reservation.dateTime)} · '
                        '${DateFormat.Hm().format(_reservation.dateTime)}',
                  ),
                  _Row('Party', '${_reservation.partySize}'),
                  _Row('Space', _reservation.spaceName),
                  _Row('Name', _reservation.customerName),
                  _Row('Status', _reservation.statusDisplay),
                  if (_reservation.reference.isNotEmpty)
                    _Row(
                      l.reference,
                      // Short enough to read down the phone, and the venue can
                      // find the booking from it in the admin.
                      _reservation.reference.split('-').first.toUpperCase(),
                    ),
                  if (payment != null) ...[
                    const Divider(height: 24),
                    _Row(l.paidWith, payment.providerDisplay),
                    _Row('Amount', '${payment.amount} GNF'),
                    _Row('Payment', payment.statusDisplay),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: failed
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    switch (payment?.status) {
                      null => 'Pay on arrival.',
                      PaymentStatus.completed =>
                        'Deposit paid. Settle the rest at the venue.',
                      PaymentStatus.failed =>
                        'Nothing was charged. Pay on arrival instead.',
                      _ => 'Waiting for the payment to clear.',
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
