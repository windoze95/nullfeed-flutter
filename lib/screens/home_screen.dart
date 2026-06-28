import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed.dart';
import '../models/recommendation.dart';
import '../providers/feed_provider.dart';
import '../providers/websocket_provider.dart';
import '../providers/channel_provider.dart';
import '../providers/discover_provider.dart';
import '../services/api_service.dart';
import '../widgets/content_row.dart';
import '../widgets/video_card.dart';
import '../config/constants.dart';
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
            // Surfaces the same AI recommendations as the Discover tab; renders
            // nothing until there are any, so Home never shows an empty section.
            const SliverToBoxAdapter(child: _RecommendedForYouRail()),
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

/// "Recommended for you" rail — surfaces the same AI recommendations as the
/// Discover tab ([discoverProvider]) on Home. The WebSocket `recommendation_ready`
/// event reloads that provider, so this rail refreshes live alongside Discover.
///
/// The rail is omitted entirely until there are recommendations to show: pure
/// loading and error states render nothing here (Home should not carry an empty
/// or broken suggestion section — the Discover tab owns those states), and a
/// stale value is kept on screen during a background reload.
class _RecommendedForYouRail extends ConsumerWidget {
  const _RecommendedForYouRail();

  /// Subscribes to a recommended channel, mirroring the Discover tab: the
  /// recommendation is dismissed only after the subscribe succeeds, and
  /// failures surface via SnackBar.
  Future<void> _subscribe(
    BuildContext context,
    WidgetRef ref,
    Recommendation rec,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(channelsProvider.notifier)
          .subscribe(rec.youtubeChannelId!);
      await ref.read(discoverProvider.notifier).dismiss(rec.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Subscribed to ${rec.channelName}')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not subscribe: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(discoverProvider).value ?? const <Recommendation>[];
    if (recs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentRow(
          title: 'Recommended for you',
          children: [
            for (final rec in recs)
              _RecommendationRailCard(
                channelName: rec.channelName,
                reasoning: rec.reasoning,
                onSubscribe: rec.youtubeChannelId != null
                    ? () => _subscribe(context, ref, rec)
                    : null,
                onDismiss: () =>
                    ref.read(discoverProvider.notifier).dismiss(rec.id),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// A compact recommendation card for the Home rail: channel name, the model's
/// reasoning, and the Discover actions (Subscribe / dismiss). Sized to fit the
/// fixed [ContentRow] height, so the reasoning is clamped and the Subscribe
/// button stays pinned to the bottom.
class _RecommendationRailCard extends StatelessWidget {
  const _RecommendationRailCard({
    required this.channelName,
    required this.reasoning,
    required this.onDismiss,
    this.onSubscribe,
  });

  final String channelName;
  final String reasoning;
  final VoidCallback onDismiss;
  final VoidCallback? onSubscribe;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppConstants.channelCardWidth,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: NullFeedTheme.primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        channelName.isNotEmpty
                            ? channelName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: NullFeedTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      channelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: NullFeedTheme.textMuted,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    tooltip: 'Dismiss',
                    onPressed: onDismiss,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  reasoning,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onSubscribe,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Subscribe'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
