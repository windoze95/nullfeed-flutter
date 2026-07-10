import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video.dart';
import '../providers/channel_provider.dart';
import '../providers/feed_provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../models/channel.dart';
import '../widgets/content_type_badge.dart';
import '../widgets/app_ui.dart';
import '../widgets/cinematic_banner.dart';
import '../widgets/queue_action.dart';
import '../widgets/unplayable_badge.dart';
import '../widgets/video_list_tile.dart';
import '../widgets/adaptive_layout.dart';
import '../config/theme.dart';

class ChannelDetailScreen extends ConsumerStatefulWidget {
  final String channelId;
  const ChannelDetailScreen({super.key, required this.channelId});

  @override
  ConsumerState<ChannelDetailScreen> createState() =>
      _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends ConsumerState<ChannelDetailScreen> {
  bool _membershipBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshChannelImages();
  }

  Future<void> _refreshChannelImages() async {
    try {
      // Snapshot current URLs before refresh
      final oldChannel = ref
          .read(channelDetailProvider(widget.channelId))
          .value;
      final oldBanner = oldChannel?.bannerUrl;
      final oldAvatar = oldChannel?.avatarUrl;

      final api = ref.read(apiServiceProvider);
      final updated = await api.refreshChannelImages(widget.channelId);

      // Evict stale images from cache if URLs changed
      if (oldBanner != null && oldBanner != updated.bannerUrl) {
        await _evictImage(oldBanner);
      }
      if (oldAvatar != null && oldAvatar != updated.avatarUrl) {
        await _evictImage(oldAvatar);
      }

      ref.invalidate(channelDetailProvider(widget.channelId));
      ref.invalidate(channelsProvider);
    } catch (_) {
      // Non-critical — channel still loads with cached images
    }
  }

  Future<void> _evictImage(String url) async {
    await CachedNetworkImage.evictFromCache(url);
    final promotedUrl = CinematicBanner.highResolutionUrl(url);
    if (promotedUrl != null && promotedUrl != url) {
      await CachedNetworkImage.evictFromCache(promotedUrl);
    }
  }

  void _invalidateChannel() {
    ref.invalidate(channelDetailProvider(widget.channelId));
    ref.invalidate(channelVideosProvider(widget.channelId));
  }

  Future<void> _refresh() async {
    // Ask the server to check YouTube for new uploads first, so a pull
    // down genuinely refreshes content rather than re-reading the catalog.
    try {
      await ref.read(apiServiceProvider).pollChannel(widget.channelId);
    } catch (_) {
      // Poll failures (offline server, YouTube hiccup) shouldn't block
      // refreshing what we already have.
    }
    // Each refresh() resolves its own errors into state (cache fallback on a
    // connection error), so neither throws.
    await Future.wait([
      ref.read(channelDetailProvider(widget.channelId).notifier).refresh(),
      ref.read(channelVideosProvider(widget.channelId).notifier).refresh(),
    ]);
  }

