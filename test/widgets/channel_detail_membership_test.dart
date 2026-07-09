import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/models/channel.dart';
import 'package:nullfeed/providers/session_scope_provider.dart';
import 'package:nullfeed/screens/channel_detail_screen.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/storage_service.dart';
import 'package:nullfeed/widgets/cinematic_banner.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService api;
  late FakeStorageService storage;

  setUp(() {
    api = MockApiService();
    storage = FakeStorageService();
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    required Channel Function() currentChannel,
  }) async {
    when(() => api.getChannel('c1')).thenAnswer((_) async => currentChannel());
    when(() => api.getChannelVideos('c1')).thenAnswer((_) async => const []);
    when(
      () => api.refreshChannelImages('c1'),
    ).thenAnswer((_) async => currentChannel());

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
          home: const ChannelDetailScreen(channelId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unsubscribed channel exposes a labelled Subscribe action', (
    tester,
  ) async {
    final channel = makeChannel(
      id: 'c1',
      youtubeChannelId: 'UC-c1-channel',
      name: 'Catalog Channel',
    );
    final semantics = tester.ensureSemantics();

    await pumpDetail(tester, currentChannel: () => channel);

    expect(find.text('NOT IN YOUR LIBRARY'), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Subscribe to Catalog Channel'),
      findsOneWidget,
    );
    expect(find.byType(CinematicBanner), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('subscribed channel exposes a labelled Unsubscribe action', (
    tester,
  ) async {
    final channel = makeChannel(
      id: 'c1',
      youtubeChannelId: 'UC-c1-channel',
      name: 'Library Channel',
    ).copyWith(isSubscribed: true);
    final semantics = tester.ensureSemantics();

    await pumpDetail(tester, currentChannel: () => channel);

    expect(find.text('IN YOUR LIBRARY'), findsOneWidget);
    expect(find.text('Unsubscribe'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Unsubscribe from Library Channel'),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('Subscribe updates membership through the channel provider', (
    tester,
  ) async {
    var isSubscribed = false;
    final channel = makeChannel(
      id: 'c1',
      youtubeChannelId: 'UC-c1-channel',
      name: 'Catalog Channel',
    );
    Channel current() => channel.copyWith(isSubscribed: isSubscribed);

    when(
      () =>
          api.subscribeToChannel('UC-c1-channel', trackingMode: 'FUTURE_ONLY'),
    ).thenAnswer((_) async {
      isSubscribed = true;
    });
    when(() => api.getChannels()).thenAnswer((_) async => [current()]);

    await pumpDetail(tester, currentChannel: current);
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    verify(
      () =>
          api.subscribeToChannel('UC-c1-channel', trackingMode: 'FUTURE_ONLY'),
    ).called(1);
    expect(find.text('IN YOUR LIBRARY'), findsOneWidget);
    expect(find.text('Unsubscribe'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
