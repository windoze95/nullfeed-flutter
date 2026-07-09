import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/feed.dart';
import '../models/recommendation.dart';
import '../models/video.dart';
import '../providers/auth_provider.dart';
import '../providers/channel_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_ui.dart';
import '../widgets/content_row.dart';
import '../widgets/progress_bar.dart';
import '../widgets/video_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _openVideo(
    BuildContext context,
    WidgetRef ref,
    FeedItem item,
  ) async {
    await context.push('/player/${item.video.id}');
    if (!context.mounted) return;
    invalidateFeedProviders(ref);
  }

  Widget _buildFeed(BuildContext context, WidgetRef ref, HomeFeed feed) {
    final spotlight =
        feed.continueWatching.firstOrNull ??
        feed.newEpisodes.firstOrNull ??
        feed.recentlyAdded.firstOrNull;
    final spotlightIsContinue =
        spotlight != null && feed.continueWatching.firstOrNull == spotlight;
    final continueWatching = spotlightIsContinue
        ? feed.continueWatching.skip(1).toList()
        : feed.continueWatching;
    final allEmpty = spotlight == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (spotlight != null)
          _SpotlightCard(
            item: spotlight,
            onPlay: () => _openVideo(context, ref, spotlight),
            onOpenChannel: () =>
                context.push('/channel/${spotlight.channel.id}'),
          ),
        if (continueWatching.isNotEmpty)
          _buildRow(
            title: 'Continue watching',
            subtitle: 'Pick up exactly where you left off.',
            items: continueWatching,
            showProgress: true,
          ),
        if (feed.newEpisodes.isNotEmpty)
          _buildRow(
            title: 'New from your channels',
            subtitle: 'Fresh episodes from the people you follow.',
            items: feed.newEpisodes,
          ),
        if (feed.recentlyAdded.isNotEmpty)
          _buildRow(
            title: 'Recently ready',
            subtitle: 'The latest videos prepared by your server.',
            items: feed.recentlyAdded,
          ),
        if (allEmpty)
          EmptyStatePanel(
            icon: Icons.add_to_queue_rounded,
            eyebrow: 'Start here',
            title: 'Build a feed that belongs to you',
            description:
                'Follow a channel once and NullFeed keeps new episodes ready. '
                'No algorithmic firehose and no ads.',
            steps: const [
              'Add a YouTube channel by pasting its link or channel ID.',
              'NullFeed finds its videos and prepares them on your server.',
              'Press play here whenever you are ready.',
            ],
            primaryLabel: 'Add your first channel',
            primaryAction: () => context.go('/library?add=1'),
            secondaryLabel: 'Explore suggestions',
            secondaryAction: () => context.go('/discover'),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRow({
    required String title,
    required String subtitle,
    required List<FeedItem> items,
    bool showProgress = false,
  }) {
    return ContentRow(
      title: title,
      subtitle: subtitle,
      children: [
        for (final item in items)
          VideoCard(
            video: item.video,
            channel: item.channel,
            showProgress: showProgress,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(webSocketConnectionProvider);
    final homeFeed = ref.watch(homeFeedProvider);
    final currentUser = ref.watch(authStateProvider).currentUser;

    Future<void> refresh() async {
      unawaited(
        ref.read(apiServiceProvider).pollAllChannels().catchError((_) {}),
      );
      await ref.read(homeFeedProvider.notifier).refresh();
    }

    final firstName = currentUser?.displayName.trim().split(' ').first;
    final title = firstName == null || firstName.isEmpty
        ? 'Ready when you are.'
        : 'Ready when you are, $firstName.';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: NullFeedTheme.primaryColor,
        onRefresh: refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: PageIntro(
                  eyebrow: 'Your home feed',
                  title: title,
                  description:
                      'Continue something familiar or choose what comes next. '
                      'Your server handles the rest.',
                  bottom: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      QuickActionButton(
                        icon: Icons.search_rounded,
                        label: 'Search',
                        onTap: () => context.push('/search'),
                      ),
                      QuickActionButton(
                        icon: Icons.add_rounded,
                        label: 'Add channel',
                        emphasized: true,
                        onTap: () => context.go('/library?add=1'),
                      ),
                      QuickActionButton(
                        icon: Icons.playlist_play_rounded,
                        label: 'Watch later',
                        onTap: () => context.push('/queue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: homeFeed.when(
                data: (feed) => _buildFeed(context, ref, feed),
                loading: () => const _HomeFeedSkeleton(),
                error: (error, _) => _HomeFeedError(
                  message: '$error',
                  onRetry: () => ref.invalidate(homeFeedProvider),
                  onServerSettings: () => context.go('/settings'),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _RecommendedForYouRail()),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({
    required this.item,
    required this.onPlay,
    required this.onOpenChannel,
  });

  final FeedItem item;
  final VoidCallback onPlay;
  final VoidCallback onOpenChannel;

  String get _thumbnailUrl =>
      'https://i.ytimg.com/vi/${item.video.youtubeVideoId}/maxresdefault.jpg';

  String get _fallbackThumbnailUrl =>
      'https://i.ytimg.com/vi/${item.video.youtubeVideoId}/hqdefault.jpg';

  String _positionLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes >= 60) {
      return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
    }
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdaptiveLayout.contentPadding(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final canResume = item.video.canResume;
    return Container(
      height: wide ? 420 : 380,
      margin: EdgeInsets.fromLTRB(padding, 4, padding, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: NullFeedTheme.cardColor,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: NullFeedTheme.borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.video.youtubeVideoId.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _thumbnailUrl,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorWidget: (_, __, ___) => CachedNetworkImage(
                imageUrl: _fallbackThumbnailUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorWidget: (_, __, ___) => const _SpotlightFallback(),
              ),
              placeholder: (_, __) => const _SpotlightFallback(),
            )
          else
            const _SpotlightFallback(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x12000000),
                  Color(0x42000000),
                  Color(0xF207090D),
                ],
                stops: [0, 0.44, 1],
              ),
            ),
          ),
          if (wide)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xDA07090D), Color(0x0007090D)],
                  stops: [0, 0.7],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.all(wide ? 32 : 22),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 640 : 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStatusPill(
                      icon: canResume
                          ? Icons.history_rounded
                          : Icons.auto_awesome_rounded,
                      label: canResume ? 'CONTINUE WATCHING' : 'READY TO WATCH',
                    ),
                    const SizedBox(height: 13),
                    Text(
                      item.video.title,
                      maxLines: wide ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: wide
                          ? Theme.of(context).textTheme.headlineLarge
                          : Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      canResume
                          ? '${item.channel.name} · Resume at ${_positionLabel(item.video.watchPositionSeconds)}'
                          : '${item.channel.name} · ${item.video.formattedDuration}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (canResume) ...[
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: NullFeedProgressBar(
                          progress: item.video.watchProgress,
                          height: 4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: onPlay,
                          icon: Icon(
                            canResume
                                ? Icons.play_arrow_rounded
                                : Icons.play_circle_rounded,
                          ),
                          label: Text(canResume ? 'Resume' : 'Play now'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onOpenChannel,
                          icon: const Icon(
                            Icons.subscriptions_outlined,
                            size: 18,
                          ),
                          label: Text(item.channel.name),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightFallback extends StatelessWidget {
  const _SpotlightFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NullFeedTheme.elevatedSurfaceColor,
            NullFeedTheme.cardColor,
            Color(0xFF19162B),
          ],
        ),
      ),
    );
  }
}

class _HomeFeedSkeleton extends StatelessWidget {
  const _HomeFeedSkeleton();

  @override
  Widget build(BuildContext context) {
    final padding = AdaptiveLayout.contentPadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 380,
          margin: EdgeInsets.symmetric(horizontal: padding),
          decoration: BoxDecoration(
            color: NullFeedTheme.cardColor,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: NullFeedTheme.borderColor),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
        const ContentRow(
          title: 'New from your channels',
          subtitle: 'Looking for new episodes…',
          isLoading: true,
          children: [],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _HomeFeedError extends StatelessWidget {
  const _HomeFeedError({
    required this.message,
    required this.onRetry,
    required this.onServerSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onServerSettings;

  @override
  Widget build(BuildContext context) {
    return EmptyStatePanel(
      icon: Icons.cloud_off_rounded,
      eyebrow: 'Connection interrupted',
      title: 'Your feed could not check in',
      description:
          'Your library is safe. Retry the server, or check its address if it '
          'moved.\n\n$message',
      primaryLabel: 'Try again',
      primaryAction: onRetry,
      secondaryLabel: 'Server settings',
      secondaryAction: onServerSettings,
    );
  }
}

/// A compact mirror of Explore. Loading, empty, and error states stay on the
/// Explore screen so Home remains focused on things the user can act on now.
class _RecommendedForYouRail extends ConsumerWidget {
  const _RecommendedForYouRail();

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
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not subscribe: ${error.message}')),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Subscribed to ${rec.channelName}')),
    );
    try {
      await ref.read(discoverProvider.notifier).dismiss(rec.id);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Subscribed to ${rec.channelName}, but the suggestion could not be cleared.',
          ),
        ),
      );
    }
  }

  Future<void> _dismiss(
    BuildContext context,
    WidgetRef ref,
    Recommendation rec,
  ) async {
    try {
      await ref.read(discoverProvider.notifier).dismiss(rec.id);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dismiss: ${error.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(discoverProvider).value ?? const <Recommendation>[];
    if (recs.isEmpty) return const SizedBox.shrink();

    return ContentRow(
      title: 'Recommended for you',
      subtitle: 'A few thoughtful picks—not an endless feed.',
      actionLabel: 'Explore all',
      onAction: () => context.go('/discover'),
      children: [
        for (final rec in recs)
          _RecommendationRailCard(
            channelName: rec.channelName,
            reasoning: rec.reasoning,
            onSubscribe: rec.youtubeChannelId != null
                ? () => _subscribe(context, ref, rec)
                : null,
            onDismiss: () => _dismiss(context, ref, rec),
          ),
      ],
    );
  }
}

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
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NullFeedTheme.accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: NullFeedTheme.accentColor.withValues(
                          alpha: 0.22,
                        ),
                      ),
                    ),
                    child: Text(
                      channelName.isNotEmpty
                          ? channelName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: NullFeedTheme.accentColor,
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
                    icon: const Icon(Icons.close_rounded, size: 19),
                    color: NullFeedTheme.textMuted,
                    tooltip: 'Dismiss',
                    onPressed: onDismiss,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const AppStatusPill(
                label: 'WHY IT FITS',
                icon: Icons.auto_awesome_rounded,
                color: NullFeedTheme.accentColor,
              ),
              const SizedBox(height: 9),
              Expanded(
                child: Text(
                  reasoning,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onSubscribe,
                  icon: const Icon(Icons.add_rounded, size: 18),
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
