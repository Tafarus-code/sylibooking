import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';
import '../widgets/reservation_card.dart';
import 'reservation_detail_screen.dart';

enum DateRange {
  today,
  week;

  String label(L l) =>
      this == DateRange.today ? l.rangeToday : l.rangeNextSevenDays;
}

/// What is booked, and act on it.
///
/// A body rather than a screen: the venue desk owns the bar above it, so this
/// and the orders queue share one venue name, one switcher and one refresh.
class ReservationsView extends StatefulWidget {
  const ReservationsView({super.key, required this.auth, this.reloadToken = 0});

  final AuthController auth;

  /// Bumped by the desk's refresh button.
  final int reloadToken;

  @override
  State<ReservationsView> createState() => _ReservationsViewState();
}

class _ReservationsViewState extends State<ReservationsView> {
  DateRange _range = DateRange.today;
  List<Reservation> _reservations = const [];
  bool _loading = true;

  /// Whether there is another page behind this one, and whether it is on its
  /// way. A venue with four hundred bookings in a week should see the first
  /// of them immediately, not wait for the four hundredth.
  bool _hasMore = false;
  bool _loadingMore = false;
  int _page = 1;
  String? _error;

  /// Ids currently being confirmed/cancelled, so their buttons disable.
  final Set<int> _pendingActions = {};

  SylibookingApi get _api => widget.auth.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReservationsView old) {
    super.didUpdateWidget(old);
    if (widget.reloadToken != old.reloadToken) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      final page = await _api.reservations(
        // One venue, the selected one. The server refuses any other.
        establishmentId: widget.auth.selectedVenueId!,
        from: today,
        to: _range == DateRange.today
            ? today
            : today.add(const Duration(days: 6)),
        page: 1,
      );
      final results = [...page.results]
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
      if (!mounted) return;
      setState(() {
        _reservations = results;
        _page = 1;
        _hasMore = page.next != null;
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

  /// Fetch the page after the one on screen, and append it.
  ///
  /// Appended rather than replacing: the merchant is already reading this
  /// list, and a list that empties and refills under them loses their place.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      final page = await _api.reservations(
        establishmentId: widget.auth.selectedVenueId!,
        from: today,
        to: _range == DateRange.today
            ? today
            : today.add(const Duration(days: 6)),
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _reservations = [..._reservations, ...page.results]
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
        _page += 1;
        _hasMore = page.next != null;
        _loadingMore = false;
      });
    } on ApiException {
      // Nothing was appended; the trigger will come round again on the next
      // scroll rather than the merchant being told off for scrolling.
      if (mounted) setState(() => _loadingMore = false);
    } on ApiUnreachableException {
      if (mounted) setState(() => _loadingMore = false);
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
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cancelThisReservation),
        content: Text(
          l.cancelReservationDetail(
            reservation.customerName,
            reservation.spaceName,
            DateFormat.Hm().format(reservation.dateTime),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.keepIt),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l.cancelBooking),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await _act(reservation, _api.cancelReservation, l.reservationCancelled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Column(
      children: [
        // The date range belongs to this queue alone, so it sits in the body
        // rather than in the bar the two queues share.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SegmentedButton<DateRange>(
            segments: [
              for (final range in DateRange.values)
                ButtonSegment(
                  value: range,
                  // Scaled down rather than clipped. A segment is a
                  // fixed-height pill, so a label that wraps loses its second
                  // line — but one that simply runs off the end loses a
                  // letter and reads "7 prochains jour", which is worse
                  // because it looks like a typo rather than a layout
                  // problem.
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      range.label(l),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
            ],
            selected: {_range},
            onSelectionChanged: (selection) {
              setState(() => _range = selection.first);
              _load();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(onRefresh: _load, child: _body()),
        ),
      ],
    );
  }

  Widget _body() {
    final l = L.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off,
        title: l.couldNotLoadReservations,
        detail: _error!,
        action: FilledButton(onPressed: _load, child: Text(l.tryAgain)),
      );
    }

    final user = widget.auth.user;
    if (user != null && user.establishments.isEmpty && !user.isSuperuser) {
      return _Message(
        icon: Icons.store_mall_directory_outlined,
        title: l.noVenueAssigned,
        detail: l.noVenueAssignedDetail,
      );
    }

    if (_reservations.isEmpty) {
      return _Message(
        icon: Icons.event_available,
        title: _range == DateRange.today
            ? l.nothingBookedToday
            : l.nothingBookedThisWeek,
        detail: l.newReservationsAppearHere,
      );
    }

    // Flattened into one list of rows — day headings and cards together —
    // rather than a builder over days that each build a Column of their own.
    // A Column builds every child at once, so five hundred bookings on one
    // Saturday used to mean five hundred cards laid out before the first was
    // on screen.
    final rows = _rows();

    return NotificationListener<ScrollNotification>(
      // Reaching the end is the request for more. No button, because a
      // merchant scrolling a list is already telling us what they want.
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.axis == Axis.vertical &&
            metrics.pixels >= metrics.maxScrollExtent - 400) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: contentInsets(context, maxWidth: ContentWidth.listFor(context)),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= rows.length) {
            // Just the spinner. Asking for the next page from inside a builder
            // would mean calling setState during a build, which Flutter
            // refuses — the scroll notification below is what triggers it.
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final row = rows[index];
          if (row is DateTime) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                _dayLabel(row, l),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          }

          final reservation = row as Reservation;
          return ReservationCard(
            reservation: reservation,
            busy: _pendingActions.contains(reservation.id),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReservationDetailScreen(
                  reservation: reservation,
                  api: _api,
                ),
              ),
            ),
            onConfirm: () => _act(
              reservation,
              _api.confirmReservation,
              l.reservationConfirmed,
            ),
            onCancel: () => _confirmCancel(reservation),
            onComplete: () => _act(
              reservation,
              _api.completeReservation,
              l.guestsArrived(reservation.customerName),
            ),
          );
        },
      ),
    );
  }

  /// Day headings and bookings in one flat list.
  ///
  /// A `DateTime` is a heading; a `Reservation` is a card. Grouped by day so
  /// the week view still reads as a calendar rather than a flat run of rows.
  List<Object> _rows() {
    final rows = <Object>[];
    DateTime? currentDay;
    for (final reservation in _reservations) {
      final day = DateTime(
        reservation.dateTime.year,
        reservation.dateTime.month,
        reservation.dateTime.day,
      );
      if (currentDay == null || day != currentDay) {
        rows.add(day);
        currentDay = day;
      }
      rows.add(reservation);
    }
    return rows;
  }

  String _dayLabel(DateTime day, L l) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = day.difference(today).inDays;
    return switch (difference) {
      0 => l.dayToday,
      1 => l.dayTomorrow,
      _ => DateFormat.MMMEd(l.localeName).format(day),
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
          padding: contentInsets(
            context,
            minHorizontal: 32,
          ).copyWith(top: 80, bottom: 32),
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
