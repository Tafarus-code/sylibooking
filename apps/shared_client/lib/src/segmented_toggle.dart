import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Two views of the same place, with one of them showing.
///
/// Used for Établissements/Plats on browse, and Réservations/Commandes on both
/// the customer's list and the merchant's desk. Deliberately not Material's
/// SegmentedButton: that widget sizes itself from its labels and clips them
/// when a French word runs long, which is precisely the defect the audit found
/// on the merchant desk. Here each option takes an equal half of the width and
/// the text shrinks to fit rather than losing its last letter.
///
/// It sits on the deepwood app bar rather than on the page, so its own
/// background is the darker deepwood-3 and its labels are ivory — the design
/// file puts it there and the contrast only works in that position.
class SegmentedToggle extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.margin = const EdgeInsets.fromLTRB(16, 10, 16, 0),
  });

  /// Two, in practice. The widget does not forbid three, but the design's
  /// pill only reads as a choice at two or three; past that it wants tabs.
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: SylibookingTokens.deepwoodSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final (index, label) in options.indexed) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: _Option(
                  label: label,
                  selected: index == selectedIndex,
                  onTap: () => onSelected(index),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? SylibookingTokens.ember : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Center(
              // Shrinks rather than clips: "7 prochains jours" losing its last
              // letter reads as a typo, and a merchant cannot tell whether the
              // app is broken or the word is.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? SylibookingTokens.onEmber
                        : SylibookingTokens.ivoryDim,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
