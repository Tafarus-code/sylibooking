import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

void main() {
  group('DragAnywhereScrollBehavior', () {
    test('a mouse can drag, which is the whole point', () {
      // Flutter's default allows touch only, so on a desktop a horizontal
      // strip cannot be moved at all and its overflow is unreachable.
      const behaviour = DragAnywhereScrollBehavior();

      expect(behaviour.dragDevices, contains(PointerDeviceKind.mouse));
      expect(behaviour.dragDevices, contains(PointerDeviceKind.trackpad));
      expect(behaviour.dragDevices, contains(PointerDeviceKind.touch));
    });
  });

  group('HorizontalStrip', () {
    Future<void> pump(
      WidgetTester tester, {
      int items = 12,
      Size size = const Size(360, 900),
    }) async {
      tester.view.physicalSize = size * 3.0;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HorizontalStrip(
              height: 60,
              children: [
                for (var i = 0; i < items; i++)
                  SizedBox(width: 100, child: Center(child: Text('item $i'))),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('content far wider than the screen does not overflow',
        (tester) async {
      // 12 x 100 in a 360 window. It scrolls; it must not throw.
      await pump(tester);

      expect(find.text('item 0'), findsOneWidget);
    });

    testWidgets('it carries a visible scrollbar', (tester) async {
      await pump(tester);

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      // Always on, not on hover: its job is to say the row scrolls at all.
      expect(scrollbar.thumbVisibility, isTrue);
    });

    testWidgets('a mouse drag reaches content that starts off screen',
        (tester) async {
      await pump(tester);

      // 12 items of 100 in a 360 window: the tail starts well past the right
      // edge, and a mouse is all a desktop user has to bring it into view.
      expect(
        tester.getRect(find.text('item 9')).left,
        greaterThan(360),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('item 1')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-700, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.getRect(find.text('item 9')).left, lessThan(360));
    });

    testWidgets('every item exists even when scrolled off', (tester) async {
      await pump(tester);

      // Not a lazy list: a chip that has scrolled out of view must be merely
      // invisible, not gone from the tree and the semantics with it.
      expect(find.text('item 11'), findsOneWidget);
    });

    testWidgets('it reserves room for the scrollbar under the content',
        (tester) async {
      await pump(tester);

      // The strip is taller than its content by the scrollbar's allowance, so
      // the bar never sits on top of what it is scrolling.
      expect(tester.getSize(find.byType(HorizontalStrip)).height, 70);
    });

    testWidgets('children fill the strip and stop above the scrollbar',
        (tester) async {
      await pump(tester);

      // A horizontal ListView stretches its children to the cross axis for
      // free; a Row does not, and without an explicit height the strip
      // collapses to its tallest child and the bar lands across the content.
      // The Center fills the child box, so its rect is the box the strip
      // handed the child — the text inside it is centred and would not be.
      final child = tester.getRect(
        find.ancestor(of: find.text('item 0'), matching: find.byType(Center)),
      );
      final strip = tester.getRect(find.byType(HorizontalStrip));

      expect(child.top, strip.top);
      expect(child.bottom, strip.bottom - 10);
    });

    testWidgets('short content still lays out', (tester) async {
      // One item in a wide window: nothing to scroll, nothing to fade.
      await pump(tester, items: 1, size: const Size(1440, 900));

      expect(find.text('item 0'), findsOneWidget);
    });
  });
}
