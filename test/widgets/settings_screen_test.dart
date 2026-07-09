import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/providers/auth_provider.dart';
import 'package:nullfeed/screens/settings_screen.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService api;
  late FakeStorageService storage;

  setUp(() {
    api = MockApiService();
    storage = FakeStorageService(serverUrl: 'http://oldbox.local:8484');
    final user = makeUser(displayName: 'Alice');
    when(
      () => api.selectProfile(user.id),
    ).thenAnswer((_) async => (user: user, token: 'session-token'));
    when(() => api.logout()).thenAnswer((_) async {});
  });

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    required SettingsServerHealthCheck healthCheck,
  }) async {
    final container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.notifier).selectProfile('u1');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NullFeedTheme.darkTheme,
          home: SettingsScreen(healthCheck: healthCheck),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('tests the draft address without changing the saved server', (
    tester,
  ) async {
    final checkedAddresses = <String>[];
    await pumpSettings(
      tester,
      healthCheck: (address) async {
        checkedAddresses.add(address);
        return true;
      },
    );

    expect(find.text('Who is watching'), findsOneWidget);
    expect(find.text('Your NullFeed server'), findsOneWidget);
    expect(find.text('Download Quality'), findsNothing);
    expect(checkedAddresses, ['http://oldbox.local:8484']);

    await tester.enterText(
      find.byKey(const ValueKey('settings-server-url')),
      'newbox.local:8484',
    );
    await tester.pump();
    final testButton = find.byKey(const ValueKey('settings-test-connection'));
    await tester.ensureVisible(testButton);
    await tester.pumpAndSettle();
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(checkedAddresses.last, 'http://newbox.local:8484');
    expect(storage.getServerUrl(), 'http://oldbox.local:8484');
    expect(find.textContaining('Connection confirmed.'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(SettingsScreen)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
  });

  testWidgets('confirms sign-out before switching to a reachable server', (
    tester,
  ) async {
    final container = await pumpSettings(
      tester,
      healthCheck: (_) async => true,
    );

    await tester.enterText(
      find.byKey(const ValueKey('settings-server-url')),
      'http://newbox.local:8484/',
    );
    await tester.pump();
    final saveButton = find.byKey(const ValueKey('settings-save-server'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Switch NullFeed servers?'), findsOneWidget);
    expect(find.textContaining('This signs Alice out.'), findsOneWidget);
    expect(storage.getServerUrl(), 'http://oldbox.local:8484');
    expect(container.read(authStateProvider).currentUser?.displayName, 'Alice');

    await tester.tap(find.text('Switch server & sign out'));
    await tester.pumpAndSettle();

    expect(storage.getServerUrl(), 'http://newbox.local:8484');
    expect(storage.getSessionToken(), isNull);
    expect(storage.getSelectedUserId(), isNull);
    expect(container.read(authStateProvider).currentUser, isNull);
    verify(() => api.logout()).called(1);

    ScaffoldMessenger.of(
      tester.element(find.byType(SettingsScreen)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
  });
}
