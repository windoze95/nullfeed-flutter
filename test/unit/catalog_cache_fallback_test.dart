import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/models/feed.dart';
import 'package:nullfeed/providers/channel_provider.dart';
import 'package:nullfeed/providers/feed_provider.dart';
import 'package:nullfeed/providers/session_scope_provider.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/catalog_cache_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late Directory hiveDir;
  late MockApiService api;
  late FakeStorageService storage;

  const connectionError = ApiException(
    message: 'Could not reach the server. Check your connection.',
    isConnectionError: true,
  );
  const serverError = ApiException(message: 'boom', statusCode: 500);

  setUp(() async {
    hiveDir = await setUpTestHive();
    api = MockApiService();
    storage = FakeStorageService(serverUrl: 'http://server-a:8484');
    await storage.setSelectedUserId('u1');
  });

  tearDown(() async {
    await tearDownTestHive(hiveDir);
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(activeSessionScopeProvider.notifier)
        .activate(serverUrl: 'http://server-a:8484', userId: 'u1');
    return container;
  }

  CatalogCacheService cacheOf(ProviderContainer c) =>
      c.read(catalogCacheServiceProvider);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  group('channelsProvider', () {
    test('writes through to the cache on a successful load', () async {
      final channels = [makeChannel(id: 'c1')];
      when(() => api.getChannels()).thenAnswer((_) async => channels);
      final container = createContainer();

      await container.read(channelsProvider.notifier).load();
      await settle();

      expect(container.read(channelsProvider).value, channels);
      expect(cacheOf(container).readChannels(), channels);
    });

    test('falls back to cached channels on a connection error', () async {
      final cached = [makeChannel(id: 'c1', name: 'Cached')];
      final container = createContainer();
      await cacheOf(container).writeChannels(cached);
      when(() => api.getChannels()).thenThrow(connectionError);

      await container.read(channelsProvider.notifier).load();
      await settle();

      final state = container.read(channelsProvider);
      expect(state.hasError, isFalse);
      expect(state.value, cached);
    });

    test('surfaces a real server error', () async {
      final container = createContainer();
      when(() => api.getChannels()).thenThrow(serverError);

      await container.read(channelsProvider.notifier).load();
      await settle();

      expect(container.read(channelsProvider).hasError, isTrue);
    });

    test('surfaces a connection error when nothing is cached', () async {
      final container = createContainer();
      when(() => api.getChannels()).thenThrow(connectionError);

      await container.read(channelsProvider.notifier).load();
      await settle();

      expect(container.read(channelsProvider).hasError, isTrue);
    });
  });

  group('homeFeedProvider', () {
    test('hydrates from cache instantly, then refreshes through', () async {
      final cachedFeed = HomeFeed(recentlyAdded: [makeFeedItem()]);
      final fresh = HomeFeed(
        newEpisodes: [makeFeedItem(video: makeVideo(id: 'v2'))],
      );
      final container = createContainer();
      await cacheOf(container).writeHomeFeed(cachedFeed);
      when(() => api.getHomeFeed()).thenAnswer((_) async => fresh);

      // The very first read (build) shows cached content without a spinner.
      expect(container.read(homeFeedProvider).value, cachedFeed);

      await container.read(homeFeedProvider.notifier).refresh();
      await settle();

      expect(container.read(homeFeedProvider).value, fresh);
      expect(cacheOf(container).readHomeFeed(), fresh);
    });

    test('falls back to the cached feed on a connection error', () async {
      final cachedFeed = HomeFeed(recentlyAdded: [makeFeedItem()]);
      final container = createContainer();
      await cacheOf(container).writeHomeFeed(cachedFeed);
      when(() => api.getHomeFeed()).thenThrow(connectionError);

      await container.read(homeFeedProvider.notifier).refresh();
      await settle();

      final state = container.read(homeFeedProvider);
      expect(state.hasError, isFalse);
      expect(state.value, cachedFeed);
    });
  });

  group('channelVideosProvider (family)', () {
    test('falls back to cached videos on a connection error', () async {
      final cached = [makeVideo(id: 'v1'), makeVideo(id: 'v2')];
      final container = createContainer();
      await cacheOf(container).writeChannelVideos('c1', cached);
      when(() => api.getChannelVideos('c1')).thenThrow(connectionError);

      await container.read(channelVideosProvider('c1').notifier).refresh();
      await settle();

      final state = container.read(channelVideosProvider('c1'));
      expect(state.hasError, isFalse);
      expect(state.value, cached);
    });

    test('writes through and is scoped per channel', () async {
      final videos = [makeVideo(id: 'v9')];
      final container = createContainer();
      when(() => api.getChannelVideos('c1')).thenAnswer((_) async => videos);

      await container.read(channelVideosProvider('c1').notifier).refresh();
      await settle();

      expect(container.read(channelVideosProvider('c1')).value, videos);
      expect(cacheOf(container).readChannelVideos('c1'), videos);
      expect(cacheOf(container).readChannelVideos('c2'), isNull);
    });
  });
}
