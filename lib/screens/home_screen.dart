import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed.dart';
import '../providers/feed_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../widgets/content_row.dart';
import '../widgets/video_card.dart';
import '../config/theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Widget _buildFeed(HomeFeed feed) {
    final allEmpty =
        feed.continueWatching.isEmpty &&
        feed.newEpisodes.isEmpty &&
        feed.recentlyAdded.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        if (feed.continueWatching.isNotEmpty)
          _buildRow(
            title: 'Continue Watching',
            items: feed.continueWatching,
            showProgress: true,
          ),
        if (feed.newEpisodes.isNotEmpty)
          _buildRow(title: 'New Episodes', items: feed.newEpisodes),
        if (feed.recentlyAdded.isNotEmpty)
          _buildRow(title: 'Recently Added', items: feed.recentlyAdded),
        if (allEmpty) const _EmptyHomeState(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRow({
    required String title,
    required List<FeedItem> items,
    bool showProgress = false,
  }) {
    return ContentRow(
      title: title,
      children: items
          .map(
            (item) => VideoCard(
              video: item.video,
              channel: item.channel,
              showProgress: showProgress,
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize WebSocket connection
    ref.watch(webSocketConnectionProvider);

    // The whole feed now arrives in a single request; rows are derived from it
    // and the WebSocket service invalidates this provider for live updates.
    final homeFeed = ref.watch(homeFeedProvider);

    Future<void> refresh() async {
      // Fire-and-forget: kick a server-side poll of all channels so new
      // uploads start flowing in; results land via WS events / next refresh.
      unawaited(
        ref.read(apiServiceProvider).pollAllChannels().catchError((_) {}),
      );
      // Reload the unified feed and keep the spinner up until it resolves.
      // refresh() resolves its own errors into state (cache fallback on a
      // connection error), so it never throws.
      await ref.read(homeFeedProvider.notifier).refresh();
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
              child: homeFeed.when(
                data: _buildFeed,
                loading: () => const _HomeFeedSkeleton(),
                error: (error, _) => _HomeFeedError(
                  message: '$error',
                  onRetry: () => ref.invalidate(homeFeedProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer placeholders for the three rows while the feed loads.
class _HomeFeedSkeleton extends StatelessWidget {
  const _HomeFeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 8),
        ContentRow(title: 'Continue Watching', isLoading: true, children: []),
        ContentRow(title: 'New Episodes', isLoading: true, children: []),
        ContentRow(title: 'Recently Added', isLoading: true, children: []),
        SizedBox(height: 24),
      ],
    );
  }
}

class _HomeFeedError extends StatelessWidget {
  const _HomeFeedError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: NullFeedTheme.errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load your feed',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
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
