import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/video.dart';
import '../providers/feed_provider.dart';
import '../providers/queue_provider.dart';
import '../widgets/queue_action.dart';
import '../widgets/video_list_tile.dart';
import '../config/theme.dart';

/// The watch-later queue, reached from the Library app bar. Lists queued videos
/// in play order; tapping one plays it, and each row's menu offers a
/// reorder-free remove. Pages load as the list scrolls; pull-to-refresh reloads
/// the queue from the server.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Prefetch the next page a little before hitting the very bottom.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(queueProvider.notifier).loadMore();
    }
  }

  Future<void> _openVideo(String id) async {
    await context.push('/player/$id');
    if (!mounted) return;
    // Watch positions — and the queue itself, via player auto-advance — may
    // have changed while the player was open.
    invalidateFeedProviders(ref);
  }

  void _showMenu(Video video) {
    showVideoActionsSheet(
      context,
      video: video,
      onPlay: () => _openVideo(video.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(queueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        backgroundColor: NullFeedTheme.backgroundColor,
      ),
      body: RefreshIndicator(
        color: NullFeedTheme.primaryColor,
        onRefresh: () => ref.read(queueProvider.notifier).refresh(),
        child: _QueueBody(
          state: state,
          scrollController: _scrollController,
          onRetry: () => ref.read(queueProvider.notifier).refresh(),
          onVideoTap: (video) => _openVideo(video.id),
          onVideoMenu: _showMenu,
        ),
      ),
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({
    required this.state,
    required this.scrollController,
    required this.onRetry,
    required this.onVideoTap,
    required this.onVideoMenu,
  });

  final QueueState state;
  final ScrollController scrollController;
  final VoidCallback onRetry;
  final ValueChanged<Video> onVideoTap;
  final ValueChanged<Video> onVideoMenu;

  @override
  Widget build(BuildContext context) {
    // Always a scrollable so pull-to-refresh works in every state, including
    // empty/error.
    return CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [_buildContent(context)],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (state.isLoading && state.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null && state.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _QueueMessage(
          icon: Icons.error_outline,
          iconColor: NullFeedTheme.errorColor,
          title: 'Could not load your queue',
          message: state.error!,
          onRetry: onRetry,
        ),
      );
    }
    if (state.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _QueueMessage(
          icon: Icons.playlist_play,
          iconColor: NullFeedTheme.textMuted,
          title: 'Your queue is empty',
          message:
              'Add videos to watch later from any video’s menu, the '
              'player, or a channel.',
        ),
      );
    }

    // Items + a footer that spins while the next page loads.
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == state.videos.length) {
          return SizedBox(
            height: 64,
            child: Center(
              child: state.isLoadingMore
                  ? const CircularProgressIndicator()
                  : const SizedBox.shrink(),
            ),
          );
        }
        final video = state.videos[index];
        return VideoListTile(
          video: video,
          // Always tappable: opening a not-yet-downloaded item starts its
          // preview, matching how search results behave.
          onTap: () => onVideoTap(video),
          onMenu: () => onVideoMenu(video),
        );
      }, childCount: state.videos.length + 1),
    );
  }
}

/// Centered full-screen state (empty / error) with an optional Retry button.
class _QueueMessage extends StatelessWidget {
  const _QueueMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
