import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../config/constants.dart';
import '../models/channel.dart';
import '../models/feed.dart';
import '../models/video.dart';
import 'api_service.dart';
import 'storage_service.dart';

final catalogCacheServiceProvider = Provider<CatalogCacheService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return CatalogCacheService(storage: storage);
});

/// Maps a failed catalog refresh to the next [AsyncValue], shared by the
/// cache-backed catalog notifiers.
///
/// A connection error ([ApiException.isConnectionError]) falls back to [cached]
/// when present, otherwise keeps the [current] value if there is one, and only
/// surfaces the error when there's nothing to show (a cold offline start). Any
/// other error — a real server error — surfaces.
AsyncValue<T> resolveCatalogRefreshError<T>(
  Object error,
  StackTrace stackTrace,
  AsyncValue<T> current,
  T? cached,
) {
  if (error is ApiException && error.isConnectionError) {
    if (cached != null) return AsyncValue.data(cached);
    if (current.hasValue) return current;
  }
  return AsyncValue.error(error, stackTrace);
}

/// Persists the last-good catalog — the channel list, the home feed, and
/// per-channel video/detail snapshots — to Hive so the app stays browsable
/// when the server is unreachable.
///
/// Entries are the Freezed models' JSON (`toJson`) stored as a string, which
/// round-trips through the same `fromJson` the network path uses. Every key is
/// scoped to the active profile ([StorageService.getSelectedUserId]) so
/// switching profiles never surfaces another profile's catalog, and a re-login
/// as the same profile keeps its cache. Reads and writes are no-ops while
/// signed out (no scope).
class CatalogCacheService {
  CatalogCacheService({required this.storage});

  final StorageService storage;

  Box get _box => Hive.box(AppConstants.catalogCacheBox);

  /// The active profile's id, or null when signed out.
  String? get _scope => storage.getSelectedUserId();

  /// Builds a profile-scoped key, or null when there is no active profile (in
  /// which case callers skip the read/write entirely).
  String? _key(String suffix) {
    final scope = _scope;
    return scope == null ? null : '$scope::$suffix';
  }

  // --- Channel list -------------------------------------------------------

  List<Channel>? readChannels() =>
      _readList(_key('channels'), Channel.fromJson);

  Future<void> writeChannels(List<Channel> channels) =>
      _writeJson(_key('channels'), [for (final c in channels) c.toJson()]);

  // --- Home feed ----------------------------------------------------------

  HomeFeed? readHomeFeed() => _readObject(_key('home_feed'), HomeFeed.fromJson);

  Future<void> writeHomeFeed(HomeFeed feed) =>
      _writeJson(_key('home_feed'), feed.toJson());

  // --- Channel detail -----------------------------------------------------

  Channel? readChannel(String channelId) =>
      _readObject(_key('channel::$channelId'), Channel.fromJson);

  Future<void> writeChannel(Channel channel) =>
      _writeJson(_key('channel::${channel.id}'), channel.toJson());

  // --- Per-channel video list ---------------------------------------------

  List<Video>? readChannelVideos(String channelId) =>
      _readList(_key('channel_videos::$channelId'), Video.fromJson);

  Future<void> writeChannelVideos(String channelId, List<Video> videos) =>
      _writeJson(_key('channel_videos::$channelId'), [
        for (final v in videos) v.toJson(),
      ]);

  // --- Generic helpers ----------------------------------------------------

  String? _read(String? key) {
    if (key == null) return null;
    final value = _box.get(key);
    return value is String ? value : null;
  }

  Future<void> _writeJson(String? key, Object json) async {
    if (key == null) return;
    await _box.put(key, jsonEncode(json));
  }

  T? _readObject<T>(String? key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _read(key);
    if (raw == null) return null;
    try {
      return fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      // Corrupt or stale-schema entry — ignore and fall through to a refetch.
      return null;
    }
  }

  List<T>? _readList<T>(
    String? key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = _read(key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List)
          .map((e) => fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
