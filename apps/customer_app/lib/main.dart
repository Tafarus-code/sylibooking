import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import 'src/app.dart';
import 'src/booking_store.dart';
import 'src/config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    CustomerApp(
      api: SylibookingApi(baseUrl: AppConfig.apiBaseUrl),
      store: SharedPreferencesBookingStore(),
    ),
  );
}
