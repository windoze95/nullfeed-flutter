import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/config/constants.dart';
import 'package:nullfeed/models/channel.dart';
import 'package:nullfeed/models/feed.dart';
import 'package:nullfeed/models/user.dart';
import 'package:nullfeed/models/video.dart';
import 'package:nullfeed/models/youtube_import.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/push_service.dart';
import 'package:nullfeed/services/storage_service.dart';
import 'package:nullfeed/services/websocket_service.dart';

class MockApiService extends Mock implements ApiService {}

class MockStorageService extends Mock implements StorageService {}

class MockWebSocketService extends Mock implements WebSocketService {}

class MockPushService extends Mock implements PushService {}

/// In-memory [StorageService] for widget tests.
///
/// Real Hive writes block forever inside the `testWidgets` FakeAsync zone
/// (their completion needs the real event loop), so flows that await
/// storage writes — profile select, add profile — must use this fake.
class FakeStorageService implements StorageService {
  FakeStorageService({String? serverUrl}) : _serverUrl = serverUrl;

  String? _serverUrl;
  String? _selectedUserId;
  String? _sessionToken;
  String? _deviceId;
  String _preferredQuality = '1080p';
  final Set<String> _autoOfflineChannels = {};

  @override
  String? getServerUrl() => _serverUrl;

  @override
  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
  }

  @override
  String? getSelectedUserId() => _selectedUserId;

  @override
  Future<void> setSelectedUserId(String? userId) async {
    _selectedUserId = userId;
  }

  @override
  String? getSessionToken() => _sessionToken;

  @override
  Future<void> setSessionToken(String? token) async {
    _sessionToken = token;
  }

  @override
  String? getDeviceId() => _deviceId;

  @override
  Future<void> setDeviceId(String id) async {
    _deviceId = id;
  }

  @override
  String getPreferredQuality() => _preferredQuality;

  @override
  Future<void> setPreferredQuality(String quality) async {
    _preferredQuality = quality;
  }

  @override
  Future<void> clearSession() async {
    _selectedUserId = null;
    _sessionToken = null;
  }

  @override
  Set<String> getAutoOfflineChannels() => Set.of(_autoOfflineChannels);

  @override
  Future<void> setAutoOffline(String channelId, bool enabled) async {
    if (enabled) {
      _autoOfflineChannels.add(channelId);
    } else {
      _autoOfflineChannels.remove(channelId);
    }
  }

  @override
  bool isAutoOfflineEnabled(String channelId) =>
      _autoOfflineChannels.contains(channelId);

  @override
  Future<void> clearAll() async {
    _serverUrl = null;
    _deviceId = null;
    _preferredQuality = '1080p';
    _autoOfflineChannels.clear();
    await clearSession();
  }
}

/// Registers mocktail fallback values needed by `any()` matchers in tests.
void registerTestFallbacks() {
  registerFallbackValue(<ChannelSuggestion>[]);
}

/// Initializes Hive in a fresh per-test temp directory and opens every box
/// the app uses. Returns the directory so [tearDownTestHive] can remove it.
Future<Directory> setUpTestHive() async {
  final dir = await Directory.systemTemp.createTemp('nullfeed_test_');
  Hive.init(dir.path);
  await Hive.openBox<dynamic>(AppConstants.settingsBox);
  await Hive.openBox<dynamic>(AppConstants.sessionBox);
  await Hive.openBox<dynamic>(AppConstants.offlineBox);
  await Hive.openBox<dynamic>(AppConstants.catalogCacheBox);
  return dir;
}

/// Closes all boxes, deletes them from disk, and removes the temp directory.
Future<void> tearDownTestHive(Directory dir) async {
  await Hive.deleteFromDisk();
  await Hive.close();
  if (dir.existsSync()) {
    await dir.delete(recursive: true);
  }
}

User makeUser({
  String id = 'u1',
  String displayName = 'Alice',
  String? avatarUrl,
  bool isAdmin = false,
  bool hasPin = false,
}) {
  return User(
    id: id,
    displayName: displayName,
    avatarUrl: avatarUrl,
    isAdmin: isAdmin,
    hasPin: hasPin,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

YoutubeProfile makeYoutubeProfile({
  String handle = '@mkbhd',
  String channelId = 'UC-mkbhd',
  String name = 'Marques Brownlee',
  String? avatarUrl,
  int? followerCount = 21000000,
}) {
  return YoutubeProfile(
    handle: handle,
    channelId: channelId,
    name: name,
    avatarUrl: avatarUrl,
    followerCount: followerCount,
  );
}

ChannelSuggestion makeSuggestion({
  String youtubeChannelId = 'UC-suggested',
  String name = 'Suggested Channel',
  String source = 'playlists',
  int score = 5,
}) {
  return ChannelSuggestion(
    youtubeChannelId: youtubeChannelId,
    name: name,
    source: source,
    score: score,
  );
}

Channel makeChannel({
  String id = 'c1',
  String youtubeChannelId = 'UC-c1',
  String name = 'Some Channel',
  String slug = 'some-channel',
  String? avatarUrl,
  DateTime? lastCheckedAt,
}) {
  return Channel(
    id: id,
    youtubeChannelId: youtubeChannelId,
    name: name,
    slug: slug,
    avatarUrl: avatarUrl,
    lastCheckedAt: lastCheckedAt,
  );
}

Video makeVideo({
  String id = 'v1',
  String youtubeVideoId = 'yt-v1',
  String channelId = 'c1',
  String title = 'A Video',
  int durationSeconds = 600,
  VideoStatus status = VideoStatus.complete,
  UnplayableReason? unplayableReason,
}) {
  return Video(
    id: id,
    youtubeVideoId: youtubeVideoId,
    channelId: channelId,
    title: title,
    durationSeconds: durationSeconds,
    status: status,
    unplayableReason: unplayableReason,
  );
}

FeedItem makeFeedItem({Channel? channel, Video? video}) {
  return FeedItem(
    channel: channel ?? makeChannel(),
    video: video ?? makeVideo(),
  );
}
