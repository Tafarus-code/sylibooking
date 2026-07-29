import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import 'booking_store.dart';
import 'directions.dart';
import 'image_source.dart';
import 'location_source.dart';
import 'screens/browse_screen.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({
    super.key,
    required this.api,
    required this.store,
    this.imageSource,
    this.locationSource,
    this.directionsLauncher,
  });

  final SylibookingApi api;
  final BookingStore store;

  /// Injected so widget tests can drive uploads without a platform channel.
  final ImageSource? imageSource;
  final LocationSource? locationSource;
  final DirectionsLauncher? directionsLauncher;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sylibooking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB4551C)),
        useMaterial3: true,
      ),
      home: BrowseScreen(
        api: api,
        store: store,
        imageSource: imageSource ?? DeviceImageSource(),
        locationSource: locationSource ?? const DeviceLocationSource(),
        directionsLauncher:
            directionsLauncher ?? const DeviceDirectionsLauncher(),
      ),
    );
  }
}
