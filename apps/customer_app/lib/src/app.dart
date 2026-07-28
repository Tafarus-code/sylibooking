import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import 'booking_store.dart';
import 'screens/browse_screen.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key, required this.api, required this.store});

  final SylibookingApi api;
  final BookingStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sylibooking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB4551C)),
        useMaterial3: true,
      ),
      home: BrowseScreen(api: api, store: store),
    );
  }
}
