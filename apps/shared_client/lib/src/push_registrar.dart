/// Getting this phone a push token, and telling the server about it.
///
/// The server half has existed since Slice 7 — `DeviceToken`, `POST
/// /api/devices/`, and a sender behind configuration. This is the half that
/// was missing, and it is deliberately small: acquire a token, register it,
/// re-register when Firebase rotates it, and unregister on sign-out.
///
/// **An app with no Firebase project still runs.** `Firebase.initializeApp`
/// throws when there is no `google-services.json`, and that is caught rather
/// than allowed to take the app down. A merchant whose build predates the
/// Firebase setup gets no push and everything else, which is the right
/// trade — the alternative is a launch screen that crashes because somebody
/// has not finished a console wizard.
///
/// **A stale token is worse than no token.** Signing out unregisters, because
/// otherwise a shared phone in a lounge keeps receiving another venue's
/// bookings, and the server keeps paying to send them.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// What the app asks for a token. An interface because the real one is a
/// platform channel, and every flow around it is worth testing without one.
abstract class PushRegistrar {
  /// Ask for permission if needed, get a token, and register it.
  ///
  /// Returns the token, or null when push is unavailable — no project, no
  /// permission, or a platform that does not do this.
  Future<String?> register(SylibookingApi api);

  /// Forget this device server-side. Called on sign-out.
  Future<void> unregister(SylibookingApi api);

  /// Fires when Firebase issues a new token for this install.
  Stream<String> get tokenRefreshes;
}

/// What runs when nobody has set Firebase up. Does nothing, quietly.
class NoPushRegistrar implements PushRegistrar {
  const NoPushRegistrar();

  @override
  Future<String?> register(SylibookingApi api) async => null;

  @override
  Future<void> unregister(SylibookingApi api) async {}

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
}

/// The real one.
class FirebasePushRegistrar implements PushRegistrar {
  FirebasePushRegistrar({this.platform = 'android'});

  /// Sent to the server so it knows which sender to use later.
  final String platform;

  String? _token;
  bool _ready = false;

  /// Bring Firebase up, or decide it is not available and say so once.
  ///
  /// Idempotent: called before every register, and cheap after the first.
  Future<bool> _ensureReady() async {
    if (_ready) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _ready = true;
      return true;
    } on Object catch (error) {
      // No google-services.json, or a project that is not set up. Not fatal:
      // the app works, it simply cannot be pushed to.
      debugPrint('Push unavailable: $error');
      return false;
    }
  }

  @override
  Future<String?> register(SylibookingApi api) async {
    if (!await _ensureReady()) return null;

    try {
      final messaging = FirebaseMessaging.instance;
      // Asked here rather than at launch: a permission prompt before anybody
      // has seen what the app does gets refused, and iOS never asks twice.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return null;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return null;

      await api.registerDevice(token: token, platform: platform);
      _token = token;
      return token;
    } on Object catch (error) {
      // Registration failing must never stop a sign-in. The merchant still
      // has a desk to work; they just have to pull to refresh.
      debugPrint('Could not register for push: $error');
      return null;
    }
  }

  @override
  Future<void> unregister(SylibookingApi api) async {
    final token = _token;
    if (token == null) return;
    try {
      await api.unregisterDevice(token);
    } on Object catch (error) {
      debugPrint('Could not unregister push token: $error');
    } finally {
      _token = null;
    }
  }

  @override
  Stream<String> get tokenRefreshes {
    if (!_ready) return const Stream.empty();
    return FirebaseMessaging.instance.onTokenRefresh;
  }
}
