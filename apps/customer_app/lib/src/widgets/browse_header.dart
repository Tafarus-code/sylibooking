import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

/// Greeting over a search field, with the one amber glow on this screen.
///
/// The glow is deliberate and singular: used once here, behind the search
/// field, and nowhere else. Repeating it would turn a focal point into noise.
class BrowseHeader extends StatelessWidget {
  const BrowseHeader({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.customerName,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// From the last booking made on this device; customers have no accounts.
  final String? customerName;

  String get _greeting {
    final hour = DateTime.now().hour;
    // Lounges here fill up after dark, so the evening greeting is the one
    // most customers will see.
    if (hour < 12) return 'Bonjour';
    if (hour < 17) return 'Bon après-midi';
    return 'Bonsoir';
  }

  /// Below this the greeting is dropped and only the search field is kept.
  ///
  /// A phone in landscape has about 360dp of height for everything. Spending a
  /// third of it on "Bonsoir, Fatou" pushes the first venue off the screen,
  /// which is the one thing this screen exists to show.
  static const _shortWindow = 500.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (customerName ?? '').trim();
    final firstName = name.isEmpty ? null : name.split(' ').first;
    final short = MediaQuery.sizeOf(context).height < _shortWindow;

    return Stack(
      children: [
        // The glow, behind everything, bleeding off the right edge.
        Positioned(
          right: -60,
          top: -30,
          child: IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SylibookingTokens.ember.withValues(alpha: 0.22),
                    SylibookingTokens.ember.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, short ? 8 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (short)
                // The subtitle carries on alone: it names the screen, which
                // the greeting never did.
                Text(
                  'Find a table',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                )
              else ...[
                Text(
                  firstName == null ? _greeting : '$_greeting, $firstName',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Find a table',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(height: short ? 8 : 14),
              TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: onClear,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontally scrollable filters. Active is filled ember; inactive outlined.
class BrowseFilters extends StatelessWidget {
  const BrowseFilters({
    super.key,
    required this.options,
    required this.isSelected,
    required this.onSelected,
  });

  /// (value, label) pairs; value is opaque to this widget.
  final List<(Object?, String)> options;
  final bool Function(Object? value) isSelected;
  final void Function(Object? value) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 44,
      // SingleChildScrollView, not ListView: a handful of chips, all of which
      // should exist whether or not they are currently on screen — a lazily
      // built row means a filter that has scrolled off is not merely invisible
      // but absent, which breaks find-by-label for tests and semantics alike.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final (value, label) in options)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: Text(label),
                  selected: isSelected(value),
                  onSelected: (_) => onSelected(value),
                  showCheckmark: false,
                  // Filled ember when active, outlined when not.
                  //
                  // The label is onPrimary (white), not dark: dark text on
                  // ember measures about 3.1:1, below the 4.5:1 AA needs.
                  // White on ember is the pairing the presets verify at 4.93:1.
                  selectedColor: theme.colorScheme.primary,
                  backgroundColor: Colors.transparent,
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                    color: isSelected(value)
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: isSelected(value)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
