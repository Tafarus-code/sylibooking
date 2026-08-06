import 'package:flutter/material.dart';

/// How much room the app has to work with.
///
/// Three sizes rather than a device list: a phone in landscape and a small
/// window are the same problem, and asking "is this an iPad" never answers it.
enum LayoutSize {
  /// Phones in portrait. One column, bottom navigation.
  compact,

  /// Tablets in portrait, phones in landscape, half-screen desktop windows.
  medium,

  /// Tablets in landscape, and desktop windows. Navigation rail, wide grids.
  expanded;

  /// The Material window-size-class thresholds, which is where these come from.
  static const mediumFrom = 600.0;
  static const expandedFrom = 1024.0;

  static LayoutSize forWidth(double width) {
    if (width >= expandedFrom) return LayoutSize.expanded;
    if (width >= mediumFrom) return LayoutSize.medium;
    return LayoutSize.compact;
  }

  /// Reads the window, not the widget. For a widget that may be laid out in a
  /// narrow slot on a wide screen, measure the slot with a LayoutBuilder.
  static LayoutSize of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == LayoutSize.compact;

  /// Navigation down the side rather than across the bottom. A bottom bar on a
  /// desktop window is a thumb target where there is no thumb.
  bool get usesRail => this != LayoutSize.compact;
}

/// How wide a column of content is allowed to get.
///
/// Text set across 1600px is unreadable however large the screen: the eye
/// loses the line it was on coming back from the right edge. Beyond these
/// widths the extra space becomes margin, not measure.
class ContentWidth {
  /// Prose and forms — roughly 70 characters at body size.
  static const reading = 720.0;

  /// Lists and grids of cards, which tolerate more width than prose.
  static const list = 1100.0;

  /// Lists on a window wide enough that 1100 leaves acres of nothing.
  ///
  /// A 2560px tablet in landscape gave the merchant's desk a 1100px strip
  /// down the middle and 700px of empty on each side, which reads as a
  /// screen that has not finished loading. Wider cards are not the ideal
  /// answer — the real one is a second column, the day's list beside the
  /// selected booking — but that is a screen to design, not a number to
  /// change, and this stops the desk looking broken in the meantime.
  static const wideList = 1600.0;

  /// The list width for the window this context is in.
  static double listFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 2000 ? wideList : list;
}

/// Centres its child and stops it growing past [maxWidth].
///
/// The single most useful thing on a desktop window: without it every screen
/// built for a phone stretches its rows edge to edge.
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.child,
    this.maxWidth = ContentWidth.reading,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Side padding that centres a scroll view's content on a wide window.
///
/// For a ListView, this does what [ContentColumn] does for a fixed child, but
/// without nesting: the scroll view still fills the window, so the scrollbar
/// stays at the screen edge where a desktop user reaches for it, while the
/// content sits in a readable column.
EdgeInsets contentInsets(
  BuildContext context, {
  double maxWidth = ContentWidth.reading,
  double vertical = 0,
  double minHorizontal = 0,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final gutter = ((width - maxWidth) / 2).clamp(minHorizontal, double.infinity);
  return EdgeInsets.symmetric(horizontal: gutter, vertical: vertical);
}

/// The number of columns a card grid should use at [width].
///
/// Driven by a target card width rather than by breakpoints, so a grid in a
/// narrow pane on a wide screen still gets it right.
int columnsForWidth(
  double width, {
  double targetCardWidth = 260,
  int max = 4,
}) {
  final columns = (width / targetCardWidth).floor();
  return columns.clamp(1, max);
}
