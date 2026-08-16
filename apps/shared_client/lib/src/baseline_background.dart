/// The painted canvas each app sits on.
///
/// One per baseline, transcribed from the CSS in the final-direction document:
/// a flat ground, a linear gradient over it, a dot or weave texture, and two
/// or three radial glows on top. They are the reason both baseline themes set
/// `scaffoldBackgroundColor` to transparent — the canvas goes behind the whole
/// app, once, and every Scaffold lets it through.
///
/// **Painted once, not per frame.** Each is a [CustomPaint] whose painter
/// never reports a repaint, inside a [RepaintBoundary], so the layer is
/// rasterised on the first frame and reused until the window changes size. A
/// list scrolling in front of it costs nothing.
///
/// See the CSS-to-Flutter notes at the foot of this file for the two places
/// the translation is an approximation rather than a transcription.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'baseline_theme.dart';

/// The customer app's canvas. Palette: Ember Vivid — "golden hour".
///
/// The darkened version, not the first near-white draft: at the lighter
/// weight the ivory cards had nothing to sit against and the whole screen
/// read as one surface.
///
/// **Light on purpose.** Everything the customer app paints on top of this is
/// dark — [CustomerBaselineTokens.deepwood] at 11.00:1 on the ground, and
/// better on the two lighter gradient stops. That relationship is asserted in
/// `contrast_test.dart` rather than left to hold by luck, which is exactly
/// how the merchant canvas came to be unreadable.
class CustomerBaselineBackground extends StatelessWidget {
  const CustomerBaselineBackground({super.key});

  /// The flat ground under every layer.
  static const ground = Color(0xFFE9D6AE);

  /// The three stops of the base linear gradient, at 0%, 50% and 100%.
  static const gradientStops = <Color>[
    Color(0xFFF2E4C4),
    Color(0xFFE9D6AE),
    Color(0xFFDDC594),
  ];

  /// The darkest thing the canvas can be, for anything checking legibility
  /// against the worst case rather than the average one.
  static const darkestStop = Color(0xFFDDC594);

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
        child: CustomPaint(
          painter: _CustomerCanvasPainter(),
          child: SizedBox.expand(),
        ),
      );
}

/// The merchant app's canvas. Palette: Ember Professional.
///
/// Deepwood falling to near-black on the diagonal, an amber glow top right, a
/// palm-green counterpoint bottom left, and a fine diagonal weave over it.
/// The background that was approved before any indigo attempt.
///
/// **Dark, and nothing dark is ever painted on it.** That is not a property
/// of these colours — the indigo canvas that replaced this one was the same
/// shape, and what made it unreadable was content standing on it rather than
/// on a surface of its own. [merchantBaselineContentGround] is what keeps
/// that from being possible; this stays the ground for chrome.
class MerchantBaselineBackground extends StatelessWidget {
  const MerchantBaselineBackground({super.key});

  static const ground = Color(0xFF0C1D16);

  static const gradientStops = <Color>[
    Color(0xFF12271F),
    Color(0xFF0C1D16),
    Color(0xFF06110C),
  ];

  /// The darkest thing the canvas can be, for anything measuring the worst
  /// case rather than the average one.
  static const darkestStop = Color(0xFF06110C);

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
        child: CustomPaint(
          painter: _MerchantCanvasPainter(),
          child: SizedBox.expand(),
        ),
      );
}

/// One radial glow, as the CSS writes them: a centre in fractions of the box,
/// a colour, and the fraction of the way to the farthest corner at which it
/// reaches transparent.
class _Glow {
  const _Glow(this.x, this.y, this.colour, this.extent);

  final double x;
  final double y;
  final Color colour;
  final double extent;
}

void _paintGlows(Canvas canvas, Size size, List<_Glow> glows) {
  // CSS measures a radial-gradient's extent along the ray to the farthest
  // corner. Flutter's RadialGradient.radius is a fraction of the *shortest
  // side*, which on a 360x900 phone is less than half as far — so the radius
  // is computed here in pixels instead, against the same corner CSS uses.
  for (final glow in glows) {
    final centre = Offset(size.width * glow.x, size.height * glow.y);
    final farthest = math.sqrt(
      math.pow(math.max(centre.dx, size.width - centre.dx), 2) +
          math.pow(math.max(centre.dy, size.height - centre.dy), 2),
    );
    final radius = farthest * glow.extent;
    if (radius <= 0) continue;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          radius,
          [glow.colour, glow.colour.withValues(alpha: 0)],
        ),
    );
  }
}

