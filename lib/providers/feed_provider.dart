import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed.dart';
import '../services/api_service.dart';

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
final homeFeedProvider = FutureProvider<HomeFeed>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getHomeFeed();
});
