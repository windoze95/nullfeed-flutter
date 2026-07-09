import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/models/channel.dart';
import 'package:nullfeed/providers/channel_provider.dart';
import 'package:nullfeed/providers/session_scope_provider.dart';
import 'package:nullfeed/screens/library_screen.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService api;
  late FakeStorageService storage;

  setUp(() {
    api = MockApiService();
    storage = FakeStorageService();
  });

  Future<ProviderContainer> pumpLibrary(
    WidgetTester tester,
    List<Channel> channels,
  ) async {
    when(() => api.getChannels()).thenAnswer((_) async => channels);
    final container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(activeSessionScopeProvider.notifier)
        .activate(serverUrl: 'http://test.local:8484', userId: 'u1');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NullFeedTheme.darkTheme,
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('Library only renders channels subscribed by this profile', (
    tester,
  ) async {
    final subscribed = makeChannel(
      id: 'followed',
      name: 'Followed Channel',
    ).copyWith(isSubscribed: true);
    final globalOnly = makeChannel(
      id: 'catalog',
      name: 'Global Catalog Channel',
    );

    final container = await pumpLibrary(tester, [globalOnly, subscribed]);

    expect(find.text('Followed Channel'), findsOneWidget);
    expect(find.text('Global Catalog Channel'), findsNothing);
    // Search/discovery still receive the complete global catalog.
    expect(container.read(channelsProvider).value, [globalOnly, subscribed]);
    expect(container.read(subscribedChannelsProvider).value, [subscribed]);
  });

  testWidgets('empty Library offers an actionable, explained add flow', (
    tester,
  ) async {
    await pumpLibrary(tester, [
      makeChannel(id: 'catalog', name: 'Not Followed'),
    ]);

    expect(find.text('Follow your first channel'), findsOneWidget);
    expect(find.text('Add your first channel'), findsOneWidget);
    expect(find.text('Not Followed'), findsNothing);

    await tester.ensureVisible(find.text('Add your first channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your first channel'));
    await tester.pumpAndSettle();

    expect(find.text('Add a YouTube channel'), findsOneWidget);
    expect(find.text('Channel link or @handle'), findsOneWidget);
    expect(find.text('Add to Library'), findsOneWidget);

    await tester.tap(find.text('Add to Library'));
    await tester.pump();
    expect(
      find.text('Enter a channel URL, @handle, or channel ID.'),
      findsOneWidget,
    );
    verifyNever(
      () => api.subscribeToChannel(
        any(),
        trackingMode: any(named: 'trackingMode'),
      ),
    );
  });
}
