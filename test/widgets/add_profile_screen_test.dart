import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/models/youtube_import.dart';
import 'package:nullfeed/providers/auth_provider.dart';
import 'package:nullfeed/screens/add_profile_screen.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService api;
  late FakeStorageService storage;

  setUpAll(registerTestFallbacks);

  setUp(() {
    api = MockApiService();
    storage = FakeStorageService(serverUrl: 'http://test.local:8484');
  });

  Future<ProviderContainer> pumpAddProfile(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(path: '/add', builder: (_, _) => const AddProfileScreen()),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home-screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    return container;
  }

  Finder handleField() =>
      find.widgetWithText(TextField, '@handle or channel URL');

  /// Scrolls the screen's ListView until the (lazily built) create button
  /// exists, then makes sure it is fully visible.
  Future<void> scrollToCreateButton(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Create Profile'),
      200,
      // The first Scrollable is the screen's ListView (text fields nest
      // their own inner scrollables).
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('YouTube import happy path creates, subscribes, and navigates', (
    tester,
  ) async {
    final profile = makeYoutubeProfile();
    final suggestions = [
      makeSuggestion(youtubeChannelId: 'UC-one', name: 'Channel One'),
      makeSuggestion(
        youtubeChannelId: 'UC-two',
        name: 'Channel Two',
        source: 'featured',
        score: 100,
      ),
    ];
    final created = makeUser(id: 'u9', displayName: 'Marques Brownlee');
    when(
      () => api.resolveYoutubeHandle('@mkbhd'),
    ).thenAnswer((_) async => profile);
    when(
      () => api.getYoutubeSuggestions('@mkbhd'),
    ).thenAnswer((_) async => suggestions);
    when(
      () => api.createProfile(
        youtubeHandle: '@mkbhd',
        displayName: 'Marques Brownlee',
        pin: null,
      ),
    ).thenAnswer((_) async => created);
    when(
      () => api.selectProfile('u9', pin: null),
    ).thenAnswer((_) async => (user: created, token: 'tok-9'));
    when(() => api.subscribeBulk(any())).thenAnswer(
      (_) async => const [
        BulkSubscribeResult(youtubeChannelId: 'UC-one', status: 'subscribed'),
        BulkSubscribeResult(
          youtubeChannelId: 'UC-two',
          status: 'already_subscribed',
        ),
      ],
    );
    when(() => api.getMe()).thenAnswer((_) async => created);

    final container = await pumpAddProfile(tester);

    // Look up the handle: identity preview + suggestions appear and the name
    // field auto-fills.
    await tester.enterText(handleField(), '@mkbhd');
    await tester.tap(find.text('Lookup'));
    await tester.pumpAndSettle();

    expect(find.text('Marques Brownlee'), findsAtLeastNWidgets(1));
    expect(find.text('21.0M subscribers'), findsOneWidget);
    expect(find.text('Channel One'), findsOneWidget);
    expect(find.text('Channel Two'), findsOneWidget);
    expect(find.text('From public playlists'), findsOneWidget);
    expect(find.text('Featured channel'), findsOneWidget);
    expect(find.text('0 of 2 selected'), findsOneWidget);

    // Inferred public channels are opt-in; nothing is followed silently.
    final checkboxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(checkboxes.every((tile) => !(tile.value ?? false)), isTrue);
    await tester.tap(find.text('Channel One'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 selected'), findsOneWidget);
    await tester.tap(find.text('Channel Two'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 selected'), findsOneWidget);

    // Create: profile is created from the handle, selected, channels
    // followed, and the router lands on home.
    await scrollToCreateButton(tester);
    await tester.tap(find.text('Create Profile'));
    await tester.pumpAndSettle();

    expect(find.text('home-screen'), findsOneWidget);
    expect(find.text('Followed 2 channels'), findsOneWidget);

    final bulkItems =
        verify(() => api.subscribeBulk(captureAny())).captured.single
            as List<ChannelSuggestion>;
    expect(bulkItems.map((item) => item.youtubeChannelId), [
      'UC-one',
      'UC-two',
    ]);
    expect(storage.getSessionToken(), 'tok-9');
    expect(storage.getSelectedUserId(), 'u9');
    expect(container.read(authStateProvider).currentUser?.id, 'u9');

    // Let the SnackBar's auto-dismiss timer expire before the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed lookup shows an inline error and no preview', (
    tester,
  ) async {
    when(() => api.resolveYoutubeHandle('@nope')).thenThrow(
      const ApiException(
        message: 'Could not resolve YouTube handle',
        statusCode: 502,
      ),
    );

    await pumpAddProfile(tester);

    await tester.enterText(handleField(), '@nope');
    await tester.tap(find.text('Lookup'));
    await tester.pumpAndSettle();

    expect(find.text('Could not resolve YouTube handle'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    verifyNever(
      () => api.createProfile(
        youtubeHandle: any(named: 'youtubeHandle'),
        displayName: any(named: 'displayName'),
        pin: any(named: 'pin'),
      ),
    );
  });

  testWidgets('creates a plain profile with a PIN and navigates home', (
    tester,
  ) async {
    final created = makeUser(
      id: 'u5',
      displayName: 'Kid Profile',
      hasPin: true,
    );
    when(
      () => api.createProfile(displayName: 'Kid Profile', pin: '1234'),
    ).thenAnswer((_) async => created);
    when(
      () => api.selectProfile('u5', pin: '1234'),
    ).thenAnswer((_) async => (user: created, token: 'tok-5'));
    when(() => api.getMe()).thenAnswer((_) async => created);

    final container = await pumpAddProfile(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'Kid Profile',
    );
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '1234');
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm PIN'),
      '1234',
    );
    await scrollToCreateButton(tester);
    await tester.tap(find.text('Create Profile'));
    await tester.pumpAndSettle();

    expect(find.text('home-screen'), findsOneWidget);
    expect(container.read(authStateProvider).currentUser?.id, 'u5');
    expect(storage.getSessionToken(), 'tok-5');
    verifyNever(() => api.subscribeBulk(any()));
  });

  testWidgets('mismatched PIN confirmation blocks creation', (tester) async {
    await pumpAddProfile(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'Kid Profile',
    );
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '1234');
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm PIN'),
      '9999',
    );
    await scrollToCreateButton(tester);
    await tester.tap(find.text('Create Profile'));
    await tester.pumpAndSettle();

    expect(find.text('PINs do not match'), findsOneWidget);
    verifyNever(
      () => api.createProfile(
        displayName: any(named: 'displayName'),
        pin: any(named: 'pin'),
      ),
    );
  });
}
