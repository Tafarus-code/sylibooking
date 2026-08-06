import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

/// The three pieces both apps share, and the one rule that matters about
/// each: a badge's colour is a vocabulary and not a choice, a toggle reports
/// which half was tapped, and the deposit box tells the truth about *this*
/// venue's grace period rather than a number somebody typed once.

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

/// The design file's badge block, transcribed. Written out here rather than
/// read from the widget so the test would notice a value being changed on
/// both sides at once.
const expected = <StatusTone, (int, int)>{
  StatusTone.paid: (0xFFE3F2E9, 0xFF1F6B44),
  StatusTone.confirmed: (0xFFE3F2E9, 0xFF1F6B44),
  StatusTone.orderReady: (0xFFE3F2E9, 0xFF1F6B44),
  StatusTone.orderCompleted: (0xFFE3F2E9, 0xFF1F6B44),
  StatusTone.cash: (0xFFF3EEE0, 0xFF8A6D2A),
  StatusTone.unpaid: (0xFFFBEAE8, 0xFFA8453A),
  StatusTone.noShow: (0xFFFBEAE8, 0xFFA8453A),
  StatusTone.orderPlaced: (0xFFEDEAE0, 0xFF6B6656),
  StatusTone.orderPreparing: (0xFFFBF0DC, 0xFF8A5C1C),
  StatusTone.reservationCompleted: (0xFFE3EAF2, 0xFF2F5B8A),
};

void main() {
  group('StatusBadge', () {
    testWidgets('every tone renders the colours the design file names',
        (tester) async {
      for (final entry in expected.entries) {
        await tester.pumpWidget(
          host(StatusBadge(label: 'Payé', tone: entry.key)),
        );

        final box = tester.widget<Container>(
          find.ancestor(
            of: find.text('Payé'),
            matching: find.byType(Container),
          ).first,
        );
        final decoration = box.decoration! as BoxDecoration;
        final text = tester.widget<Text>(find.text('Payé'));

        expect(
          decoration.color,
          Color(entry.value.$1),
          reason: '${entry.key.name} background',
        );
        expect(
          text.style?.color,
          Color(entry.value.$2),
          reason: '${entry.key.name} foreground',
        );
      }
    });

    testWidgets('the vocabulary covers every tone', (tester) async {
      // A tone added without a colour would throw at build rather than fall
      // back to something plausible-looking.
      for (final tone in StatusTone.values) {
        expect(expected.containsKey(tone), isTrue, reason: tone.name);
        await tester.pumpWidget(host(StatusBadge(label: 'x', tone: tone)));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a finished order and a finished sitting differ',
        (tester) async {
      // **The one that is easy to "tidy up" into a bug.** They look like
      // duplicates and are not: a merchant scanning a mixed list must not
      // read a collected order as a sitting that happened.
      expect(
        StatusBadge.backgroundOf(StatusTone.orderCompleted),
        isNot(StatusBadge.backgroundOf(StatusTone.reservationCompleted)),
      );
      expect(
        StatusBadge.foregroundOf(StatusTone.orderCompleted),
        isNot(StatusBadge.foregroundOf(StatusTone.reservationCompleted)),
      );
    });

    testWidgets('unpaid and no-show share one colour, deliberately',
        (tester) async {
      // Both mean the venue is out of pocket. One vocabulary, not two.
      expect(
        StatusBadge.backgroundOf(StatusTone.unpaid),
        StatusBadge.backgroundOf(StatusTone.noShow),
      );
    });

    testWidgets('a long label is cut rather than overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 90,
            child: StatusBadge(
              label: 'Paiement en attente chez Orange Money',
              tone: StatusTone.unpaid,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('SegmentedToggle', () {
    testWidgets('tapping the other half reports its index', (tester) async {
      var chosen = -1;
      await tester.pumpWidget(
        host(
          SegmentedToggle(
            options: const ['Établissements', 'Plats'],
            selectedIndex: 0,
            onSelected: (index) => chosen = index,
          ),
        ),
      );

      await tester.tap(find.text('Plats'));
      await tester.pumpAndSettle();

      expect(chosen, 1);
    });

    testWidgets('tapping the half already showing still reports it',
        (tester) async {
      // A toggle that goes silent on the selected option makes a caller
      // guess whether the tap landed.
      var chosen = -1;
      await tester.pumpWidget(
        host(
          SegmentedToggle(
            options: const ['Réservations', 'Commandes'],
            selectedIndex: 0,
            onSelected: (index) => chosen = index,
          ),
        ),
      );

      await tester.tap(find.text('Réservations'));
      await tester.pumpAndSettle();

      expect(chosen, 0);
    });

    testWidgets('the selected half is filled ember', (tester) async {
      await tester.pumpWidget(
        host(
          SegmentedToggle(
            options: const ['Réservations', 'Commandes'],
            selectedIndex: 1,
            onSelected: (_) {},
          ),
        ),
      );

      Color? fillUnder(String label) {
        final ink = tester.widget<Ink>(
          find.ancestor(of: find.text(label), matching: find.byType(Ink)).first,
        );
        return (ink.decoration! as BoxDecoration).color;
      }

      expect(fillUnder('Commandes'), SylibookingTokens.ember);
      expect(fillUnder('Réservations'), Colors.transparent);
    });

    testWidgets('a long French label keeps all its letters', (tester) async {
      // The defect this widget exists to not repeat: SegmentedButton clipped
      // "7 prochains jours" to "7 prochains jour".
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: SegmentedToggle(
              options: const ['Réservations', '7 prochains jours'],
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('7 prochains jours'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DepositDisclosure', () {
    /// Copy shaped like the app's, so the test exercises interpolation the
    /// way the screen will.
    String headline(String deposit, int _) => 'Acompte $deposit.';
    String detail(String _, int minutes) =>
        "Compensé sur l'addition à votre arrivée. Si la table n'est pas "
        "honorée $minutes minutes après l'heure réservée, l'acompte est retenu.";

    Widget disclosure({required int minutes}) => host(
          DepositDisclosure(
            deposit: '50 000 GNF',
            windowMinutes: minutes,
            headline: headline,
            detail: detail,
          ),
        );

    testWidgets('a restaurant is told thirty minutes', (tester) async {
      await tester.pumpWidget(disclosure(minutes: 30));

      expect(find.textContaining('30 minutes'), findsOneWidget);
      expect(find.textContaining('90 minutes'), findsNothing);
    });

    testWidgets('a lounge is told ninety', (tester) async {
      // **The pair that matters.** The backend resolves this per venue type
      // and captures it on the booking; a box hardcoded to 30 would be a
      // promise the server does not keep for half the platform.
      await tester.pumpWidget(disclosure(minutes: 90));

      expect(find.textContaining('90 minutes'), findsOneWidget);
      expect(find.textContaining('30 minutes'), findsNothing);
    });

    testWidgets('the amount is shown, not implied', (tester) async {
      await tester.pumpWidget(disclosure(minutes: 30));

      expect(find.textContaining('50 000 GNF'), findsOneWidget);
    });

    testWidgets('it wears the design file\'s amber, not the error colour',
        (tester) async {
      // This is information, not a warning. Painting it red would read as
      // "something went wrong" on a screen where nothing has.
      await tester.pumpWidget(disclosure(minutes: 30));

      final box = tester.widget<Container>(find.byType(Container).first);
      final decoration = box.decoration! as BoxDecoration;

      expect(decoration.color, const Color(0xFFFBF3E4));
      expect(
        (decoration.border! as Border).top.color,
        const Color(0xFFEED9A9),
      );
    });
  });
}
