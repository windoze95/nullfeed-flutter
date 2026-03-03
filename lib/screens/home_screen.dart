import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/feed_provider.dart';
import '../providers/websocket_provider.dart';
import '../widgets/content_row.dart';
import '../widgets/video_card.dart';
import '../config/theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize WebSocket connection
    ref.watch(webSocketConnectionProvider);

    final continueWatching = ref.watch(continueWatchingProvider);
    final newEpisodes = ref.watch(newEpisodesProvider);
    final recentlyAdded = ref.watch(recentlyAddedProvider);

    return Scaffold(
      body: RefreshIndicator(
        color: NullFeedTheme.primaryColor,
        onRefresh: () async {
          ref.invalidate(continueWatchingProvider);
          ref.invalidate(newEpisodesProvider);
          ref.invalidate(recentlyAddedProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: const Row(
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
                  continueWatching.when(
                    data: (items) {
                      if (items.isEmpty) return const SizedBox.shrink();
                      return ContentRow(
                        title: 'Continue Watching',
                        children: items
                            .map((item) => VideoCard(
                                  video: item.video,
                                  channel: item.channel,
                                  showProgress: true,
                                ))
                            .toList(),
                      );
                    },
                    loading: () => const ContentRow(
                      title: 'Continue Watching',
                      isLoading: true,
                      children: [],
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  newEpisodes.when(
                    data: (items) {
                      if (items.isEmpty) return const SizedBox.shrink();
                      return ContentRow(
                        title: 'New Episodes',
                        children: items
                            .map((item) => VideoCard(
                                  video: item.video,
                                  channel: item.channel,
                                ))
                            .toList(),
                      );
                    },
                    loading: () => const ContentRow(
                      title: 'New Episodes',
                      isLoading: true,
                      children: [],
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  recentlyAdded.when(
                    data: (items) {
                      if (items.isEmpty) return const SizedBox.shrink();
                      return ContentRow(
                        title: 'Recently Added',
                        children: items
                            .map((item) => VideoCard(
                                  video: item.video,
                                  channel: item.channel,
                                ))
                            .toList(),
                      );
                    },
                    loading: () => const ContentRow(
                      title: 'Recently Added',
                      isLoading: true,
                      children: [],
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  // Empty state
                  if (continueWatching.valueOrNull?.isEmpty == true &&
                      newEpisodes.valueOrNull?.isEmpty == true &&
                      recentlyAdded.valueOrNull?.isEmpty == true)
                    const _EmptyHomeState(),
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
