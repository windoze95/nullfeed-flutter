import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/config/routes.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/push_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

class MockGoRouter extends Mock implements GoRouter {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nullfeed/push');
  late MockApiService api;
  late MockStorageService storage;
  late MockGoRouter router;

  setUp(() {
    api = MockApiService();
    storage = MockStorageService();
    router = MockGoRouter();
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
        routerProvider.overrideWithValue(router),
      ],
    );
    addTearDown(container.dispose);
    // Reading the provider constructs the service, which registers the channel
    // handler that the simulated native calls below dispatch to.
    container.read(pushServiceProvider);
    return container;
  }

  /// Simulates the native side invoking a method on the push channel.
  Future<void> sendNative(String method, [dynamic args]) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );
  }

  group('onApnsToken', () {
    test('registers an APNs token from native with the backend', () async {
      when(() => storage.getDeviceId()).thenReturn('dev-1');
      when(
        () => api.registerPushToken(
          token: any(named: 'token'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async => true);
      createContainer();

      await sendNative('onApnsToken', 'deadbeef');

      verify(
        () => api.registerPushToken(token: 'deadbeef', deviceId: 'dev-1'),
      ).called(1);
    });

    test('generates and persists a device id on first registration', () async {
      when(() => storage.getDeviceId()).thenReturn(null);
      when(() => storage.setDeviceId(any())).thenAnswer((_) async {});
      when(
        () => api.registerPushToken(
          token: any(named: 'token'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async => true);
      createContainer();

      await sendNative('onApnsToken', 'tok');

      final captured =
          verify(() => storage.setDeviceId(captureAny())).captured.single
              as String;
      expect(captured, hasLength(32), reason: '128-bit id, hex-encoded');
      verify(
        () => api.registerPushToken(token: 'tok', deviceId: captured),
      ).called(1);
    });

    test('does not re-register an unchanged token', () async {
      when(() => storage.getDeviceId()).thenReturn('dev-1');
      when(
        () => api.registerPushToken(
          token: any(named: 'token'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async => true);
      createContainer();

      await sendNative('onApnsToken', 'tok-1');
      await sendNative('onApnsToken', 'tok-1');

      verify(
        () => api.registerPushToken(token: 'tok-1', deviceId: 'dev-1'),
      ).called(1);
    });

    test('re-registers when the backend did not store the token', () async {
      // enabled:false (push disabled server-side) returns false, so the token
      // is not cached and a later identical token is retried.
      when(() => storage.getDeviceId()).thenReturn('dev-1');
      when(
        () => api.registerPushToken(
          token: any(named: 'token'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async => false);
      createContainer();

      await sendNative('onApnsToken', 'tok-1');
      await sendNative('onApnsToken', 'tok-1');

      verify(
        () => api.registerPushToken(token: 'tok-1', deviceId: 'dev-1'),
      ).called(2);
    });
  });

  group('onNotificationTap', () {
    test('routes a new-episode tap to the player', () async {
      when(() => router.push(any())).thenAnswer((_) async => null);
      createContainer();

      await sendNative('onNotificationTap', {
        'type': 'new_episode',
        'video_id': 'vid-123',
      });

      verify(() => router.push('/player/vid-123')).called(1);
    });

    test('ignores a tap with no video id', () async {
      createContainer();

      await sendNative('onNotificationTap', {'type': 'new_episode'});

      verifyNever(() => router.push(any()));
    });

    test('ignores a tap of an unknown type', () async {
      createContainer();

      await sendNative('onNotificationTap', {
        'type': 'something_else',
        'video_id': 'vid-123',
      });

      verifyNever(() => router.push(any()));
    });
  });
}
