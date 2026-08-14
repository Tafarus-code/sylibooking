import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import 'payment_badge.dart';

/// One booking, worked beside the day rather than on top of it.
///
/// The tablet half of the desk. Same booking the phone opens as its own
/// screen, laid out for a pane that sits next to the list: a field grid
/// instead of a column of rows, because at this width the eye reads two
/// columns faster than it reads eight lines.
///
/// It takes its actions as nullable callbacks rather than deciding for itself
/// which are allowed. The rules — a pending booking can be confirmed only
/// once its payment cleared, guests can only be marked arrived once the
/// sitting has begun — live where the list already applies them, and having
/// two copies would eventually mean two answers.
class ReservationDetailPane extends StatelessWidget {
  const ReservationDetailPane({
    super.key,
    required this.reservation,
    required this.onConfirm,
    required this.onCancel,
    required this.onComplete,
    this.busy = false,
  });

  final Reservation reservation;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reservation.customerName,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  _Reference(reference: reservation.reference),
                ],
              ),
            ),
            PaymentBadge(reservation: reservation, compact: false),
          ],
        ),
        const SizedBox(height: 16),
        // Two columns. Four facts a merchant checks in the same order every
        // time — when, how many, where, and how long they have.
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 3.4,
          children: [
            _Field(
              label: l.rowWhen,
              value: DateFormat.Hm().format(reservation.dateTime),
              mono: true,
            ),
            _Field(
              label: l.rowParty,
              value: l.guestCount(reservation.partySize),
            ),
            _Field(label: l.rowSpace, value: reservation.spaceName),
            _Field(
              label: l.rowGraceWindow,
              // Captured on the booking when it was made, not read live: a
              // venue that changes its default must not move the deadline on
              // a table somebody already holds.
              value: reservation.noShowAfterMinutes == null
                  ? '—'
                  : l.graceMinutes(reservation.noShowAfterMinutes!),
              mono: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            if (onComplete != null)
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onComplete,
                  child: Text(l.markArrived),
                ),
              ),
            if (onComplete != null && onConfirm != null)
              const SizedBox(width: 10),
            if (onConfirm != null)
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onConfirm,
                  child: Text(l.confirm),
                ),
              ),
            if (onCancel != null) ...[
              if (onComplete != null || onConfirm != null)
                const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onCancel,
                  child: Text(l.cancel),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The booking's reference, and a way to get it onto the clipboard.
///
/// A merchant reads this out on the phone or pastes it into a message; typing
/// a UUID by eye is how the wrong booking gets cancelled.
class _Reference extends StatelessWidget {
  const _Reference({required this.reference});

  final String reference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: reference));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(l.fieldCopied(l.rowReference))),
          );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy, size: 12, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                reference,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sylibookingPriceStyle(context, fontSize: 11).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;

  /// Times and durations are figures; they line up down a column.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono
                ? sylibookingPriceStyle(context, fontSize: 13)
                : theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}
