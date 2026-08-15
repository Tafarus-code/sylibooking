import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import 'src/app.dart';
import 'src/auth_controller.dart';
import 'src/config.dart';
import 'src/token_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final auth = AuthController(
    api: SylibookingApi(baseUrl: AppConfig.apiBaseUrl),
    tokenStore: SharedPreferencesTokenStore(),
    // The real registrar only here, not in the controller's default: widget
    // tests build the controller directly and must not reach for a platform
    // channel. It disables itself when there is no Firebase project, so a
    // build without google-services.json still runs — see push_registrar.dart.
    push: FirebasePushRegistrar(),
  );

  runApp(MerchantApp(auth: auth));
}
