import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel.dart';
import '../models/video.dart';
import '../providers/feed_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/queue_action.dart';
import '../widgets/video_list_tile.dart';
import '../widgets/app_ui.dart';
import '../widgets/cinematic_banner.dart';
import '../config/theme.dart';

/// Full-screen library search reached from the Library app bar. The query is
/// debounced in [SearchNotifier]; video results paginate via `next_cursor` as
/// the user scrolls. Tapping a video opens the player; tapping a channel opens
/// the channel.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Seed the field from any query the (kept-alive) provider already holds so
    // the text and the on-screen results always agree.
    _controller = TextEditingController(text: ref.read(searchProvider).query);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Prefetch the next page a little before hitting the very bottom.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(searchProvider.notifier).loadMore();
    }
  }

  Future<void> _openVideo(String id) async {
    await context.push('/player/$id');
    if (!mounted) return;
    // Watch positions may have changed — keep the home feed fresh.
    invalidateFeedProviders(ref);
  }

  void _showVideoMenu(Video video) {
    showVideoActionsSheet(
      context,
      video: video,
      onPlay: () => _openVideo(video.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);

    return Scaffold(
      backgroundColor: NullFeedTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        toolbarHeight: 76,
        titleSpacing: 4,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: notifier.search,
            style: const TextStyle(
              color: NullFeedTheme.textPrimary,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: 'Search your videos and channels',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _controller.clear();
                      notifier.clear();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
      body: AppBackdrop(
        child: _SearchBody(
          state: state,
          scrollController: _scrollController,
          onRetry: notifier.retry,
          onVideoTap: _openVideo,
          onVideoMenu: _showVideoMenu,
          onChannelTap: (id) => context.push('/channel/$id'),
        ),
      ),
    );
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.state,
    required this.scrollController,
    required this.onRetry,
    required this.onVideoTap,
    required this.onVideoMenu,
    required this.onChannelTap,
  });

  final SearchState state;
  final ScrollController scrollController;
  final VoidCallback onRetry;
  final ValueChanged<String> onVideoTap;
  final ValueChanged<Video> onVideoMenu;
  final ValueChanged<String> onChannelTap;

  @override
  Widget build(BuildContext context) {
    // First load / error / empty all take over the whole screen; once there
    // are results they stay put and loading happens in-place.
    if (state.isLoading && !state.hasResults) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && !state.hasResults) {
      return _SearchMessage(
        icon: Icons.error_outline,
        iconColor: NullFeedTheme.errorColor,
        title: 'Search failed',
        message: state.error!,
        onRetry: onRetry,
      );
    }
    if (!state.hasResults) {
      final isQuery = state.query.isNotEmpty;
      return _SearchMessage(
        icon: isQuery ? Icons.search_off : Icons.video_library_outlined,
        iconColor: NullFeedTheme.textMuted,
        title: isQuery
            ? 'No results for "${state.query}"'
            : 'Search your NullFeed library',
        message: isQuery
            ? 'Try a different title or channel name. Search covers content '
                  'already known to your server.'
            : 'Find a video or a channel already known to your server. Add a '
                  'new YouTube channel from the Channels tab.',
      );
    }

    final slivers = <Widget>[
      if (state.channels.isNotEmpty)
        SliverToBoxAdapter(
          child: _ChannelResults(channels: state.channels, onTap: onChannelTap),
        ),
      if (state.videos.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              state.query.isEmpty ? 'Recent' : 'Videos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final video = state.videos[index];
            return VideoListTile(
              video: video,
              onTap: () => onVideoTap(video.id),
              onMenu: () => onVideoMenu(video),
            );
          }, childCount: state.videos.length),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 64,
            child: Center(
              child: state.isLoadingMore
                  ? const CircularProgressIndicator()
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    ];

    return CustomScrollView(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: slivers,
    );
  }
}

/// Horizontal strip of channel matches shown above the video results.
class _ChannelResults extends StatelessWidget {
  const _ChannelResults({required this.channels, required this.onTap});

  final List<Channel> channels;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Channels',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final channel = channels[index];
              return _ChannelChip(
                channel: channel,
                onTap: () => onTap(channel.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            if (channel.avatarUrl != null)
              CircleAvatar(
                radius: 32,
                backgroundColor: NullFeedTheme.cardColor,
                backgroundImage: CachedNetworkImageProvider(
                  CinematicBanner.highResolutionUrl(channel.avatarUrl!)!,
                ),
              )
            else
              CircleAvatar(
                radius: 32,
                backgroundColor: NullFeedTheme.primaryColor.withValues(
                  alpha: 0.2,
                ),
                child: Text(
                  channel.name.isNotEmpty ? channel.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: NullFeedTheme.primaryColor,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              channel.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered full-screen state (empty / error), with an optional Retry button.
class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
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
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
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
