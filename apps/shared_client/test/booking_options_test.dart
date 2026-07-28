import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

Space space(int id, String name, int capacity) => Space(
      id: id,
      name: name,
      type: SpaceType.table,
      typeDisplay: 'Table',
      capacity: capacity,
    );

SpaceAvailability grid(Space s, Map<int, bool> hourAvailability) =>
    SpaceAvailability(
      space: s,
      slots: [
        for (final entry in hourAvailability.entries)
          Slot(
            start: DateTime(2026, 8, 1, entry.key),
            available: entry.value,
          ),
      ],
    );

void main() {
  group('bookableTimes', () {
    test('returns only times with something free', () {
      final options = bookableTimes([
        grid(space(1, 'Table 1', 2), {18: true, 19: false, 20: true}),
      ]);

      expect(options.map((o) => o.start.hour), [18, 20]);
    });

    test('picks the smallest space that fits', () {
      final options = bookableTimes([
        grid(space(1, 'VIP Room', 10), {19: true}),
        grid(space(2, 'Table 4', 4), {19: true}),
        grid(space(3, 'Terrace', 6), {19: true}),
      ]);

      expect(options.single.space.name, 'Table 4');
      expect(options.single.freeSpaceCount, 3);
    });

    test('falls back to a bigger space when the small one is taken', () {
      final options = bookableTimes([
        grid(space(1, 'Table 4', 4), {19: false}),
        grid(space(2, 'VIP Room', 10), {19: true}),
      ]);

      expect(options.single.space.name, 'VIP Room');
      expect(options.single.isLastSpace, isTrue);
    });

    test('excludes spaces too small for the party', () {
      final options = bookableTimes(
        [
          grid(space(1, 'Table 1', 2), {19: true}),
          grid(space(2, 'VIP Room', 10), {19: true}),
        ],
        partySize: 6,
      );

      expect(options.single.space.name, 'VIP Room');
      expect(options.single.freeSpaceCount, 1);
    });

    test('returns nothing when the party fits nowhere', () {
      final options = bookableTimes(
        [
          grid(space(1, 'Table 1', 2), {19: true}),
        ],
        partySize: 8,
      );

      expect(options, isEmpty);
    });

    test('returns nothing when the day is fully booked', () {
      final options = bookableTimes([
        grid(space(1, 'Table 1', 2), {18: false, 19: false}),
      ]);

      expect(options, isEmpty);
    });

    test('sorts times chronologically across spaces', () {
      final options = bookableTimes([
        grid(space(1, 'Table 1', 2), {21: true}),
        grid(space(2, 'Table 2', 2), {18: true, 20: true}),
      ]);

      expect(options.map((o) => o.start.hour), [18, 20, 21]);
    });

    test('handles an empty grid', () {
      expect(bookableTimes([]), isEmpty);
    });
  });
}
