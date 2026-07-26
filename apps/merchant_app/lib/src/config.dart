import 'package:flutter/foundation.dart';

/// Where the app looks for the backend.
///
/// Override at build time so a device on the same wifi can reach a laptop:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
class AppConfig {
  static const _override = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    // The Android emulator reaches the host's localhost as 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://127.0.0.1:8000/api';
  }
}
