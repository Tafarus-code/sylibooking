import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';

/// What the venue can learn about itself.
///
/// Read in a dim lounge, standing up, on a phone. That decides most of what
/// this screen is: big numbers, short bars, and no chart that needs a legend
/// to be understood. Nothing here encodes meaning in colour alone — every bar
/// carries its own number, because a merchant should not have to match a hue
/// against a key to find out which night is busy.
///
/// Every section says why it is empty rather than drawing an empty chart. A
/// blank panel reads as a broken screen; "no orders in this period, and only
/// restaurants take them" reads as an answer.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  VenueInsights? _insights;
  bool _loading = true;
  String? _error;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final venue = widget.auth.selectedVenue;
    if (venue == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final insights = await widget.auth.api.insights(
        establishmentId: venue.id,
        days: _days,
      );
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _pick(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final venue = widget.auth.selectedVenue;

    return Scaffold(
      appBar: AppBar(title: Text(l.insights)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: contentInsets(context).copyWith(top: 8, bottom: 32),
          children: [
            _WindowPicker(days: _days, onPick: _pick),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _Message(
                icon: Icons.cloud_off,
                title: l.insightsFailed,
                detail: _error!,
                action: FilledButton(
                  onPressed: _load,
                  child: Text(l.tryAgain),
                ),
              )
            else if (_insights case final insights?) ...[
              _CoversCard(covers: insights.covers),
              const SizedBox(height: 12),
              _AttendanceCard(attendance: insights.attendance),
              const SizedBox(height: 12),
              _PeakHoursCard(hours: insights.peakHours),
              const SizedBox(height: 12),
              _DishesCard(
                insights: insights,
                isLounge: venue?.type == 'lounge',
              ),
              const SizedBox(height: 12),
              _RepeatCard(repeat: insights.repeatCustomers),
            ],
          ],
        ),
      ),
    );
  }
}

/// Three windows, never a date range.
///
/// A merchant comparing "last 30 days" with a colleague's "last 28" is
/// comparing nothing, and a range picker turns a screen somebody reads
/// standing up into a report builder.
class _WindowPicker extends StatelessWidget {
  const _WindowPicker({required this.days, required this.onPick});

  final int days;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final labels = {7: l.insightsWindow7, 30: l.insightsWindow30, 90: l.insightsWindow90};

    return Wrap(
      spacing: 8,
      children: [
        for (final entry in labels.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: days == entry.key,
            onSelected: (_) => onPick(entry.key),
          ),
      ],
    );
  }
}

/// A titled panel. Every section is one, so the screen scans as a column of
/// answers rather than a wall.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Why a section is empty, in a sentence.
///
/// Never a blank panel: an empty chart and a broken screen look identical,
/// and only one of them is worth a merchant's afternoon.
class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.why});

  final String title;
  final String why;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          why,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CoversCard extends StatelessWidget {
  const _CoversCard({required this.covers});

  final CoverCounts covers;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    if (covers.isEmpty) {
      return _Section(
        title: l.coversTitle,
        child: _Empty(title: l.coversEmpty, why: l.coversEmptyWhy),
      );
    }

    final busiest = covers.byWeekday
        .map((d) => d.covers)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return _Section(
      title: l.coversTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.coversTotal(covers.total),
            style: theme.textTheme.displaySmall,
          ),
          Text(
            l.coversBookings(covers.bookings),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (covers.averagePartySize case final size?) ...[
            const SizedBox(height: 4),
            Text(
              l.averageParty(size.toStringAsFixed(1)),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          Text(l.coversByWeekday, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final day in covers.byWeekday)
            _Bar(
              label: _weekdayLabel(context, day.weekday),
              value: day.covers,
              max: busiest,
            ),
        ],
      ),
    );
  }
}

