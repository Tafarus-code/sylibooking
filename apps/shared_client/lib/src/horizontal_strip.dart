import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Lets a horizontal scroller be dragged with a mouse or a stylus.
///
/// Flutter only allows touch to drag a scroll view. On a phone that is right;
/// on a desktop it means a horizontal strip cannot be moved at all — the wheel
/// scrolls the page vertically, there is no visible scrollbar, and whatever
/// sits past the right edge is simply unreachable.
class DragAnywhereScrollBehavior extends MaterialScrollBehavior {
  const DragAnywhereScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

/// A row that scrolls sideways and admits that it does.
///
/// Three things a bare horizontal ListView gets wrong once the content is
/// wider than the screen: it cannot be dragged with a mouse, it shows no
/// scrollbar, and it cuts the last visible item dead at the edge so the result
/// reads as a layout bug rather than as more content.
class HorizontalStrip extends StatefulWidget {
  const HorizontalStrip({
    super.key,
    required this.height,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final double height;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  State<HorizontalStrip> createState() => _HorizontalStripState();
}

class _HorizontalStripState extends State<HorizontalStrip> {
  /// Height reserved under the content for the scrollbar, so the bar never
  /// sits on top of what it is scrolling.
  static const _barBand = 10.0;

  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return SizedBox(
      // Room for the scrollbar underneath, so it never sits on the content.
      height: widget.height + _barBand,
      child: ScrollConfiguration(
        behavior: const DragAnywhereScrollBehavior(),
        child: Scrollbar(
          controller: _controller,
          // Always visible rather than on hover: its job here is to say the
          // row scrolls at all.
          thumbVisibility: true,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                // SingleChildScrollView, not a lazy ListView: everything in
                // the strip should exist whether or not it is currently on
                // screen. A chip that has scrolled off must be merely
                // invisible, not absent — otherwise it disappears from the
                // semantics tree and from find-by-label too.
                SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: widget.padding.copyWith(bottom: _barBand),
                  // The explicit height and stretch are what a horizontal
                  // ListView gave for free: without them the row is only as
                  // tall as its tallest child's intrinsic height, the strip
                  // collapses, and the scrollbar ends up drawn across the
                  // content instead of beneath it.
                  child: SizedBox(
                    height: widget.height,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.children,
                    ),
                  ),
                ),
                // A fade at the trailing edge: the cheapest way to show that
                // an item is cut off on purpose and not by accident.
                Positioned(
                  top: 0,
                  bottom: _barBand,
                  right: 0,
                  child: IgnorePointer(
                    child: _EdgeFade(colour: surface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [colour, colour.withValues(alpha: 0)],
          ),
        ),
      );
}
