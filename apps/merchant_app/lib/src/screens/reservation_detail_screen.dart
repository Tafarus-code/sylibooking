import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../labels.dart';
import '../widgets/payment_badge.dart';

/// One booking in full, for when the list is not enough.
///
/// Exists mainly for reconciliation: when a customer says they paid and the
/// merchant cannot see it, the provider reference and amount are what settle
/// the argument. Both are copyable, because they get read out over the phone
/// or pasted into a provider's dashboard.
class ReservationDetailScreen extends StatelessWidget {
  const ReservationDetailScreen({super.key, required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);
    final payment = reservation.payment;

    return Scaffold(
      appBar: AppBar(title: Text(l.reservationTitle)),
      body: ListView(
        padding: contentInsets(context, vertical: 16, minHorizontal: 16),
        children: [
          Text(reservation.customerName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            reservation.establishmentName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatusChip(status: reservation.status),
              const SizedBox(width: 8),
              Flexible(
                child: PaymentBadge(reservation: reservation, compact: false),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Section(
            title: l.sectionBooking,
            rows: [
              (
                l.rowWhen,
                '${DateFormat.yMMMEd().format(reservation.dateTime)} · '
                    '${DateFormat.Hm().format(reservation.dateTime)}',
                false,
              ),
              (l.rowSpace, reservation.spaceName, false),
              (l.rowParty, l.guestCount(reservation.partySize), false),
              (l.rowPhone, reservation.customerPhone, true),
              if (reservation.reference.isNotEmpty)
                (l.rowReference, reservation.reference, true),
            ],
          ),
          const SizedBox(height: 16),
          if (payment == null)
            _Section(
              title: l.sectionPayment,
              rows: [
                (l.rowMethod, l.cashOnArrival, false),
                (l.rowTaken, l.nothingYetSettledAtVenue, false),
              ],
            )
          else
            _Section(
              title: l.sectionPayment,
              rows: [
                (l.rowMethod, payment.providerDisplay, false),
                (l.rowAmount, l.amountGnf(payment.amount), true),
                (l.rowStatus, payment.statusDisplay, false),
                if (payment.providerReference case final ref?)
                  (l.rowProviderReference, ref, true),
              ],
            ),
          if (reservation.isAwaitingPayment) ...[
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
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.cannotConfirmUntilPaymentClearsLong,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;

  /// (label, value, copyable)
  final List<(String, String, bool)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            for (final (label, value, copyable) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: SelectableText(value)),
                    if (copyable)
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        visualDensity: VisualDensity.compact,
                        tooltip: L.of(context).copyField(label),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: value));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  L.of(context).fieldCopied(label),
                                ),
                              ),
                            );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReservationStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (status) {
      ReservationStatus.pending => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      ReservationStatus.confirmed => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      ReservationStatus.cancelled => (
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      ReservationStatus.completed => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      // Neutral ground with error-coloured text: a missed booking did not
      // happen, like a cancelled one, but nobody chose it — so it reads as
      // distinct from the filled error a cancellation gets.
      ReservationStatus.noShow => (
          scheme.surfaceContainerHighest,
          scheme.error,
        ),
      ReservationStatus.unknown => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };
    final label = status.label(L.of(context));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