/// One row of a bar chart: a name, a proportional bar, and its own number.
///
/// The number is on the row rather than in a tooltip because a tooltip needs
/// a second hand and a steady one, and this is read in a room with a queue
/// in it.
class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.max});

  final String label;
  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = max == 0 ? 0.0 : value / max;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 14,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.attendance});

  final AttendanceCounts attendance;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    if (attendance.isEmpty) {
      return _Section(
        title: l.attendanceTitle,
        child: _Empty(title: l.attendanceEmpty, why: l.attendanceEmptyWhy),
      );
    }

    return _Section(
      title: l.attendanceTitle,
      child: Column(
        children: [
          // Apart, never added together: one is a stranger who never came,
          // the other a customer who telephoned.
          _Stat(
            label: l.attendanceMissed,
            detail: l.attendanceMissedWhy,
            count: attendance.missed,
            rate: attendance.missedRate,
            total: attendance.total,
          ),
          const SizedBox(height: 12),
          _Stat(
            label: l.attendanceCancelled,
            detail: l.attendanceCancelledWhy,
            count: attendance.cancelled,
            rate: attendance.cancelledRate,
            total: attendance.total,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.detail,
    required this.count,
    required this.total,
    this.rate,
  });

  final String label;
  final String detail;
  final int count;
  final int total;
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              rate == null ? '—' : '${(rate! * 100).round()}%',
              style: theme.textTheme.headlineSmall,
            ),
            Text(
              l.ofBookings(total),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PeakHoursCard extends StatelessWidget {
  const _PeakHoursCard({required this.hours});

  final List<PeakHour> hours;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    if (hours.isEmpty) {
      return _Section(
        title: l.peakHoursTitle,
        child: _Empty(title: l.peakHoursEmpty, why: l.coversEmptyWhy),
      );
    }

    final busiest = hours.map((h) => h.covers).fold<int>(0, (a, b) => a > b ? a : b);

    return _Section(
      title: l.peakHoursTitle,
      child: Column(
        children: [
          for (final hour in hours)
            _Bar(
              label: '${hour.hour.toString().padLeft(2, '0')}h',
              value: hour.covers,
              max: busiest,
            ),
        ],
      ),
    );
  }
}

class _DishesCard extends StatelessWidget {
  const _DishesCard({required this.insights, required this.isLounge});

  final VenueInsights insights;
  final bool isLounge;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    if (insights.dishesByQuantity.isEmpty) {
      return _Section(
        title: l.dishesTitle,
        child: _Empty(
          title: l.dishesEmpty,
          // A lounge has no orders by rule, not by accident. Saying so stops
          // a merchant looking for the setting that turned them off.
          why: isLounge ? l.dishesLoungeWhy : l.dishesEmptyWhy,
        ),
      );
    }

    return _Section(
      title: l.dishesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Two lists, because they disagree: what the kitchen makes most of
          // is rarely what pays for the kitchen.
          Text(l.dishesByQuantity, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final dish in insights.dishesByQuantity)
            _DishRow(name: dish.name, trailing: '${dish.quantity}'),
          const SizedBox(height: 16),
          Text(l.dishesByRevenue, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final dish in insights.dishesByRevenue)
            _DishRow(name: dish.name, trailing: dish.revenue),
        ],
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.name, required this.trailing});

  final String name;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
          Text(
            trailing,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RepeatCard extends StatelessWidget {
  const _RepeatCard({required this.repeat});

  final RepeatCustomers repeat;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    if (repeat.isEmpty) {
      return _Section(
        title: l.repeatTitle,
        child: _Empty(title: l.repeatEmpty, why: l.repeatEmptyWhy),
      );
    }

    final rate = repeat.returningRate;

    return _Section(
      title: l.repeatTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rate == null ? '—' : '${(rate * 100).round()}%',
            style: theme.textTheme.displaySmall,
          ),
          Text(
            l.ofBookings(repeat.bookings),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.repeatCustomers(repeat.returningCustomers),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

String _weekdayLabel(BuildContext context, int weekday) {
  final l = L.of(context);
  // Monday first, matching the hours screen and the API's day_of_week. The
  // full name rather than an abbreviation: three-letter days would need seven
  // more keys in every language to save forty pixels.
  return [
    l.monday,
    l.tuesday,
    l.wednesday,
    l.thursday,
    l.friday,
    l.saturday,
    l.sunday,
  ][weekday];
}

/// A failure with a way out of it, matching the other merchant screens.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