/// A grid of single-pixel dots, as the CSS texture layer.
///
/// One `drawPoints` call rather than a loop of `drawCircle`: the grid is a few
/// thousand points on a phone, and this is the difference between a canvas
/// that rasterises instantly and one that visibly hitches on first paint.
void _paintDots(Canvas canvas, Size size, Color colour, double spacing) {
  final points = <Offset>[];
  for (var y = 0.0; y < size.height; y += spacing) {
    for (var x = 0.0; x < size.width; x += spacing) {
      points.add(Offset(x, y));
    }
  }
  canvas.drawPoints(
    ui.PointMode.points,
    points,
    Paint()
      ..color = colour
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square,
  );
}

class _CustomerCanvasPainter extends CustomPainter {
  const _CustomerCanvasPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = CustomerBaselineBackground.ground);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          // Late afternoon: the light falls from the top, a little to one
          // side, and the bottom of the screen is where the shadow gathers.
          begin: Alignment(-0.2, -1),
          end: Alignment(0.2, 1),
          colors: CustomerBaselineBackground.gradientStops,
          stops: [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    // Paper grain. Deepwood at a twentieth, which is a texture rather than a
    // tint — at full strength it would eat into the contrast the cards need.
    _paintDots(canvas, size, const Color(0x0D12271F), 5);

    // The amber glow above, the two counterpoints below. Painted in reverse
    // of how the CSS lists them, so the ember is the layer nearest the eye.
    _paintGlows(canvas, size, const [
      _Glow(0.06, 0.92, Color(0x1FA8453A), 0.38),
      _Glow(0.94, 0.78, Color(0x243E8A63), 0.40),
      _Glow(0.50, -0.06, Color(0x4DD98E2B), 0.48),
    ]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MerchantCanvasPainter extends CustomPainter {
  const _MerchantCanvasPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = MerchantBaselineBackground.ground);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          // Diagonal: deepwood at the top left, near-black at the bottom
          // right, which is the fall the original document draws.
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: MerchantBaselineBackground.gradientStops,
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    _paintWeave(canvas, size);

    _paintGlows(canvas, size, const [
      // Palm counterpoint, bottom left.
      _Glow(0.06, 0.92, Color(0x2B1F6B44), 0.44),
      // Amber, top right, and the one the eye is meant to find.
      _Glow(0.88, 0.08, Color(0x40D98E2B), 0.46),
    ]);
  }

  /// The fine diagonal weave: one pixel on, seven off, at 135°.
  void _paintWeave(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x04FFFFFF)
      ..strokeWidth = 1;
    const spacing = 8.0;
    for (var offset = -size.height; offset < size.width; offset += spacing) {
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Frosted glass, for the two places the customer app is allowed to use it.
///
/// **The search bar and the bottom navigation, and nothing else.** A blur
/// reads the pixels behind it on every frame it is composited, so putting one
/// behind a scrolling list means re-blurring the whole list as it moves. The
/// two places it is used here are both fixed: they do not scroll, and what is
/// behind them is the static canvas.
///
/// The merchant app never uses this at all — its tablet split view scrolls two
/// panes at once, and a blurred ground behind them is a cost paid on every
/// frame for a effect nobody is looking at.
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.tint,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// The veil over the blur. Without one the blur alone is not enough to make
  /// text on top legible against an arbitrary canvas.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final veil = tint ??
        CustomerBaselineTokens.ivory.withValues(alpha: 0.82);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: veil,
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Where the CSS did not map cleanly.
//
// 1. Radial extent. CSS measures a radial-gradient to the farthest corner;
//    Flutter's RadialGradient.radius is a fraction of the shortest side. Taken
//    literally, every glow would be less than half its intended size on a tall
//    phone. _paintGlows computes the radius in pixels against the same corner
//    CSS uses, so the glows read as they do in the browser.
//
// 2. Gradient angle. CSS 170deg/165deg is an angle; Flutter takes two
//    alignments. The pairs here reproduce the direction, but the gradient line
//    is scaled to the box rather than to the angle's own length, so the stops
//    land fractionally differently on a very wide window. Invisible at any
//    size either app is used at.
// ---------------------------------------------------------------------------
