import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'package:shared_client/shared_client.dart';

import '../booking_store.dart';
import '../customer_auth.dart';
import '../image_source.dart';
import 'my_bookings_screen.dart';
import 'my_orders_view.dart';

/// The two things a customer has going: tables booked, and food ordered.
enum ActivityTab {
  bookings,
  orders;

  /// Resolved against the current language rather than baked into the enum,
  /// so the switcher changes with the rest of the app.
  String label(L l) =>
      this == ActivityTab.bookings ? l.tabBookings : l.tabOrders;
}

/// Everything this customer has on, under one heading.
///
/// A switcher rather than a fifth navigation destination: five labelled
/// destinations do not fit across a 360dp phone, and a booking and an order
/// are the same question anyway — what have I got coming.
class MyActivityScreen extends StatefulWidget {
  const MyActivityScreen({
    super.key,
    required this.api,
    required this.store,
    required this.auth,
    required this.imageSource,
  });

  final SylibookingApi api;
  final BookingStore store;
  final CustomerAuth auth;
  final ImageSource imageSource;

  @override
  State<MyActivityScreen> createState() => _MyActivityScreenState();
}

class _MyActivityScreenState extends State<MyActivityScreen> {
  ActivityTab _tab = ActivityTab.bookings;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.myBookings),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          // The shared toggle rather than SegmentedButton: the latter sizes
          // itself from its labels and clips the longer French one, which is
          // the defect the audit found on the merchant's desk.
          child: SegmentedToggle(
            options: [for (final tab in ActivityTab.values) tab.label(l)],
            selectedIndex: _tab.index,
            onSelected: (index) =>
                setState(() => _tab = ActivityTab.values[index]),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          ),
        ),
      ),
      // IndexedStack: flipping between the two must not throw either list
      // away and refetch it.
      body: IndexedStack(
        index: _tab.index,
        children: [
          MyBookingsScreen(
            api: widget.api,
            store: widget.store,
            imageSource: widget.imageSource,
          ),
          MyOrdersView(
            api: widget.api,
            store: widget.store,
            auth: widget.auth,
          ),
        ],
      ),
    );
  }
}
