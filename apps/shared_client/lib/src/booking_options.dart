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
/// One time on the picker, whether or not it can be booked.
///
/// [bookableTimes] answers "what can I have"; this answers "what does the
/// evening look like". They are different questions and the booking screen
/// asks the second one.
class SlotTime {
  const SlotTime({required this.start, required this.option});

  final DateTime start;

  /// What would be booked, or null when the time is already gone.
  final TimeOption? option;

  bool get isTaken => option == null;
}

/// Every slot the venue offers for the day, taken ones included.
///
/// Deliberately different from [bookableTimes], which drops what is gone. A
/// list showing only free times tells a customer nothing about the evening:
/// 19:30 alone reads as "barely open", where 19:30 free between two struck-
/// through neighbours reads as "busy night, take this one". Same information
/// the venue has, and it is the difference between a customer choosing
/// around the rush and one assuming the place is dead.
///
/// Taken slots are not tappable — they carry no space to reserve.
List<SlotTime> slotTimes(
  List<SpaceAvailability> availability, {
  int? partySize,
}) {
  final bookable = {
    for (final option in bookableTimes(availability, partySize: partySize))
      option.start: option,
  };

  // Every start the venue offers, from every space, free or not. A time only
  // one space ever opens at is still a time the venue offers.
  final starts = <DateTime>{
    for (final entry in availability)
      for (final slot in entry.slots) slot.start,
  }.toList()
    ..sort();

  return [
    for (final start in starts)
      SlotTime(start: start, option: bookable[start]),
  ];
}
