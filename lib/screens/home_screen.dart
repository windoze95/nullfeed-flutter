import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed.dart';
import '../providers/feed_provider.dart';
import '../providers/websocket_provider.dart';
import '../widgets/content_row.dart';
import '../widgets/video_card.dart';
import '../config/theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Widget _buildRow({
    required String title,
    required AsyncValue<List<FeedItem>> items,
    required VoidCallback onRetry,
    bool showProgress = false,
  }) {
    return items.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return ContentRow(
          title: title,
          children: list
              .map(
                (item) => VideoCard(
                  video: item.video,
                  channel: item.channel,
                  showProgress: showProgress,
                ),
              )
              .toList(),
        );
      },
      loading: () =>
          ContentRow(title: title, isLoading: true, children: const []),
      error: (error, _) => ContentRow(
        title: title,
        errorText: '$error',
        onRetry: onRetry,
        children: const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize WebSocket connection
    ref.watch(webSocketConnectionProvider);

    final continueWatching = ref.watch(continueWatchingProvider);
    final newEpisodes = ref.watch(newEpisodesProvider);
    final recentlyAdded = ref.watch(recentlyAddedProvider);

    final rows = [continueWatching, newEpisodes, recentlyAdded];
    final allEmpty = rows.every(
      (row) => row.hasValue && !row.hasError && (row.value?.isEmpty ?? false),
    );

    Future<void> refresh() async {
      try {
        await Future.wait([
          ref.refresh(continueWatchingProvider.future),
          ref.refresh(newEpisodesProvider.future),
          ref.refresh(recentlyAddedProvider.future),
        ]);
      } catch (_) {
        // Each row renders its own inline error state.
      }
    }

    return Scaffold(
      body: RefreshIndicator(
        color: NullFeedTheme.primaryColor,
        onRefresh: refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverAppBar(
              floating: true,
              title: Row(
                children: [
                  Icon(
                    Icons.rss_feed,
                    color: NullFeedTheme.primaryColor,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text('NullFeed'),
                ],
              ),
              backgroundColor: NullFeedTheme.backgroundColor,
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _buildRow(
                    title: 'Continue Watching',
                    items: continueWatching,
                    onRetry: () => ref.invalidate(continueWatchingProvider),
                    showProgress: true,
                  ),
                  _buildRow(
                    title: 'New Episodes',
                    items: newEpisodes,
                    onRetry: () => ref.invalidate(newEpisodesProvider),
                  ),
                  _buildRow(
                    title: 'Recently Added',
                    items: recentlyAdded,
                    onRetry: () => ref.invalidate(recentlyAddedProvider),
                  ),
                  if (allEmpty) const _EmptyHomeState(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.subscriptions_outlined,
              size: 64,
              color: NullFeedTheme.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Your feed is empty',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Subscribe to channels in the Library tab to start building your feed.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
