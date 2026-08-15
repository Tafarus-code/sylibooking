import 'package:flutter/material.dart';

import 'baseline_background.dart';
import 'layout.dart';

/// One destination in the app's primary navigation.
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The app shell: bottom bar on a phone, side rail on anything wider.
///
/// Both apps use this so the two halves of the product behave the same way
/// when a window is resized, and so the switch happens at one threshold rather
/// than at whatever each screen happened to pick.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.frostedBar = false,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  /// Blur the painted canvas behind the bottom bar.
  ///
  /// Opt-in, and only the customer app opts in. Both apps share this shell,
  /// and the merchant app must never blur: its tablet split view scrolls two
  /// panes, and a blur re-reads what is behind it on every composited frame.
  /// Defaulting to false is what stops that arriving by inheritance.
  ///
  /// Ignored at rail widths. A rail is full height beside a scrolling pane,
  /// which is the case the merchant rule is about.
  final bool frostedBar;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutSize.of(context);

    if (!layout.usesRail) {
      final bar = NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        // The blur supplies the surface; a second opaque one over it would
        // make the whole exercise invisible.
        backgroundColor: frostedBar ? Colors.transparent : null,
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      );

      return Scaffold(
        body: body,
        // Extended so the canvas runs under the bar rather than stopping at
        // it — there is nothing to blur otherwise.
        extendBody: frostedBar,
        bottomNavigationBar:
            frostedBar ? FrostedPanel(child: bar) : bar,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          // Labels only once there is room for them: at medium width the rail
          // is competing with the content for the same pixels.
          _Rail(
            destinations: destinations,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            extended: layout == LayoutSize.expanded,
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.extended,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    // A rail is as tall as the window; on a short landscape phone-sized window
    // its destinations do not fit, so it scrolls rather than overflowing.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              extended: extended,
              labelType: extended ? null : NavigationRailLabelType.all,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
