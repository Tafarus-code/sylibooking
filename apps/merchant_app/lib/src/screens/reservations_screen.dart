import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';
import '../widgets/reservation_card.dart';
import 'reservation_detail_screen.dart';

enum DateRange {
  today('Today'),
  week('Next 7 days');

  const DateRange(this.label);

  final String label;
}

/// The merchant's home screen: what is booked, and act on it.
class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  DateRange _range = DateRange.today;
  List<Reservation> _reservations = const [];
  bool _loading = true;
  String? _error;

  /// Ids currently being confirmed/cancelled, so their buttons disable.
  final Set<int> _pendingActions = {};

  SylibookingApi get _api => widget.auth.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      final results = await _api.allReservations(
        // One venue, the selected one. The server refuses any other.
        establishmentId: widget.auth.selectedVenueId!,
        from: today,
        to: _range == DateRange.today
            ? today
            : today.add(const Duration(days: 6)),
      );
      results.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      if (!mounted) return;
      setState(() {
        _reservations = results;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        // Token expired or was revoked — back to the login screen.
        await widget.auth.signOut();
        return;
      }
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

  Future<void> _act(
    Reservation reservation,
    Future<Reservation> Function(int id) action,
    String successMessage,
  ) async {
    setState(() => _pendingActions.add(reservation.id));
    try {
      final updated = await action(reservation.id);
      if (!mounted) return;
      setState(() {
        _reservations = [
          for (final r in _reservations) r.id == updated.id ? updated : r,
        ];
      });
      _notify(successMessage);
    } on ApiException catch (e) {
      if (!mounted) return;
      _notify(e.message, isError: true);
      // The server and the screen disagree; reload rather than guess.
      if (e.isConflict || e.isNotFound) await _load();
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _pendingActions.remove(reservation.id));
    }
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? theme.colorScheme.error : null,
        ),
      );
  }

  Future<void> _confirmCancel(Reservation reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this reservation?'),
        content: Text(
          '${reservation.customerName} · ${reservation.spaceName} at '
          '${DateFormat.Hm().format(reservation.dateTime)}.\n\n'
          'The slot becomes bookable again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await _act(reservation, _api.cancelReservation, 'Reservation cancelled.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final venue = auth.selectedVenue?.name ?? 'No venue';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reservations'),
            Text(
              // The role is shown because it decides what the rest of the app
              // will let this person do.
              auth.selectedVenue == null
                  ? venue
                  : '$venue · ${auth.selectedVenue!.roleDisplay}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          // Only for accounts that actually have somewhere to switch to.
          if (auth.hasMultipleVenues)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: auth.changeVenue,
              tooltip: 'Switch venue',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut,
            tooltip: 'Sign out',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<DateRange>(
              segments: [
                for (final range in DateRange.values)
                  ButtonSegment(value: range, label: Text(range.label)),
              ],
              selected: {_range},
              onSelectionChanged: (selection) {
                setState(() => _range = selection.first);
                _load();
              },
            ),
          ),
        ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off,
        title: 'Could not load reservations',
        detail: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    final user = widget.auth.user;
    if (user != null && user.establishments.isEmpty && !user.isSuperuser) {
      return const _Message(
        icon: Icons.store_mall_directory_outlined,
        title: 'No venue assigned',
        detail:
            'This account is not staff at any establishment yet, so there is '
            'nothing to show. An admin can assign one in the Django admin.',
      );
    }

    if (_reservations.isEmpty) {
      return _Message(
        icon: Icons.event_available,
        title: _range == DateRange.today
            ? 'Nothing booked today'
            : 'Nothing booked this week',
        detail: 'New reservations appear here as customers make them.',
      );
    }

    // Grouped by day so the week view reads as a calendar, not a flat list.
    final byDay = <DateTime, List<Reservation>>{};
    for (final reservation in _reservations) {
      final day = DateTime(
        reservation.dateTime.year,
        reservation.dateTime.month,
        reservation.dateTime.day,
      );
      byDay.putIfAbsent(day, () => []).add(reservation);
    }
    final days = byDay.keys.toList()..sort();

    return ListView.builder(
      padding: contentInsets(context, maxWidth: ContentWidth.list),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final forDay = byDay[day]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                _dayLabel(day),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            for (final reservation in forDay)
              ReservationCard(
                reservation: reservation,
                busy: _pendingActions.contains(reservation.id),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ReservationDetailScreen(reservation: reservation),
                  ),
                ),
                onConfirm: () => _act(
                  reservation,
                  _api.confirmReservation,
                  'Reservation confirmed.',
                ),
                onCancel: () => _confirmCancel(reservation),
              ),
          ],
        );
      },
    );
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = day.difference(today).inDays;
    return switch (difference) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => DateFormat.MMMEd().format(day),
    };
  }
}

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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: contentInsets(context, minHorizontal: 32).copyWith(top: 80, bottom: 32),
          child: Column(
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ],
    );
  }
}
