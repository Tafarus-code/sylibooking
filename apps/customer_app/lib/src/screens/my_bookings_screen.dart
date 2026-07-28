import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';

/// Bookings made on this device, re-read from the server so the status is live.
///
/// There are no customer accounts yet, so the ids come from local storage and
/// each is fetched by id. A booking made on another phone will not appear here.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key, required this.api, required this.store});

  final SylibookingApi api;
  final BookingStore store;

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Reservation> _reservations = const [];
  bool _loading = true;
  String? _error;

  /// References currently being cancelled, so their buttons disable.
  final Set<String> _cancelling = {};

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

    try {
      final references = await widget.store.bookingReferences();
      final found = <Reservation>[];
      for (final reference in references) {
        try {
          found.add(await widget.api.reservationByReference(reference));
        } on ApiException catch (e) {
          // A booking deleted server-side should not break the whole list.
          if (!e.isNotFound) rethrow;
        }
      }
      found.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      if (!mounted) return;
      setState(() {
        _reservations = found;
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

  Future<void> _cancel(Reservation reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(
          '${reservation.establishmentName} on '
          '${DateFormat.MMMEd().format(reservation.dateTime)} at '
          '${DateFormat.Hm().format(reservation.dateTime)}.\n\n'
          'The table goes back to other customers, so you may not get it '
          'again.',
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

    if (!(confirmed ?? false)) return;

    setState(() => _cancelling.add(reservation.reference));
    try {
      final updated =
          await widget.api.cancelReservationByReference(reservation.reference);
      if (!mounted) return;
      setState(() {
        _reservations = [
          for (final r in _reservations)
            r.reference == updated.reference ? updated : r,
        ];
      });
      _notify('Booking cancelled.');
    } on ApiException catch (e) {
      if (!mounted) return;
      _notify(e.message, isError: true);
      // The server refused because its view differs from ours — reload.
      if (e.isConflict || e.isNotFound) await _load();
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _cancelling.remove(reservation.reference));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
        children: [
          Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }

    if (_reservations.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
        children: [
          Icon(
            Icons.receipt_long,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No bookings yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Reservations you make on this phone show up here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _reservations.length,
      itemBuilder: (context, index) {
        final reservation = _reservations[index];
        final busy = _cancelling.contains(reservation.reference);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reservation.establishmentName,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat.yMMMEd().format(reservation.dateTime)}'
                            ' · ${DateFormat.Hm().format(reservation.dateTime)}',
                          ),
                          Text(
                            '${reservation.spaceName} · '
                            '${reservation.partySize} '
                            '${reservation.partySize == 1 ? "guest" : "guests"}',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (reservation.payment case final payment?)
                            Text(
                              switch (payment.status) {
                                PaymentStatus.completed =>
                                  '${payment.providerDisplay} · '
                                      '${payment.amount} GNF paid',
                                PaymentStatus.failed =>
                                  '${payment.providerDisplay} · payment failed',
                                _ => '${payment.providerDisplay} · '
                                    'payment pending',
                              },
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: payment.status == PaymentStatus.failed
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _StatusChip(status: reservation.status),
                  ],
                ),
                if (reservation.canCancel) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: busy ? null : () => _cancel(reservation),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancel booking'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ] else if (reservation.status.isOpen) ...[
                  const SizedBox(height: 8),
                  Text(
                    'To change this booking, call the venue.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReservationStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground) = switch (status) {
      ReservationStatus.pending => (
          'Pending',
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      ReservationStatus.confirmed => (
          'Confirmed',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      ReservationStatus.cancelled => (
          'Cancelled',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      ReservationStatus.completed => (
          'Completed',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      ReservationStatus.unknown => (
          'Unknown',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
