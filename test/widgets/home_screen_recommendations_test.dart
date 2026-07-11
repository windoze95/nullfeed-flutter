import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/models/channel.dart';
import 'package:nullfeed/models/feed.dart';
import 'package:nullfeed/models/recommendation.dart';
import 'package:nullfeed/screens/home_screen.dart';
import 'package:nullfeed/providers/session_scope_provider.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

Recommendation makeRecommendation({
  String id = 'r1',
  String channelName = 'Veritasium',
  String youtubeChannelId = 'UC-veritasium',
  String reasoning = 'Because you watch a lot of science explainers.',
}) {
  return Recommendation(
    id: id,
    channelName: channelName,
    youtubeChannelId: youtubeChannelId,
    reasoning: reasoning,
  );
}

void main() {
  late MockApiService api;
  late FakeStorageService storage;

  setUp(() {
    api = MockApiService();
    storage = FakeStorageService();
    // Home always loads the unified feed; keep it empty so these tests focus on
    // the recommendations rail. Signed out (no selected profile), the catalog
    // cache is a no-op, so no Hive setup is needed.
    when(() => api.getHomeFeed()).thenAnswer((_) async => const HomeFeed());
  });

  Future<void> pumpHome(WidgetTester tester) async {
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
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> revealRecommendations(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the rail with each channel and its reasoning', (
    tester,
  ) async {
    when(() => api.getRecommendations()).thenAnswer(
      (_) async => [
        makeRecommendation(
          channelName: 'Veritasium',
          reasoning: 'Because you watch science explainers.',
        ),
      ],
    );

    await pumpHome(tester);
    await revealRecommendations(tester);

    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('Veritasium'), findsOneWidget);
    expect(find.text('Because you watch science explainers.'), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
  });

  testWidgets('omits the rail entirely when there are no recommendations', (
    tester,
  ) async {
    when(() => api.getRecommendations()).thenAnswer((_) async => const []);

    await pumpHome(tester);

    expect(find.text('Recommended for you'), findsNothing);
    expect(find.text('Subscribe'), findsNothing);
  });

  testWidgets('tapping Subscribe subscribes and dismisses the recommendation', (
    tester,
  ) async {
    when(() => api.getRecommendations()).thenAnswer(
      (_) async => [
        makeRecommendation(
          id: 'r1',
          channelName: 'Veritasium',
          youtubeChannelId: 'UC-x',
        ),
      ],
    );
    when(() => api.getChannels()).thenAnswer((_) async => const <Channel>[]);
    when(
      () => api.subscribeToChannel(
        any(),
        trackingMode: any(named: 'trackingMode'),
      ),
    ).thenAnswer((_) async {});
    when(() => api.dismissRecommendation(any())).thenAnswer((_) async {});

    await pumpHome(tester);
    await revealRecommendations(tester);

    // The rail sits below the (tall) empty-feed state, so bring the button into
    // view before tapping it.
    await tester.ensureVisible(find.text('Subscribe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    verify(
      () => api.subscribeToChannel('UC-x', trackingMode: 'FUTURE_ONLY'),
    ).called(1);
    verify(() => api.dismissRecommendation('r1')).called(1);
    // The subscribe confirmation shows and the card is removed from the rail.
    expect(find.text('Subscribed to Veritasium'), findsOneWidget);
    expect(find.text('Recommended for you'), findsNothing);

    // Let the SnackBar's auto-dismiss timer expire before the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a 404 when clearing the recommendation is treated as already-cleared',
    (tester) async {
      when(() => api.getRecommendations()).thenAnswer(
        (_) async => [
          makeRecommendation(
            id: 'r1',
            channelName: 'Veritasium',
            youtubeChannelId: 'UC-x',
          ),
        ],
      );
      when(() => api.getChannels()).thenAnswer((_) async => const <Channel>[]);
      when(
        () => api.subscribeToChannel(
          any(),
          trackingMode: any(named: 'trackingMode'),
        ),
      ).thenAnswer((_) async {});
      // The recommendation is already gone server-side (e.g. cleared by the
      // staleness sweep) — dismiss 404s.
      when(() => api.dismissRecommendation(any())).thenThrow(
        const ApiException(
          message: 'Recommendation not found',
          statusCode: 404,
        ),
      );

      await pumpHome(tester);
      await revealRecommendations(tester);
      await tester.ensureVisible(find.text('Subscribe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subscribe'));
      await tester.pumpAndSettle();

      // The card is cleared and NO "could not be cleared" error is shown.
      expect(find.text('Subscribed to Veritasium'), findsOneWidget);
      expect(find.text('Recommended for you'), findsNothing);
      expect(find.textContaining('could not be cleared'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );
}
