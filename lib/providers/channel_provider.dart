import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/constants.dart';
import '../models/channel.dart';
import '../models/video.dart';
import '../services/api_service.dart';
import '../services/catalog_cache_service.dart';
import 'session_scope_provider.dart';

/// The global channel catalog, annotated by the API with this profile's
/// `isSubscribed` membership state. Hydrates from the per-profile cache
/// instantly, then refreshes in the background and writes the result through
/// to the cache. A connection error falls back to the cache; a real server
/// error still surfaces.
class ChannelsNotifier extends Notifier<AsyncValue<List<Channel>>> {
  int _requestId = 0;

  @override
  AsyncValue<List<Channel>> build() {
    final scope = ref.watch(activeSessionScopeProvider);
    _requestId++;
    if (scope == null) return const AsyncValue.loading();
    final cached = _cache.readChannels();
    // Deferred so the load runs after build() returns and `state` exists.
    Future.microtask(load);
    return cached != null
        ? AsyncValue.data(cached)
        : const AsyncValue.loading();
  }

  ApiService get _api => ref.read(apiServiceProvider);
  CatalogCacheService get _cache => ref.read(catalogCacheServiceProvider);

  Future<void> load() async {
    // The build-time load is deferred, and screens invalidate this provider
    // while a fetch is in flight; bail if this element was disposed meanwhile.
    if (!ref.mounted) return;
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) {
      state = const AsyncValue.loading();
      return;
    }
    final requestId = ++_requestId;
    final api = _api;
    final cache = _cache;
    // Keep cached channels on screen while refetching; only spin when empty.
    if (!state.hasValue) state = const AsyncValue.loading();
    try {
      final channels = await api.getChannels();
      if (!ref.mounted ||
          requestId != _requestId ||
          ref.read(activeSessionScopeProvider) != scope) {
        return;
      }
      await cache.writeChannels(channels);
      if (ref.mounted &&
          requestId == _requestId &&
          ref.read(activeSessionScopeProvider) == scope) {
        state = AsyncValue.data(channels);
      }
    } catch (e, st) {
      if (ref.mounted && requestId == _requestId) {
        state = resolveCatalogRefreshError(e, st, state, cache.readChannels());
      }
    }
  }

  /// Subscribes and reloads. Throws on failure so callers surface the error
  /// locally — a failed subscribe must not replace the loaded channel list
  /// with an error state.
  Future<void> subscribe(
    String youtubeUrl, {
    String trackingMode = 'FUTURE_ONLY',
  }) async {
    await _api.subscribeToChannel(youtubeUrl, trackingMode: trackingMode);
    await load();
  }

  /// Unsubscribes and reloads. Throws on failure (see [subscribe]).
  Future<void> unsubscribe(String channelId) async {
    await _api.unsubscribeFromChannel(channelId);
    await load();
  }
}

final channelsProvider =
    NotifierProvider<ChannelsNotifier, AsyncValue<List<Channel>>>(
      ChannelsNotifier.new,
    );

/// The active profile's Library membership.
///
/// `GET /channels` is deliberately a global catalog endpoint, so consumers
/// that represent the user's Library must filter on `isSubscribed` instead of
/// assuming every returned channel belongs to the profile.
final subscribedChannelsProvider = Provider<AsyncValue<List<Channel>>>((ref) {
  return ref
      .watch(channelsProvider)
      .whenData(
        (channels) => channels
            .where((channel) => channel.isSubscribed)
            .toList(growable: false),
      );
});

/// A single channel's detail. Hydrates from the per-profile cache instantly so
/// the channel screen header shows offline, then refreshes and writes through.
/// Connection errors fall back to the cache; real errors surface.
class ChannelDetailNotifier extends Notifier<AsyncValue<Channel>> {
  late final String _channelId;
  int _requestId = 0;

  void init(String channelId) => _channelId = channelId;

  @override
  AsyncValue<Channel> build() {
    final scope = ref.watch(activeSessionScopeProvider);
    _requestId++;
    if (scope == null) return const AsyncValue.loading();
    final cached = _cache.readChannel(_channelId);
    Future.microtask(refresh);
    return cached != null
        ? AsyncValue.data(cached)
        : const AsyncValue.loading();
  }

