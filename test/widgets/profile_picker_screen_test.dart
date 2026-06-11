import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/providers/auth_provider.dart';
import 'package:nullfeed/screens/profile_picker_screen.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/storage_service.dart';
import 'package:nullfeed/widgets/pin_entry_dialog.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService api;
  late FakeStorageService storage;

  setUp(() {
    api = MockApiService();
    storage = FakeStorageService();
  });

  /// Pumps the picker; with a configured server the profile grid shows.
  Future<ProviderContainer> pumpPicker(
    WidgetTester tester, {
    bool withServerUrl = true,
  }) async {
    if (withServerUrl) {
      storage = FakeStorageService(serverUrl: 'http://test.local:8484');
    }
    final container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePickerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('shows the server setup view when no server is configured', (
    tester,
  ) async {
    await pumpPicker(tester, withServerUrl: false);

    expect(find.text('Connect to your server'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    verifyNever(() => api.getProfiles());
  });

  testWidgets('renders profile cards with a PIN badge for locked profiles', (
    tester,
  ) async {
    when(() => api.getProfiles()).thenAnswer(
      (_) async => [
        makeUser(),
        makeUser(id: 'u2', displayName: 'Bob', hasPin: true),
      ],
    );

    await pumpPicker(tester);

    expect(find.text('Who\'s watching?'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Add Profile'), findsOneWidget);
    // Only Bob has a PIN, so exactly one lock badge.
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('tapping a PIN-protected profile opens the PIN dialog', (
    tester,
  ) async {
    final bob = makeUser(id: 'u2', displayName: 'Bob', hasPin: true);
    when(() => api.getProfiles()).thenAnswer((_) async => [bob]);
    when(
      () => api.selectProfile('u2', pin: '1111'),
    ).thenThrow(const ApiException(message: 'Incorrect PIN', statusCode: 403));
    when(
      () => api.selectProfile('u2', pin: '1234'),
    ).thenAnswer((_) async => (user: bob, token: 'tok-2'));

    final container = await pumpPicker(tester);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.byType(PinEntryDialog), findsOneWidget);

    // Wrong PIN: inline error, dialog stays open, nobody signed in.
    await tester.enterText(
      find.descendant(
        of: find.byType(PinEntryDialog),
        matching: find.byType(TextField),
      ),
      '1111',
    );
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect PIN'), findsOneWidget);
    expect(find.byType(PinEntryDialog), findsOneWidget);
    expect(container.read(authStateProvider).currentUser, isNull);

    // Correct PIN: signs in (asserted via auth state, since the router
    // normally swaps the screen out from under the dialog).
    await tester.enterText(
      find.descendant(
        of: find.byType(PinEntryDialog),
        matching: find.byType(TextField),
      ),
      '1234',
    );
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(container.read(authStateProvider).currentUser?.id, 'u2');
    expect(storage.getSessionToken(), 'tok-2');
    expect(storage.getSelectedUserId(), 'u2');
  });

  testWidgets('load failure shows an inline error card with Retry', (
    tester,
  ) async {
    when(() => api.getProfiles()).thenThrow(
      const ApiException(
        message: 'Could not reach the server. Check your connection.',
        isConnectionError: true,
      ),
    );

    await pumpPicker(tester);

    // The layout is kept: header plus an inline error card, not a full
    // replacement.
    expect(find.text('Who\'s watching?'), findsOneWidget);
    expect(
      find.text('Could not reach the server. Check your connection.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Change Server'), findsOneWidget);

    // Retry reloads and renders the grid.
    when(() => api.getProfiles()).thenAnswer((_) async => [makeUser()]);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a select error keeps the profile grid intact', (tester) async {
    when(() => api.getProfiles()).thenAnswer(
      (_) async => [makeUser(), makeUser(id: 'u2', displayName: 'Bob')],
    );
    when(() => api.selectProfile('u1', pin: null)).thenThrow(
      const ApiException(message: 'Server unavailable', statusCode: 503),
    );

    final container = await pumpPicker(tester);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Server unavailable'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(container.read(authStateProvider).currentUser, isNull);

    // Let the SnackBar's auto-dismiss timer expire before the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
