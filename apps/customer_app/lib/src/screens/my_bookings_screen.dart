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
      final ids = await widget.store.bookingIds();
      final found = <Reservation>[];
      for (final id in ids) {
        try {
          found.add(await widget.api.reservation(id));
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
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(reservation.establishmentName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  '${DateFormat.yMMMEd().format(reservation.dateTime)} · '
                  '${DateFormat.Hm().format(reservation.dateTime)}',
                ),
                Text(
                  '${reservation.spaceName} · ${reservation.partySize} '
                  '${reservation.partySize == 1 ? "guest" : "guests"}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            trailing: _StatusChip(status: reservation.status),
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
