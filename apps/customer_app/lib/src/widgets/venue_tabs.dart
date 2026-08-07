import 'package:flutter/material.dart';

/// The four things there are to know about a venue, one at a time.
///
/// The screen used to stack all four down one scroll: hours, then photos,
/// then the menu, then reviews, then the booking controls. That works when a
/// venue has two menu items and no photos, and stops working the moment one
/// has eighteen — the reviews end up a thousand pixels below the fold and
/// nobody scrolls that far to find out whether a place is any good.
///
/// Underline rather than a filled pill: this is a table of contents for one
/// screen, not a choice between two screens. The filled ember pill is spoken
/// for by SegmentedToggle, which does mean "these are two different things".
class VenueTabs extends StatelessWidget {
  const VenueTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // Scrolls sideways rather than wrapping: four French labels can be
      // wider than a 360dp phone, and a tab row that wraps to two lines
      // stops reading as a row.
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          for (final (index, label) in labels.indexed) ...[
            if (index > 0) const SizedBox(width: 18),
            _Tab(
              label: label,
              selected: index == selectedIndex,
              onTap: () => onSelected(index),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? accent : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
