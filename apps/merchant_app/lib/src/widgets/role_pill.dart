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
/// The three colours are the design system's own, and they carry meaning in
/// their own right: owner takes the ember family because an owner is the
/// account that can give the venue away; manager takes the same blue as a
/// completed reservation, a settled and unremarkable state; staff takes the
/// neutral stone of a thing that has not been acted on.
class RolePill extends StatelessWidget {
  const RolePill({super.key, required this.role});

  final MerchantRole role;

  static const _palettes = <MerchantRole, (Color, Color)>{
    MerchantRole.owner: (Color(0xFFFBF0DC), Color(0xFF8A5C1C)),
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
