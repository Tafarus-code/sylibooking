import 'models.dart';

/// One bookable time, with the space the app would reserve for it.
///
/// The availability endpoint answers per space, but a customer thinks in
/// times: "is 20:00 free?", not "is Table 4 free at 20:00?".
class TimeOption {
  const TimeOption({
    required this.start,
    required this.space,
    required this.freeSpaceCount,
  });

  final DateTime start;

  /// The space that would be booked — the smallest one that still fits.
  final Space space;

  /// How many spaces are free at this time. 1 means "last table".
  final int freeSpaceCount;

  bool get isLastSpace => freeSpaceCount == 1;
}

/// Collapses a per-space availability grid into the times a customer can book.
///
/// For each time, picks the smallest free space that seats the party, so a
/// couple does not take the VIP room while a two-top sits empty. Times with
/// nothing free are dropped rather than shown greyed out — a customer
/// scrolling for a table wants the list of what they can have.
///
/// Pass [partySize] to exclude spaces too small; the API already filters when
/// given `party_size`, but a caller that skipped it can still filter here.
List<TimeOption> bookableTimes(
  List<SpaceAvailability> availability, {
  int? partySize,
}) {
  final bySlot = <DateTime, List<Space>>{};

  for (final entry in availability) {
    if (partySize != null && entry.space.capacity < partySize) continue;
    for (final slot in entry.slots) {
      if (!slot.available) continue;
      bySlot.putIfAbsent(slot.start, () => []).add(entry.space);
    }
  }

  final starts = bySlot.keys.toList()..sort();
  return [
    for (final start in starts)
      TimeOption(
        start: start,
        space: bySlot[start]!.reduce(
          (best, space) => space.capacity < best.capacity ? space : best,
        ),
        freeSpaceCount: bySlot[start]!.length,
      ),
  ];
}