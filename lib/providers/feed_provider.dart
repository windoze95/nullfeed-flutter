import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed.dart';
import '../services/api_service.dart';
import '../services/catalog_cache_service.dart';

final continueWatchingProvider = FutureProvider<List<FeedItem>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getContinueWatching();
});

final newEpisodesProvider = FutureProvider<List<FeedItem>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getNewEpisodes();
});

final recentlyAddedProvider = FutureProvider<List<FeedItem>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getRecentlyAdded();
});

/// Refreshes the home feed. [homeFeedProvider] backs the home screen (one
/// request); the per-row providers stay invalidated for any surface still
/// reading them individually. Call after returning from the player (any entry
/// point) — watch positions have likely changed.
void invalidateFeedProviders(WidgetRef ref) {
  ref.invalidate(homeFeedProvider);
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(newEpisodesProvider);
  ref.invalidate(recentlyAddedProvider);
}

/// The unified home feed (all three rows in a single request). This is what
/// the home screen watches; [continueWatchingProvider] and friends remain for
/// callers that need one row at a time.
///
/// Hydrates from the per-profile cache instantly on build so launch shows the
/// last-known feed without a spinner, then refreshes in the background and
/// writes the result through to the cache. A connection error falls back to the
/// cached feed instead of surfacing; a real server error still surfaces.
class HomeFeedNotifier extends Notifier<AsyncValue<HomeFeed>> {
  @override
  AsyncValue<HomeFeed> build() {
    final cached = _cache.readHomeFeed();
    // Deferred so the refresh runs after build() returns and `state` exists.
    Future.microtask(refresh);
    return cached != null
        ? AsyncValue.data(cached)
        : const AsyncValue.loading();
  }

  ApiService get _api => ref.read(apiServiceProvider);
  CatalogCacheService get _cache => ref.read(catalogCacheServiceProvider);

  Future<void> refresh() async {
    // The build-time refresh is deferred, and screens invalidate this provider
    // while a fetch is in flight; bail if this element was disposed meanwhile.
    if (!ref.mounted) return;
    final api = _api;
    final cache = _cache;
    // Keep cached content on screen while refetching; only spin when empty.
    if (!state.hasValue) state = const AsyncValue.loading();
    try {
      final feed = await api.getHomeFeed();
      await cache.writeHomeFeed(feed);
      if (ref.mounted) state = AsyncValue.data(feed);
    } catch (e, st) {
      if (ref.mounted) {
        state = resolveCatalogRefreshError(e, st, state, cache.readHomeFeed());
      }
    }
  }
}

final homeFeedProvider =
    NotifierProvider<HomeFeedNotifier, AsyncValue<HomeFeed>>(
      HomeFeedNotifier.new,
    );
