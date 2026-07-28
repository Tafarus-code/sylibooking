import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

/// Today's hours up front, the rest of the week behind a tap.
///
/// A customer deciding whether to go out wants one answer — open or not, and
/// until when. The full week matters far less often, so it starts collapsed.
class HoursSection extends StatefulWidget {
  const HoursSection({super.key, required this.establishment});

  final Establishment establishment;

  @override
  State<HoursSection> createState() => _HoursSectionState();
}

class _HoursSectionState extends State<HoursSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final establishment = widget.establishment;
    final open = establishment.isOpenNow;

    // A venue with no hours recorded says so rather than claiming to be shut.
    final unknown = !establishment.hasHours && establishment.today == null;

    final colour = unknown
        ? theme.colorScheme.onSurfaceVariant
        : open
            ? theme.colorScheme.primary
            : theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              unknown
                  ? Icons.schedule
                  : open
                      ? Icons.check_circle
                      : Icons.do_not_disturb_on,
              size: 20,
              color: colour,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                establishment.openSummary,
                style: theme.textTheme.titleMedium?.copyWith(color: colour),
              ),
            ),
            if (establishment.hasHours)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Hide week' : 'All week'),
              ),
          ],
        ),
        if (_expanded && establishment.hasHours) ...[
          const SizedBox(height: 8),
          _WeekTable(
            hours: establishment.hours,
            todayIndex: establishment.today?.dayOfWeek,
          ),
        ],
      ],
    );
  }
}

class _WeekTable extends StatelessWidget {
  const _WeekTable({required this.hours, this.todayIndex});

  final List<OpeningHours> hours;
  final int? todayIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        for (final day in hours)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    day.dayDisplay,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: day.dayOfWeek == todayIndex
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    day.range,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: day.isClosed
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                      fontWeight: day.dayOfWeek == todayIndex
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
