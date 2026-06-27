import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/providers/auth_provider.dart';
import 'package:nullfeed/providers/websocket_provider.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService api;
  late MockStorageService storage;
  late MockWebSocketService webSocket;

  setUp(() {
    api = MockApiService();
    storage = MockStorageService();
    webSocket = MockWebSocketService();
    when(() => storage.getSessionToken()).thenReturn(null);
    when(() => storage.setSelectedUserId(any())).thenAnswer((_) async {});
    when(() => storage.setSessionToken(any())).thenAnswer((_) async {});
    when(() => storage.clearSession()).thenAnswer((_) async {});
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
        webSocketServiceProvider.overrideWithValue(webSocket),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Lets the fire-and-forget restore from [AuthNotifier.build] finish.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('session restore', () {
    test('starts signed out when no session token is stored', () async {
      final container = createContainer();

      final state = container.read(authStateProvider);
      await settle();

      expect(state.currentUser, isNull);
      expect(container.read(authStateProvider).restoreFailed, isFalse);
      verifyNever(() => api.getMe());
    });

    test('validates a stored token via getMe and signs in', () async {
      final user = makeUser();
      when(() => storage.getSessionToken()).thenReturn('tok');
      when(() => api.getMe()).thenAnswer((_) async => user);
      final container = createContainer();

      container.read(authStateProvider);
      await settle();

      final state = container.read(authStateProvider);
      expect(state.currentUser, user);
      expect(state.isLoading, isFalse);
      expect(state.restoreFailed, isFalse);
      // Restore must not re-select (which would bypass PIN protection).
      verifyNever(() => api.selectProfile(any(), pin: any(named: 'pin')));
    });

    test('clears the session when the token is rejected with 401', () async {
      when(() => storage.getSessionToken()).thenReturn('stale-tok');
      when(() => api.getMe()).thenThrow(
        const ApiException(message: 'Invalid token', statusCode: 401),
      );
      final container = createContainer();

      container.read(authStateProvider);
      await settle();

      final state = container.read(authStateProvider);
      expect(state.currentUser, isNull);
      expect(state.restoreFailed, isFalse);
      verify(() => storage.setSelectedUserId(null)).called(1);
      verify(() => storage.setSessionToken(null)).called(1);
    });

    test(
      'keeps the session and flags restoreFailed on network error',
      () async {
        when(() => storage.getSessionToken()).thenReturn('tok');
        when(() => api.getMe()).thenThrow(
          const ApiException(
            message: 'Could not reach the server. Check your connection.',
            isConnectionError: true,
          ),
        );
        final container = createContainer();

        container.read(authStateProvider);
        await settle();

        final state = container.read(authStateProvider);
        expect(state.currentUser, isNull);
        expect(state.restoreFailed, isTrue);
        verifyNever(() => storage.setSessionToken(any()));
        verifyNever(() => storage.setSelectedUserId(any()));
      },
    );

    test('retryRestore succeeds after a failed restore', () async {
      final user = makeUser();
      when(() => storage.getSessionToken()).thenReturn('tok');
      when(() => api.getMe()).thenThrow(
        const ApiException(message: 'Server down', isConnectionError: true),
      );
      final container = createContainer();

      container.read(authStateProvider);
      await settle();
      expect(container.read(authStateProvider).restoreFailed, isTrue);

      when(() => api.getMe()).thenAnswer((_) async => user);
      await container.read(authStateProvider.notifier).retryRestore();

      final state = container.read(authStateProvider);
      expect(state.currentUser, user);
      expect(state.restoreFailed, isFalse);
    });
  });

  group('loadProfiles', () {
    test('populates profiles on success', () async {
      final alice = makeUser();
      final bob = makeUser(id: 'u2', displayName: 'Bob', hasPin: true);
      when(() => api.getProfiles()).thenAnswer((_) async => [alice, bob]);
      final container = createContainer();

      await container.read(authStateProvider.notifier).loadProfiles();

      final state = container.read(authStateProvider);
      expect(state.profiles, [alice, bob]);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('surfaces the ApiException message and keeps old profiles', () async {
      final alice = makeUser();
      when(() => api.getProfiles()).thenAnswer((_) async => [alice]);
      final container = createContainer();
      final notifier = container.read(authStateProvider.notifier);
      await notifier.loadProfiles();

      when(() => api.getProfiles()).thenThrow(
        const ApiException(message: 'Server exploded', statusCode: 500),
      );
      await notifier.loadProfiles();

      final state = container.read(authStateProvider);
      expect(state.error, 'Server exploded');
      expect(state.profiles, [alice], reason: 'errors must not wipe the grid');
    });
  });

  group('selectProfile', () {
    test('stores the session and sets currentUser', () async {
      final bob = makeUser(id: 'u2', displayName: 'Bob', hasPin: true);
      when(
        () => api.selectProfile('u2', pin: '1234'),
      ).thenAnswer((_) async => (user: bob, token: 'tok-2'));
      final container = createContainer();

      await container
          .read(authStateProvider.notifier)
          .selectProfile('u2', pin: '1234');

      final state = container.read(authStateProvider);
      expect(state.currentUser, bob);
      expect(state.error, isNull);
      verify(() => storage.setSelectedUserId('u2')).called(1);
      verify(() => storage.setSessionToken('tok-2')).called(1);
    });

    test(
      'surfaces Incorrect PIN without signing in or wiping profiles',
      () async {
        final alice = makeUser();
        final bob = makeUser(id: 'u2', displayName: 'Bob', hasPin: true);
        when(() => api.getProfiles()).thenAnswer((_) async => [alice, bob]);
        when(() => api.selectProfile('u2', pin: '0000')).thenThrow(
          const ApiException(message: 'Incorrect PIN', statusCode: 403),
        );
        final container = createContainer();
        final notifier = container.read(authStateProvider.notifier);
        await notifier.loadProfiles();

        await notifier.selectProfile('u2', pin: '0000');

        final state = container.read(authStateProvider);
        expect(state.error, 'Incorrect PIN');
        expect(state.currentUser, isNull);
        expect(state.profiles, [alice, bob]);
        verifyNever(() => storage.setSessionToken(any()));
      },
    );
  });

  group('createProfileFromYoutube', () {
    test('creates, selects, and signs in to the new profile', () async {
      final created = makeUser(id: 'u9', displayName: 'Marques Brownlee');
      when(
        () => api.createProfile(
          displayName: null,
          pin: null,
          youtubeHandle: '@mkbhd',
        ),
      ).thenAnswer((_) async => created);
      when(
        () => api.selectProfile('u9', pin: null),
      ).thenAnswer((_) async => (user: created, token: 'tok-9'));
      final container = createContainer();

      await container
          .read(authStateProvider.notifier)
          .createProfileFromYoutube(handle: '@mkbhd');

      final state = container.read(authStateProvider);
      expect(state.currentUser, created);
      expect(state.profiles, contains(created));
      expect(state.isLoading, isFalse);
      verify(() => storage.setSelectedUserId('u9')).called(1);
      verify(() => storage.setSessionToken('tok-9')).called(1);
    });

    test('surfaces a resolve failure as the error message', () async {
      when(
        () => api.createProfile(
          displayName: null,
          pin: null,
          youtubeHandle: '@nope',
        ),
      ).thenThrow(
        const ApiException(
          message: 'Could not resolve YouTube handle',
          statusCode: 502,
        ),
      );
      final container = createContainer();

      await container
          .read(authStateProvider.notifier)
          .createProfileFromYoutube(handle: '@nope');

      final state = container.read(authStateProvider);
      expect(state.error, 'Could not resolve YouTube handle');
      expect(state.currentUser, isNull);
    });
  });

  group('signOut', () {
    Future<ProviderContainer> signedInContainer() async {
      final alice = makeUser();
      when(() => api.getProfiles()).thenAnswer((_) async => [alice]);
      when(
        () => api.selectProfile('u1', pin: null),
      ).thenAnswer((_) async => (user: alice, token: 'tok-1'));
      final container = createContainer();
      final notifier = container.read(authStateProvider.notifier);
      await notifier.loadProfiles();
      await notifier.selectProfile('u1');
      expect(container.read(authStateProvider).currentUser, alice);
      return container;
    }

    test('logs out, disconnects the websocket, and clears storage', () async {
      when(() => api.logout()).thenAnswer((_) async {});
      final container = await signedInContainer();

      await container.read(authStateProvider.notifier).signOut();

      final state = container.read(authStateProvider);
      expect(state.currentUser, isNull);
      expect(state.profiles, hasLength(1), reason: 'profiles are kept');
      verify(() => api.logout()).called(1);
      verify(() => webSocket.disconnect()).called(1);
      verify(() => storage.clearSession()).called(1);
    });

    test('still signs out locally when the server logout fails', () async {
      when(() => api.logout()).thenThrow(
        const ApiException(message: 'Server down', isConnectionError: true),
      );
      final container = await signedInContainer();

      await container.read(authStateProvider.notifier).signOut();

      expect(container.read(authStateProvider).currentUser, isNull);
      verify(() => webSocket.disconnect()).called(1);
      verify(() => storage.clearSession()).called(1);
    });
  });

  group('handleSessionExpired', () {
    Future<ProviderContainer> signedInContainer() async {
      final alice = makeUser();
      when(() => api.getProfiles()).thenAnswer((_) async => [alice]);
      when(
        () => api.selectProfile('u1', pin: null),
      ).thenAnswer((_) async => (user: alice, token: 'tok-1'));
      final container = createContainer();
      final notifier = container.read(authStateProvider.notifier);
      await notifier.loadProfiles();
      await notifier.selectProfile('u1');
      expect(container.read(authStateProvider).currentUser, alice);
      return container;
    }

    test('resets to the picker and clears storage on a server 401', () async {
      final container = await signedInContainer();
      final notifier = container.read(authStateProvider.notifier);

      final didReset = notifier.handleSessionExpired();

      expect(didReset, isTrue);
      final state = container.read(authStateProvider);
      expect(state.currentUser, isNull);
      expect(state.profiles, hasLength(1), reason: 'profiles are kept');
      verify(() => webSocket.disconnect()).called(1);
      verify(() => storage.clearSession()).called(1);
    });

    test('is a no-op when nobody is signed in', () {
      final container = createContainer();
      final notifier = container.read(authStateProvider.notifier);

      expect(notifier.handleSessionExpired(), isFalse);
      expect(container.read(authStateProvider).currentUser, isNull);
      verifyNever(() => webSocket.disconnect());
      verifyNever(() => storage.clearSession());
    });

    test('a burst of 401s resets exactly once', () async {
      final container = await signedInContainer();
      final notifier = container.read(authStateProvider.notifier);

      expect(notifier.handleSessionExpired(), isTrue);
      expect(notifier.handleSessionExpired(), isFalse);
      expect(notifier.handleSessionExpired(), isFalse);

      verify(() => webSocket.disconnect()).called(1);
      verify(() => storage.clearSession()).called(1);
    });
  });

  group('deleteProfile', () {
    test('deleting the current user clears the session', () async {
      final alice = makeUser();
      when(() => api.getProfiles()).thenAnswer((_) async => [alice]);
      when(
        () => api.selectProfile('u1', pin: null),
      ).thenAnswer((_) async => (user: alice, token: 'tok-1'));
      when(() => api.deleteProfile('u1')).thenAnswer((_) async {});
      final container = createContainer();
      final notifier = container.read(authStateProvider.notifier);
      await notifier.loadProfiles();
      await notifier.selectProfile('u1');

      await notifier.deleteProfile('u1');

      final state = container.read(authStateProvider);
      expect(state.currentUser, isNull);
      expect(state.profiles, isEmpty);
      verify(() => webSocket.disconnect()).called(1);
      verify(() => storage.clearSession()).called(1);
    });

    test('deleting another profile keeps the current session', () async {
      final alice = makeUser();
      final bob = makeUser(id: 'u2', displayName: 'Bob');
      when(() => api.getProfiles()).thenAnswer((_) async => [alice, bob]);
      when(
        () => api.selectProfile('u1', pin: null),
      ).thenAnswer((_) async => (user: alice, token: 'tok-1'));
      when(() => api.deleteProfile('u2')).thenAnswer((_) async {});
      final container = createContainer();
      final notifier = container.read(authStateProvider.notifier);
      await notifier.loadProfiles();
      await notifier.selectProfile('u1');

      await notifier.deleteProfile('u2');

      final state = container.read(authStateProvider);
      expect(state.currentUser, alice);
      expect(state.profiles, [alice]);
      verifyNever(() => webSocket.disconnect());
      verifyNever(() => storage.clearSession());
    });

    test('surfaces admin-rule errors without changing state', () async {
      final alice = makeUser(isAdmin: true);
      when(() => api.getProfiles()).thenAnswer((_) async => [alice]);
      when(() => api.deleteProfile('u1')).thenThrow(
        const ApiException(
          message: 'Cannot delete the only admin profile',
          statusCode: 409,
        ),
      );
      final container = createContainer();
      final notifier = container.read(authStateProvider.notifier);
      await notifier.loadProfiles();

      await notifier.deleteProfile('u1');

      final state = container.read(authStateProvider);
      expect(state.error, 'Cannot delete the only admin profile');
      expect(state.profiles, [alice]);
    });
  });
}
