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
  );

  runApp(MerchantApp(auth: auth));
}
