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

/// Refreshes the three home-feed rows. Call after returning from the player
/// (any entry point) — watch positions have likely changed.
void invalidateFeedProviders(WidgetRef ref) {
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(newEpisodesProvider);
  ref.invalidate(recentlyAddedProvider);
}

final homeFeedProvider = FutureProvider<HomeFeed>((ref) async {
  final continueWatching = await ref.watch(continueWatchingProvider.future);
  final newEpisodes = await ref.watch(newEpisodesProvider.future);
  final recentlyAdded = await ref.watch(recentlyAddedProvider.future);

  return HomeFeed(
    continueWatching: continueWatching,
    newEpisodes: newEpisodes,
    recentlyAdded: recentlyAdded,
  );
});
