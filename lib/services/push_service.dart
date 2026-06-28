import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/routes.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Bridges native APNs registration to the NullFeed backend.
///
/// On iOS this owns a [MethodChannel] to the native `AppDelegate`, which
/// requests notification authorization, registers with APNs, and reports the
/// device token back. The token is then sent to the backend's push registry so
/// new-episode notifications can be delivered.
///
/// This is a pure platform-channel integration (no Firebase): foreground
/// notification presentation is handled natively by the
/// `UNUserNotificationCenterDelegate`. All operations are best-effort and must
/// never block or break the auth flow, so failures are logged and swallowed.
class PushService {
  PushService(this._ref) {
    // Listen for tokens pushed from native (initial registration and APNs
    // token rotation) and for notification taps. Re-register whenever the
    // token changes.
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const _channel = MethodChannel('nullfeed/push');

  final Ref _ref;

  /// The last APNs token successfully registered with the backend, used to
  /// avoid redundant registration calls when the token hasn't changed.
  String? _registeredToken;

  bool get _isSupported => !kIsWeb && Platform.isIOS;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onApnsToken':
        final token = call.arguments as String?;
        if (token != null && token.isNotEmpty && token != _registeredToken) {
          await _sendToken(token);
        }
      case 'onNotificationTap':
        _routeNotification(call.arguments);
    }
    return null;
  }

  /// Requests notification permission (showing the system prompt the first
  /// time) and registers this device's APNs token with the backend. Call after
  /// an interactive sign-in. A no-op on unsupported platforms.
  Future<void> registerForPush() async {
    if (!_isSupported) return;
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestPermissionAndToken') ??
          false;
      if (!granted) {
        debugPrint('Push: notification permission not granted');
      }
      // The token arrives asynchronously via onApnsToken once APNs registration
      // completes; _sendToken forwards it to the backend.
    } catch (e) {
      debugPrint('Push: registerForPush failed: $e');
    }
  }

  /// Refreshes the token registration without ever prompting — registers only
  /// if notifications are already authorized. Call on silent session restore so
  /// a relaunch refreshes the token but never pops the permission dialog at
  /// cold launch. A no-op on unsupported platforms.
  Future<void> registerIfAuthorized() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<bool>('registerIfAuthorized');
      // If authorized, the token arrives via onApnsToken as above.
    } catch (e) {
      debugPrint('Push: registerIfAuthorized failed: $e');
    }
  }

  /// Pulls the notification (if any) that cold-started the app and routes to it,
  /// then signals the native side that subsequent (warm) taps can be delivered
  /// live. Call once we're signed in and the router can navigate. No-op off iOS.
  Future<void> handleInitialNotification() async {
    if (!_isSupported) return;
    try {
      final args = await _channel.invokeMethod('getInitialNotification');
      if (args != null) _routeNotification(args);
    } catch (e) {
      debugPrint('Push: getInitialNotification failed: $e');
    }
  }

  /// Removes this device's push token from the backend. Best-effort; call
  /// before clearing auth state on sign-out (while the session is still valid).
  Future<void> unregister() async {
    if (!_isSupported) return;
    try {
      final deviceId = _ref.read(storageServiceProvider).getDeviceId();
      if (deviceId == null || deviceId.isEmpty) return;
      await _ref.read(apiServiceProvider).unregisterPushToken(deviceId);
      _registeredToken = null;
    } catch (e) {
      debugPrint('Push: unregister failed: $e');
    }
  }

  /// Routes a tapped notification to the right screen from its custom payload.
  /// New-episode pushes carry a `video_id` and open the player.
  void _routeNotification(Object? arguments) {
    final data = _asStringMap(arguments);
    switch (data['type'] as String?) {
      case 'new_episode':
        final videoId = data['video_id'] as String?;
        if (videoId == null || videoId.isEmpty) return;
        _ref.read(routerProvider).push('/player/$videoId');
    }
  }

  /// Registers [token] with the backend, attaching this device's stable id.
  Future<void> _sendToken(String token) async {
    try {
      final deviceId = await _deviceId();
      final registered = await _ref
          .read(apiServiceProvider)
          .registerPushToken(token: token, deviceId: deviceId);
      if (registered) {
        _registeredToken = token;
      } else {
        debugPrint('Push: backend reports push disabled or token not stored');
      }
    } catch (e) {
      debugPrint('Push: failed to send token: $e');
    }
  }

  /// Returns this install's stable device id, generating and persisting one on
  /// first use.
  Future<String> _deviceId() async {
    final storage = _ref.read(storageServiceProvider);
    final existing = storage.getDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generateDeviceId();
    await storage.setDeviceId(id);
    return id;
  }

  /// A random 128-bit identifier, hex-encoded. Stable once persisted.
  String _generateDeviceId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, dynamic> _asStringMap(Object? value) =>
      value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : const {};
}

/// Provides the app-wide [PushService].
final pushServiceProvider = Provider<PushService>(PushService.new);
