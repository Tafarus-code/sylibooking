import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

/// How a booking is being paid, at a glance.
///
/// Built to be scanned down a full day's list rather than read one row at a
/// time, so the three states carry different colour *and* a different icon —
/// colour alone would fail anyone with a colour vision deficiency, and these
/// are read fast in a dim lounge.
///
///   paid           filled, primary   — money is in
///   awaiting/failed  filled, error   — money is owed and has not arrived
///   cash on arrival  outlined, muted — nothing owed yet, and that is fine
class PaymentBadge extends StatelessWidget {
  const PaymentBadge({super.key, required this.reservation, this.compact = true});

  final Reservation reservation;

  /// Compact drops the provider name to fit a list row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = _styleFor(reservation, scheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(6),
        border: style.border == null
            ? null
            : Border.all(color: style.border!, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              compact ? style.shortLabel : style.label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: style.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _BadgeStyle = ({
  String label,
  String shortLabel,
  IconData icon,
  Color background,
  Color foreground,
  Color? border,
});

_BadgeStyle _styleFor(Reservation reservation, ColorScheme scheme) {
  if (reservation.isPaid) {
    final provider = reservation.paymentProviderDisplay.isEmpty
        ? 'mobile money'
        : reservation.paymentProviderDisplay;
    return (
      label: 'Paid ($provider)',
      shortLabel: 'Paid ($provider)',
      icon: Icons.check_circle,
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
      border: null,
    );
  }

  if (reservation.isAwaitingPayment) {
    final failed = reservation.paymentStatus == PaymentStatus.failed;
    return (
      label: failed
          ? 'Payment failed (${reservation.paymentProviderDisplay})'
          : 'Awaiting payment (${reservation.paymentProviderDisplay})',
      shortLabel: failed ? 'Payment failed' : 'Unpaid',
      icon: failed ? Icons.error : Icons.hourglass_top,
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
      border: null,
    );
  }

  // Cash on arrival: nothing is owed yet, so it must not read as a problem.
  return (
    label: 'Cash on arrival',
    shortLabel: 'Cash',
    // local_atm rather than payments_outlined: the latter now marks the
    // Payments tab, and the same glyph meaning two things in one screen is
    // exactly what a scannable badge must not do.
    icon: Icons.local_atm,
    background: Colors.transparent,
    foreground: scheme.onSurfaceVariant,
    border: scheme.outlineVariant,
  );
}