  Future<void> _changeMembership(Channel channel) async {
    if (_membershipBusy) return;

    if (channel.isSubscribed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Unsubscribe from ${channel.name}?'),
          content: const Text(
            'This removes the channel from this profile\'s Library. New '
            'uploads will no longer appear in Home.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep subscribed'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(
                foregroundColor: NullFeedTheme.errorColor,
              ),
              child: const Text('Unsubscribe'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _membershipBusy = true);
    final wasSubscribed = channel.isSubscribed;
    try {
      final notifier = ref.read(channelsProvider.notifier);
      if (wasSubscribed) {
        await notifier.unsubscribe(channel.id);
      } else {
        await notifier.subscribe(channel.youtubeChannelId);
      }
      if (!mounted) return;

      await Future.wait([
        ref.read(channelDetailProvider(widget.channelId).notifier).refresh(),
        ref.read(channelVideosProvider(widget.channelId).notifier).refresh(),
      ]);
      if (!mounted) return;
      invalidateFeedProviders(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasSubscribed
                ? 'Removed ${channel.name} from your Library'
                : 'Added ${channel.name} to your Library',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasSubscribed
                ? 'Couldn\'t unsubscribe from ${channel.name}'
                : 'Couldn\'t subscribe to ${channel.name}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _membershipBusy = false);
    }
  }

  Widget _membershipButton(Channel channel) {
    final isSubscribed = channel.isSubscribed;
    final label = isSubscribed ? 'Unsubscribe' : 'Subscribe';
    final icon = isSubscribed
        ? Icons.notifications_off_outlined
        : Icons.add_circle_rounded;
    final content = _membershipBusy
        ? const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: NullFeedTheme.textSecondary,
                ),
              ),
              SizedBox(width: 10),
              Text('Updating…'),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19),
              const SizedBox(width: 9),
              Text(label),
            ],
          );

    final button = isSubscribed
        ? OutlinedButton(
            onPressed: _membershipBusy
                ? null
                : () => _changeMembership(channel),
            style: OutlinedButton.styleFrom(
              foregroundColor: NullFeedTheme.errorColor,
              side: BorderSide(
                color: NullFeedTheme.errorColor.withValues(alpha: 0.7),
              ),
            ),
            child: content,
          )
        : ElevatedButton(
            onPressed: _membershipBusy
                ? null
                : () => _changeMembership(channel),
            child: content,
          );

    return Semantics(
      button: true,
      label: _membershipBusy
          ? 'Updating subscription for ${channel.name}'
          : isSubscribed
          ? 'Unsubscribe from ${channel.name}'
          : 'Subscribe to ${channel.name}',
      excludeSemantics: true,
      child: SizedBox(width: double.infinity, child: button),
    );
  }

  /// Picks the video for the Resume/Play button:
  /// 1. an in-progress video (position > 0 and not watched) — "Resume";
  /// 2. else the newest unwatched video — "Play";
  /// 3. else the newest complete video — "Play".
  ({Video video, String label})? _resumeTarget(List<Video> videos) {
    final complete = videos
        .where((v) => v.status == VideoStatus.complete)
        .toList();
    if (complete.isEmpty) return null;

    final inProgress = complete
        .where((v) => v.watchPositionSeconds > 0 && !v.isWatched)
        .toList();
    if (inProgress.isNotEmpty) {
      // Most-recently-watched first; entries without a timestamp sort last.
      inProgress.sort((a, b) {
        final aTime = a.lastWatchedAt;
        final bTime = b.lastWatchedAt;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      return (video: inProgress.first, label: 'Resume');
    }

    int newestFirst(Video a, Video b) {
      final aTime = a.uploadedAt;
      final bTime = b.uploadedAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    }

    final unwatched = complete.where((v) => !v.isWatched).toList()
      ..sort(newestFirst);
    if (unwatched.isNotEmpty) {
      return (video: unwatched.first, label: 'Play');
    }

    final sorted = [...complete]..sort(newestFirst);
    return (video: sorted.first, label: 'Play');
  }

  @override
  Widget build(BuildContext context) {
    final channelAsync = ref.watch(channelDetailProvider(widget.channelId));
    final videosAsync = ref.watch(channelVideosProvider(widget.channelId));
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      // The loaded state brings its own SliverAppBar; loading/error states
      // still need a back button.
      appBar: channelAsync.hasValue && !channelAsync.hasError
          ? null
          : AppBar(backgroundColor: NullFeedTheme.backgroundColor),
      body: AppBackdrop(
        child: channelAsync.when(
          data: (channel) => RefreshIndicator(
            color: NullFeedTheme.primaryColor,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: AdaptiveLayout.value(
                    context,
                    phone: 230.0,
                    tablet: 310.0,
                  ),
                  pinned: true,
                  backgroundColor: NullFeedTheme.surfaceColor,
                  actions: [
                    // Per-channel content-type filter — only when subscribed and
                    // the channel has more than one kind of media to sift.
                    if (channel.isSubscribed &&
                        channel.availableContentTypes.length > 1)
                      IconButton(
                        icon: Icon(
                          channel.hiddenContentTypes.isEmpty
                              ? Icons.filter_alt_outlined
                              : Icons.filter_alt,
                        ),
                        tooltip: 'Filter content types',
                        onPressed: () => _showContentFilter(channel),
                      ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: CinematicBanner(
                      imageUrl: channel.bannerUrl,
                      showSharpArtwork: true,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (channel.avatarUrl != null)
                              CircleAvatar(
                                radius: 32,
                                backgroundImage: CachedNetworkImageProvider(
                                  CinematicBanner.highResolutionUrl(
                                    channel.avatarUrl!,
                                  )!,
                                ),
                              )
                            else
                              CircleAvatar(
                                radius: 32,
                                backgroundColor: NullFeedTheme.primaryColor
                                    .withValues(alpha: 0.2),
                                child: Text(
                                  channel.name.isNotEmpty
                                      ? channel.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: NullFeedTheme.accentColor,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    channel.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  if (channel.description != null &&
                                      channel.description!.isNotEmpty)
                                    Text(
                                      channel.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  const SizedBox(height: 8),
                                  // Membership is persistent state, not a
                                  // signal moment — no lime, and "not in
                                  // library" is neutral, not a warning.
                                  AppStatusPill(
                                    label: channel.isSubscribed
                                        ? 'IN YOUR LIBRARY'
                                        : 'NOT IN YOUR LIBRARY',
                                    icon: channel.isSubscribed
                                        ? Icons.check_circle_rounded
                                        : Icons.add_circle_outline_rounded,
                                    color: channel.isSubscribed
                                        ? NullFeedTheme.textSecondary
                                        : NullFeedTheme.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _membershipButton(channel),
                        const SizedBox(height: 10),
                        videosAsync.when(
                          data: (videos) {
                            final target = _resumeTarget(videos);
                            if (target == null) return const SizedBox.shrink();
                            return SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  await context.push(
                                    '/player/${target.video.id}',
                                  );
                                  if (!mounted) return;
                                  ref.invalidate(
                                    channelVideosProvider(widget.channelId),
                                  );
                                  invalidateFeedProviders(ref);
                                },
                                // A lime icon marks the resume signal; "Play
                                // latest" stays plain violet.
                                icon: Icon(
                                  Icons.play_arrow,
                                  size: 24,
                                  color: target.label == 'Resume'
                                      ? NullFeedTheme.successColor
                                      : null,
                                ),
                                label: Text(target.label),
                              ),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        if (!kIsWeb &&
                            channel.isSubscribed &&
                            channel.trackingMode == 'FUTURE_ONLY')
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Auto-offline new episodes',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                Switch(
                                  value: ref
                                      .read(storageServiceProvider)
                                      .isAutoOfflineEnabled(widget.channelId),
                                  onChanged: (value) async {
                                    await ref
                                        .read(storageServiceProvider)
                                        .setAutoOffline(
                                          widget.channelId,
                                          value,
                                        );
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                        Text(
                          'Videos',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                videosAsync.when(
                  data: (videos) {
                    final displayVideos = videos;
                    if (displayVideos.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(padding),
                          child: Center(
                            child: Text(
                              'No videos found',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final video = displayVideos[index];
                        return VideoListTile(
                          video: video,
                          // Every episode plays on tap — cached or not (an
                          // un-cached one starts via instant-stream).
                          onTap: () async {
                            await context.push('/player/${video.id}');
                            if (!mounted) return;
                            ref.invalidate(
                              channelVideosProvider(widget.channelId),
                            );
                            invalidateFeedProviders(ref);
                          },
                          onMenu: () => _showVideoMenu(video),
                        );
                      }, childCount: displayVideos.length),
                    );
                  },
                  loading: () => const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
                  error: (error, _) => SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Text(
                              'Failed to load videos',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () => ref.invalidate(
                                channelVideosProvider(widget.channelId),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: NullFeedTheme.errorColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load channel',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _invalidateChannel,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The per-channel content-type filter menu: a checklist of the types this
  /// channel has. Unchecking a type hides it from this channel's list and feeds
  /// (persisted server-side); checking it brings it back. Toggles apply live.
  void _showContentFilter(Channel channel) {
    final available = channel.availableContentTypes
        .map(contentTypeFromWire)
        .whereType<ContentType>()
        .where((t) => t != ContentType.unknown)
        .toList();
    if (available.isEmpty) return;

    // Local source of truth for the sheet, seeded from the current filter and
    // updated optimistically so toggles feel instant; each change is persisted.
    final hidden = {...channel.hiddenContentTypes};

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Show content types',
                    style: TextStyle(
                      color: NullFeedTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              for (final type in available)
                CheckboxListTile(
                  value: !hidden.contains(type.wire),
                  secondary: Icon(
                    contentTypeIcon(type),
                    color: contentTypeColor(type),
                  ),
                  title: Text(type.menuLabel),
                  activeColor: NullFeedTheme.primaryColor,
                  onChanged: (show) {
                    setSheetState(() {
                      if (show == false) {
                        hidden.add(type.wire);
                      } else {
                        hidden.remove(type.wire);
                      }
                    });
                    _applyContentFilter(hidden.toList());
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyContentFilter(List<String> hidden) async {
    try {
      await ref
          .read(apiServiceProvider)
          .setContentFilter(widget.channelId, hidden);
      if (!mounted) return;
      // Re-fetch the channel (updated filter + icon state) and the now-gated
      // video list.
      ref.invalidate(channelDetailProvider(widget.channelId));
      ref.invalidate(channelVideosProvider(widget.channelId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t update the filter')),
        );
      }
    }
  }

  void _showVideoMenu(Video video) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NullFeedTheme.textMuted),
              ),
            ),
            if (video.activeUnplayableReason != null)
              UnplayableReasonTile(reason: video.activeUnplayableReason!),
            QueueActionTile(
              video: video,
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }
}
