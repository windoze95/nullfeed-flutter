import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/models/channel.dart';
import 'package:nullfeed/models/feed.dart';
import 'package:nullfeed/models/recommendation.dart';
import 'package:nullfeed/models/video.dart';
import 'package:nullfeed/models/video_page.dart';
import 'package:nullfeed/providers/channel_provider.dart';
import 'package:nullfeed/providers/discover_provider.dart';
import 'package:nullfeed/providers/feed_provider.dart';
import 'package:nullfeed/providers/queue_provider.dart';
import 'package:nullfeed/providers/search_provider.dart';
import 'package:nullfeed/providers/session_scope_provider.dart';
import 'package:nullfeed/providers/video_provider.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/catalog_cache_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late Directory hiveDir;
  late MockApiService api;
  late FakeStorageService storage;
  late ProviderContainer container;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 40));

  setUp(() async {
    hiveDir = await setUpTestHive();
    api = MockApiService();
    storage = FakeStorageService(serverUrl: 'http://server-a:8484');
    await storage.setSelectedUserId('user-a');
    container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    container
        .read(activeSessionScopeProvider.notifier)
        .activate(serverUrl: 'http://server-a:8484', userId: 'user-a');
  });

  tearDown(() async {
    container.dispose();
    await tearDownTestHive(hiveDir);
  });

  test(
    'scope change clears every loaded user-domain provider before reload',
    () async {
      final aVideo = makeVideo(id: 'shared', title: 'Profile A video');
      final bVideo = makeVideo(id: 'shared', title: 'Profile B video');
      final aFeed = HomeFeed(recentlyAdded: [makeFeedItem(video: aVideo)]);
      final bFeed = HomeFeed(recentlyAdded: [makeFeedItem(video: bVideo)]);
      const aRecommendation = Recommendation(
        id: 'rec-a',
        channelName: 'Profile A recommendation',
        reasoning: 'A',
      );
      const bRecommendation = Recommendation(
        id: 'rec-b',
        channelName: 'Profile B recommendation',
        reasoning: 'B',
      );

      final bFeedResult = Completer<HomeFeed>();
      final bChannelsResult = Completer<List<Channel>>();
      final bDiscoverResult = Completer<List<Recommendation>>();
      final bQueueResult = Completer<VideoPage>();
      final bSearchResult = Completer<VideoPage>();
      final bVideoResult = Completer<Video>();
      var feedCalls = 0;
      var channelCalls = 0;
      var discoverCalls = 0;
      var queueCalls = 0;
      var searchCalls = 0;
      var videoCalls = 0;

      when(() => api.getHomeFeed()).thenAnswer((_) {
        feedCalls++;
        return feedCalls == 1 ? Future.value(aFeed) : bFeedResult.future;
      });
      when(() => api.getChannels()).thenAnswer((_) {
        channelCalls++;
        return channelCalls == 1
            ? Future.value([makeChannel(id: 'channel-a', name: 'Profile A')])
            : bChannelsResult.future;
      });
      when(() => api.getRecommendations()).thenAnswer((_) {
        discoverCalls++;
        return discoverCalls == 1
            ? Future.value([aRecommendation])
            : bDiscoverResult.future;
      });
      when(() => api.getQueue()).thenAnswer((_) {
        queueCalls++;
        return queueCalls == 1
            ? Future.value(VideoPage(items: [aVideo], total: 1))
            : bQueueResult.future;
      });
      when(() => api.searchVideos()).thenAnswer((_) {
        searchCalls++;
        return searchCalls == 1
            ? Future.value(VideoPage(items: [aVideo], total: 1))
            : bSearchResult.future;
      });
      when(() => api.getVideo('shared')).thenAnswer((_) {
        videoCalls++;
        return videoCalls == 1 ? Future.value(aVideo) : bVideoResult.future;
      });

      container.read(homeFeedProvider);
      container.read(channelsProvider);
      container.read(discoverProvider);
      container.read(queueProvider);
      container.read(searchProvider);
      container.read(videoDetailProvider('shared'));
      await settle();

      expect(container.read(homeFeedProvider).value, aFeed);
      expect(container.read(channelsProvider).value?.single.name, 'Profile A');
      expect(
        container.read(discoverProvider).value?.single.id,
        aRecommendation.id,
      );
      expect(container.read(queueProvider).videos.single.title, aVideo.title);
      expect(container.read(searchProvider).videos.single.title, aVideo.title);
      expect(
        container.read(videoDetailProvider('shared')).value?.title,
        aVideo.title,
      );

      await storage.setSelectedUserId('user-b');
      container
          .read(activeSessionScopeProvider.notifier)
          .activate(serverUrl: 'http://server-a:8484', userId: 'user-b');

      // Dependency rebuilds are synchronous on read: no profile-A value survives
      // while profile B's requests are deliberately held open.
      expect(container.read(homeFeedProvider).value, isNull);
      expect(container.read(channelsProvider).value, isNull);
      expect(container.read(discoverProvider).value, isNull);
      expect(container.read(queueProvider).videos, isEmpty);
      expect(container.read(searchProvider).videos, isEmpty);
      expect(container.read(videoDetailProvider('shared')).value, isNull);

      bFeedResult.complete(bFeed);
      bChannelsResult.complete([
        makeChannel(id: 'channel-b', name: 'Profile B'),
      ]);
      bDiscoverResult.complete([bRecommendation]);
      bQueueResult.complete(VideoPage(items: [bVideo], total: 1));
      bSearchResult.complete(VideoPage(items: [bVideo], total: 1));
      bVideoResult.complete(bVideo);
      await settle();

      expect(container.read(homeFeedProvider).value, bFeed);
      expect(container.read(channelsProvider).value?.single.name, 'Profile B');
      expect(
        container.read(discoverProvider).value?.single.id,
        bRecommendation.id,
      );
      expect(container.read(queueProvider).videos.single.title, bVideo.title);
      expect(container.read(searchProvider).videos.single.title, bVideo.title);
      expect(
        container.read(videoDetailProvider('shared')).value?.title,
        bVideo.title,
      );
    },
  );

  test('an old request cannot overwrite the new scope or its cache', () async {
    final aResult = Completer<HomeFeed>();
    final bResult = Completer<HomeFeed>();
    final aFeed = HomeFeed(
      recentlyAdded: [
        makeFeedItem(
          video: makeVideo(id: 'a', title: 'Late profile A'),
        ),
      ],
    );
    final bFeed = HomeFeed(
      recentlyAdded: [
        makeFeedItem(
          video: makeVideo(id: 'b', title: 'Profile B'),
        ),
      ],
    );
    var calls = 0;
    when(() => api.getHomeFeed()).thenAnswer((_) {
      calls++;
      return calls == 1 ? aResult.future : bResult.future;
    });

    container.read(homeFeedProvider);
    await Future<void>.delayed(Duration.zero);

    await storage.setSelectedUserId('user-b');
    container
        .read(activeSessionScopeProvider.notifier)
        .activate(serverUrl: 'http://server-a:8484', userId: 'user-b');
    container.read(homeFeedProvider);
    await Future<void>.delayed(Duration.zero);

    bResult.complete(bFeed);
    await settle();
    aResult.complete(aFeed);
    await settle();

    expect(container.read(homeFeedProvider).value, bFeed);
    expect(container.read(catalogCacheServiceProvider).readHomeFeed(), bFeed);
  });
}
