import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

void main() {
  group('LayoutSize', () {
    test('a phone is compact', () {
      // The commonest widths in this market, and an iPhone SE for the floor.
      for (final width in [320.0, 360.0, 412.0, 599.9]) {
        expect(LayoutSize.forWidth(width), LayoutSize.compact, reason: '$width');
      }
    });

    test('a tablet in portrait is medium', () {
      for (final width in [600.0, 768.0, 834.0, 1023.9]) {
        expect(LayoutSize.forWidth(width), LayoutSize.medium, reason: '$width');
      }
    });

    test('a laptop is expanded', () {
      for (final width in [1024.0, 1280.0, 1440.0, 2560.0]) {
        expect(
          LayoutSize.forWidth(width),
          LayoutSize.expanded,
          reason: '$width',
        );
      }
    });

    test('the rail starts exactly where compact ends', () {
      expect(LayoutSize.forWidth(599.9).usesRail, isFalse);
      expect(LayoutSize.forWidth(600).usesRail, isTrue);
    });

    test('a phone in landscape is not treated as a phone', () {
      // 900x360: the width is what decides, not the device.
      expect(LayoutSize.forWidth(900), LayoutSize.medium);
    });
  });

  group('columnsForWidth', () {
    test('a phone gets one column of venue cards', () {
      expect(columnsForWidth(360), 1);
    });

    test('wider windows get more', () {
      expect(columnsForWidth(834), 3);
      expect(columnsForWidth(1100), 4);
    });

    test('it never returns zero, however narrow', () {
      // A zero-column grid is a crash, not a layout.
      expect(columnsForWidth(0), 1);
      expect(columnsForWidth(100), 1);
    });

    test('it stops at the cap rather than growing forever', () {
      expect(columnsForWidth(4000), 4);
      expect(columnsForWidth(4000, max: 6), 6);
    });

    test('a smaller target card yields more columns at the same width', () {
      // What keeps the menu at two columns on a phone.
      expect(columnsForWidth(328, targetCardWidth: 160), 2);
    });
  });

  group('contentInsets', () {
    Future<EdgeInsets> insetsAt(
      WidgetTester tester,
      double width, {
      double maxWidth = ContentWidth.reading,
      double minHorizontal = 0,
    }) async {
      late EdgeInsets result;
      tester.view.physicalSize = Size(width, 900) * 3.0;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = contentInsets(
                context,
                maxWidth: maxWidth,
                minHorizontal: minHorizontal,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('a phone gets no gutter it cannot afford', (tester) async {
      expect((await insetsAt(tester, 360)).horizontal, 0);
    });

    testWidgets('a narrow window keeps its minimum padding', (tester) async {
      final insets = await insetsAt(tester, 360, minHorizontal: 16);
      expect(insets.left, 16);
    });

    testWidgets('a wide window centres the content', (tester) async {
      final insets = await insetsAt(tester, 1440);

      // 1440 - 720 of content, split evenly.
      expect(insets.left, 360);
      expect(insets.right, 360);
    });

    testWidgets('content never exceeds its measure', (tester) async {
      for (final width in [800.0, 1280.0, 2560.0]) {
        final insets = await insetsAt(tester, width);
        expect(
          width - insets.horizontal,
          lessThanOrEqualTo(ContentWidth.reading),
          reason: '$width',
        );
      }
    });
  });

  group('ContentColumn', () {
    testWidgets('it does not shrink a phone-width child', (tester) async {
      tester.view.physicalSize = const Size(360, 900) * 3.0;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: ContentColumn(child: SizedBox.expand(child: Placeholder())),
        ),
      );

      expect(tester.getSize(find.byType(Placeholder)).width, 360);
    });

    testWidgets('it caps a desktop-width child', (tester) async {
      tester.view.physicalSize = const Size(1440, 900) * 3.0;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: ContentColumn(child: SizedBox.expand(child: Placeholder())),
        ),
      );

      expect(
        tester.getSize(find.byType(Placeholder)).width,
        ContentWidth.reading,
      );
    });
  });

  group('AdaptiveScaffold', () {
    const destinations = [
      AdaptiveDestination(
        label: 'One',
        icon: Icons.looks_one_outlined,
        selectedIcon: Icons.looks_one,
      ),
      AdaptiveDestination(
        label: 'Two',
        icon: Icons.looks_two_outlined,
        selectedIcon: Icons.looks_two,
      ),
    ];

    final tapped = <int>[];

    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tapped.clear();
      tester.view.physicalSize = size * 3.0;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            destinations: destinations,
            selectedIndex: 0,
            onDestinationSelected: tapped.add,
            body: const Center(child: Text('body')),
          ),
        ),
      );
    }

    testWidgets('a phone gets a bottom bar', (tester) async {
      await pumpAt(tester, const Size(360, 900));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a tablet gets a rail with labels but not extended',
        (tester) async {
      await pumpAt(tester, const Size(834, 1112));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(rail.labelType, NavigationRailLabelType.all);
    });

    testWidgets('a desktop window gets an extended rail', (tester) async {
      await pumpAt(tester, const Size(1440, 900));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('the body is shown at every size', (tester) async {
      for (final size in [
        const Size(360, 900),
        const Size(834, 1112),
        const Size(1440, 900),
      ]) {
        await pumpAt(tester, size);
        expect(find.text('body'), findsOneWidget, reason: '$size');
      }
    });

    testWidgets('a short landscape window scrolls the rail rather than '
        'overflowing it', (tester) async {
      // 720x300 — a resized desktop window, too short for a tall rail.
      await pumpAt(tester, const Size(720, 300));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('tapping a destination reports its index at every size',
        (tester) async {
      // The callback has to fire identically whether the tap landed on the
      // bottom bar or the rail — the shell swaps them out underneath.
      for (final size in [
        const Size(360, 900),
        const Size(834, 1112),
        const Size(1440, 900),
      ]) {
        await pumpAt(tester, size);
        await tester.tap(find.text('Two'));
        await tester.pump();

        expect(tapped, [1], reason: '$size');
      }
    });
  });
}
