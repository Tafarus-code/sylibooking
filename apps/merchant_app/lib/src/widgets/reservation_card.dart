import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import 'payment_badge.dart';

/// One booking, with the actions the merchant can still take on it.
class ReservationCard extends StatelessWidget {
  const ReservationCard({
    super.key,
    required this.reservation,
    required this.onConfirm,
    required this.onCancel,
    this.onTap,
    this.busy = false,
  });

  final Reservation reservation;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  /// Opens the detail view, where the reference and amount live.
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat.Hm().format(reservation.dateTime);
    final isPending = reservation.status == ReservationStatus.pending;
    // The server refuses to confirm an unpaid mobile money booking, so offer
    // the button greyed rather than absent — a missing button looks like a
    // bug, a disabled one with a reason explains itself.
    final canConfirm = isPending && reservation.canConfirm;
    final blockedByPayment = isPending && !reservation.canConfirm;
    final canCancel = reservation.status.isOpen;

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
                        '${reservation.partySize} '
                        '${reservation.partySize == 1 ? "guest" : "guests"}',
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
                'Cannot confirm until the payment clears.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (isPending || canCancel) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canCancel)
                    TextButton.icon(
                      onPressed: busy ? null : onCancel,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  if (isPending) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: (busy || !canConfirm) ? null : onConfirm,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Confirm'),
                    ),
                  ],
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
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground) = switch (status) {
      ReservationStatus.pending => (
          'Pending',
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      ReservationStatus.confirmed => (
          'Confirmed',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      ReservationStatus.cancelled => (
          'Cancelled',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      ReservationStatus.completed => (
          'Completed',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      ReservationStatus.unknown => (
          'Unknown',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
