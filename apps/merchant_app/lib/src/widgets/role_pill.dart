import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../labels.dart';

/// What somebody is allowed to do here, said in one word.
///
/// Deliberately not [StatusBadge], and deliberately not its colours. A status
/// answers "what happened to this booking"; a role answers "who is this
/// person". They appear on different screens for different reasons, and
/// giving a role the green that means *paid* would invite a merchant to read
/// a staff list as a payment list for the half-second before they focus.
///
/// The three colours carry meaning in their own right: owner takes the warm
/// accent family because an owner is the account that can give the venue
/// away; manager takes the same blue as a completed reservation, a settled
/// and unremarkable state; staff takes the neutral stone of a thing that has
/// not been acted on.
///
/// Only the owner pill moved with the Indigo Ledger recolour — it was the
/// ember family, and ember is no longer in this app. Manager and staff did
/// not: their blue and stone are borrowed from the status vocabulary, which
/// is fixed by design, and a role list read beside an order list should keep
/// using one language for "settled" and "not yet touched".
class RolePill extends StatelessWidget {
  const RolePill({super.key, required this.role});

  final MerchantRole role;

  static const _palettes = <MerchantRole, (Color, Color)>{
    // Copper's own tint, replacing the ember pair. 6.32:1 on its background.
    MerchantRole.owner: (Color(0xFFF6E7D8), Color(0xFF7A4718)),
    MerchantRole.manager: (Color(0xFFE3EAF2), Color(0xFF2F5B8A)),
    MerchantRole.staff: (Color(0xFFEDEAE0), Color(0xFF6B6656)),
  };

  static Color backgroundOf(MerchantRole role) =>
      _palettes[role]?.$1 ?? const Color(0xFFEDEAE0);
  static Color foregroundOf(MerchantRole role) =>
      _palettes[role]?.$2 ?? const Color(0xFF6B6656);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundOf(role),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        role.name(L.of(context)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: foregroundOf(role),
        ),
      ),
    );
  }
}
