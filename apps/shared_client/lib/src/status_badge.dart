import 'package:flutter/material.dart';

/// The fixed vocabulary of statuses the two apps may show.
///
/// A closed set on purpose. Statuses are read at a glance, down a list, in a
/// dim room — so the same thing has to look the same everywhere, and a screen
/// must not be able to invent a colour for a state it happens to care about.
/// Adding a value here is a deliberate act; picking a colour at a call site is
/// not possible at all.
///
/// Two pairs are worth explaining because they look like duplicates:
///
///   * [orderCompleted] and [reservationCompleted] are deliberately different
///     colours. A collected order and a sitting that happened answer different
///     questions, and a merchant scanning a mixed list should never mistake
///     one for the other. The blue is not an oversight.
///   * [paid], [orderReady] and [orderCompleted] share the same green because
///     they share the same meaning to whoever is reading: this one is settled,
///     nothing is owed and nothing is pending.
enum StatusTone {
  /// Money is in.
  paid,

  /// Confirmed booking — settled enough to expect them.
  confirmed,

  /// Paying on arrival. Nothing is owed yet, and that is fine.
  cash,

  /// Money is owed and has not arrived.
  unpaid,

  /// The table was held and nobody came.
  noShow,

  /// A sitting that happened. Its own colour — see the class doc.
  reservationCompleted,

  /// Ordered, kitchen has not started.
  orderPlaced,

  /// Kitchen is on it.
  orderPreparing,

  /// Waiting on the counter.
  orderReady,

  /// Collected.
  orderCompleted,
}

/// The two colours a tone resolves to. Taken verbatim from the design file's
/// badge block rather than derived from the colour scheme: this vocabulary is
/// shared across both apps and must survive a venue's own branding being
/// layered over the screen it sits on.
typedef _Palette = ({Color background, Color foreground});

const _settled = (background: Color(0xFFE3F2E9), foreground: Color(0xFF1F6B44));
const _owed = (background: Color(0xFFFBEAE8), foreground: Color(0xFFA8453A));

const Map<StatusTone, _Palette> _palettes = {
  StatusTone.paid: _settled,
  StatusTone.confirmed: _settled,
  StatusTone.orderReady: _settled,
  StatusTone.orderCompleted: _settled,
  StatusTone.cash: (
    background: Color(0xFFF3EEE0),
    foreground: Color(0xFF8A6D2A),
  ),
  StatusTone.unpaid: _owed,
  StatusTone.noShow: _owed,
  StatusTone.orderPlaced: (
    background: Color(0xFFEDEAE0),
    foreground: Color(0xFF6B6656),
  ),
  StatusTone.orderPreparing: (
    background: Color(0xFFFBF0DC),
    foreground: Color(0xFF8A5C1C),
  ),
  StatusTone.reservationCompleted: (
    background: Color(0xFFE3EAF2),
    foreground: Color(0xFF2F5B8A),
  ),
};

/// One state of one thing, said in two words and a colour.
///
/// The label is passed in rather than derived, because the words are localised
/// and this package has no catalogue of its own. The colour is not passed in,
/// for the reason in [StatusTone].
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final StatusTone tone;

  /// Optional, and worth using on the merchant's dense lists: colour alone
  /// fails anyone with a colour vision deficiency, and these are scanned fast.
  final IconData? icon;

  /// The colours this tone resolves to, for anything that needs to match a
  /// badge without being one — a bar, a dot in a legend.
  static Color backgroundOf(StatusTone tone) => _palettes[tone]!.background;
  static Color foregroundOf(StatusTone tone) => _palettes[tone]!.foreground;

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[tone]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: palette.foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: palette.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