  ApiService get _api => ref.read(apiServiceProvider);
  CatalogCacheService get _cache => ref.read(catalogCacheServiceProvider);

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) {
      state = const AsyncValue.loading();
      return;
    }
    final requestId = ++_requestId;
    final api = _api;
    final cache = _cache;
    if (!state.hasValue) state = const AsyncValue.loading();
    try {
      final channel = await api.getChannel(_channelId);
      if (!ref.mounted ||
          requestId != _requestId ||
          ref.read(activeSessionScopeProvider) != scope) {
        return;
      }
      await cache.writeChannel(channel);
      if (ref.mounted &&
          requestId == _requestId &&
          ref.read(activeSessionScopeProvider) == scope) {
        state = AsyncValue.data(channel);
      }
    } catch (e, st) {
      if (ref.mounted && requestId == _requestId) {
        state = resolveCatalogRefreshError(
          e,
          st,
          state,
          cache.readChannel(_channelId),
        );
      }
    }
  }
}

final channelDetailProvider =
    NotifierProvider.family<ChannelDetailNotifier, AsyncValue<Channel>, String>(
      (channelId) {
        final notifier = ChannelDetailNotifier();
        notifier.init(channelId);
        return notifier;
      },
    );

/// A channel's video list. Hydrates from the per-profile cache instantly so the
/// channel screen lists last-known videos offline, then refreshes and writes
/// through. Connection errors fall back to the cache; real errors surface.
class ChannelVideosNotifier extends Notifier<AsyncValue<List<Video>>> {
  late final String _channelId;
  int _requestId = 0;

  void init(String channelId) => _channelId = channelId;

  @override
  AsyncValue<List<Video>> build() {
    final scope = ref.watch(activeSessionScopeProvider);
    _requestId++;
    if (scope == null) return const AsyncValue.loading();
    final cached = _cache.readChannelVideos(_channelId);
    Future.microtask(refresh);
    return cached != null
        ? AsyncValue.data(cached)
        : const AsyncValue.loading();
  }

  ApiService get _api => ref.read(apiServiceProvider);
  CatalogCacheService get _cache => ref.read(catalogCacheServiceProvider);

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) {
      state = const AsyncValue.loading();
      return;
    }
    final requestId = ++_requestId;
    final api = _api;
    final cache = _cache;
    if (!state.hasValue) state = const AsyncValue.loading();
    try {
      final videos = await api.getChannelVideos(_channelId);
      if (!ref.mounted ||
          requestId != _requestId ||
          ref.read(activeSessionScopeProvider) != scope) {
        return;
      }
      await cache.writeChannelVideos(_channelId, videos);
      if (ref.mounted &&
          requestId == _requestId &&
          ref.read(activeSessionScopeProvider) == scope) {
        state = AsyncValue.data(videos);
        _prewarm(videos);
      }
    } catch (e, st) {
      if (ref.mounted && requestId == _requestId) {
        state = resolveCatalogRefreshError(
          e,
          st,
          state,
          cache.readChannelVideos(_channelId),
        );
      }
    }
  }

  /// Best-effort: ask the backend to pre-generate previews for the first few
  /// not-yet-playable videos so opening one lands on the ready-preview fast
  /// path. Skips already-downloaded / already-previewed videos.
  void _prewarm(List<Video> videos) {
    final ids = videos
        .where((v) => !v.isPlayable)
        .take(AppConstants.prewarmBatchSize)
        .map((v) => v.id)
        .toList();
    if (ids.isEmpty) return;
    // Detached and best-effort: a prewarm failure must never affect the load,
    // so the call is deferred (swallowing even a synchronous throw) and ignored.
    Future(() => _api.prewarmPreviews(ids)).ignore();
  }
}

final channelVideosProvider =
    NotifierProvider.family<
      ChannelVideosNotifier,
      AsyncValue<List<Video>>,
      String
    >((channelId) {
      final notifier = ChannelVideosNotifier();
      notifier.init(channelId);
      return notifier;
    });
