import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nullfeed/config/constants.dart';
import 'package:nullfeed/models/feed.dart';
import 'package:nullfeed/services/catalog_cache_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late Directory hiveDir;
  late StorageService storage;
  late CatalogCacheService cache;

  setUp(() async {
    hiveDir = await setUpTestHive();
    storage = StorageService();
    await storage.setSelectedUserId('u1');
    cache = CatalogCacheService(storage: storage);
  });

  tearDown(() async {
    await tearDownTestHive(hiveDir);
  });

  group('channel list', () {
    test('returns null before anything is written', () {
      expect(cache.readChannels(), isNull);
    });

    test('round-trips the channel list through JSON', () async {
      final channels = [
        makeChannel(id: 'c1', name: 'Alpha'),
        makeChannel(id: 'c2', name: 'Beta', avatarUrl: 'https://x/a.jpg'),
      ];

      await cache.writeChannels(channels);

      expect(cache.readChannels(), channels);
    });
  });

  group('home feed', () {
    test('round-trips the home feed through JSON', () async {
      expect(cache.readHomeFeed(), isNull);

      final feed = HomeFeed(
        continueWatching: [makeFeedItem(video: makeVideo(id: 'v1'))],
        recentlyAdded: [makeFeedItem(video: makeVideo(id: 'v2'))],
      );

      await cache.writeHomeFeed(feed);

      expect(cache.readHomeFeed(), feed);
    });
  });

  group('channel detail and videos', () {
    test('round-trips a single channel keyed by id', () async {
      final channel = makeChannel(id: 'c9', name: 'Detail');

      await cache.writeChannel(channel);

      expect(cache.readChannel('c9'), channel);
      expect(cache.readChannel('other'), isNull);
    });

    test('round-trips a video list keyed by channel', () async {
      final videos = [makeVideo(id: 'v1'), makeVideo(id: 'v2')];

      await cache.writeChannelVideos('c1', videos);

      expect(cache.readChannelVideos('c1'), videos);
      expect(cache.readChannelVideos('c2'), isNull);
    });
  });

  group('profile scoping', () {
    test('one profile never reads another profile\'s cache', () async {
      await cache.writeChannels([makeChannel(id: 'c1')]);
      expect(cache.readChannels(), hasLength(1));

      await storage.setSelectedUserId('u2');
      expect(cache.readChannels(), isNull, reason: 'u2 sees nothing');

      await storage.setSelectedUserId('u1');
      expect(cache.readChannels(), hasLength(1), reason: 'u1 cache intact');
    });

    test('reads and writes are no-ops while signed out', () async {
      await storage.setSelectedUserId(null);
      await cache.writeChannels([makeChannel()]);
      expect(cache.readChannels(), isNull);

      await storage.setSelectedUserId('u1');
      expect(cache.readChannels(), isNull, reason: 'nothing was written');
    });
  });

  group('corrupt entries', () {
    test('a malformed entry reads as null instead of throwing', () async {
      // Inject a stale-schema / truncated value under our scope's key.
      await Hive.box(
        AppConstants.catalogCacheBox,
      ).put('u1::channels', 'not-json');

      expect(cache.readChannels(), isNull);
    });
  });
}
