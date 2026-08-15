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
      tokenStore: SharedPreferencesCustomerTokenStore(),
      // Only here, never as the controller's default: a widget test builds
      // the app directly and must not touch a platform channel. It disables
      // itself when there is no Firebase project.
      push: FirebasePushRegistrar(),
    ),
  );
}
