import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../labels.dart';
import 'payment_badge.dart';

/// One booking, with the actions the merchant can still take on it.
class ReservationCard extends StatelessWidget {
  const ReservationCard({
    super.key,
    required this.reservation,
    required this.onConfirm,
    required this.onCancel,
    required this.onComplete,
    this.onTap,
    this.busy = false,
  });

  final Reservation reservation;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  /// Marks the guests as arrived, which closes the booking.
  final VoidCallback onComplete;

  /// Opens the detail view, where the reference and amount live.
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);
    final time = DateFormat.Hm().format(reservation.dateTime);
    final isPending = reservation.status == ReservationStatus.pending;
    // The server refuses to confirm an unpaid mobile money booking, so offer
    // the button greyed rather than absent — a missing button looks like a
    // bug, a disabled one with a reason explains itself.
    final canConfirm = isPending && reservation.canConfirm;
    final blockedByPayment = isPending && !reservation.canConfirm;
    final canCancel = reservation.status.isOpen;
    // Offered only once the sitting has begun: nobody has arrived for a
    // table that is not due yet, and the server refuses it anyway.
    final canComplete = reservation.status.isOpen &&
        reservation.dateTime.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(time, style: theme.textTheme.titleLarge),
                    Text(
                      DateFormat.MMMEd().format(reservation.dateTime),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reservation.customerName,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${reservation.spaceName} · '
                        '${l.guestCount(reservation.partySize)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        reservation.customerPhone,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: reservation.status),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: PaymentBadge(reservation: reservation),
            ),
            if (blockedByPayment) ...[
              const SizedBox(height: 6),
              Text(
                l.cannotConfirmUntilPaymentClears,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (isPending || canCancel) ...[
              const SizedBox(height: 8),
              // Wrap, not a Row: "Cancel", "Mark arrived" and "Confirm" on
              // one line is wider than a 360dp card, and a second line beats
              // a clipped button.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (canCancel)
                    TextButton.icon(
                      onPressed: busy ? null : onCancel,
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(l.cancel),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  if (canComplete)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onComplete,
                      icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                      label: Text(l.markArrived),
                    ),
                  if (isPending)
                    FilledButton.icon(
                      onPressed: (busy || !canConfirm) ? null : onConfirm,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(l.confirm),
                    ),
                ],
              ),
            ],
          ],
        ),
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
