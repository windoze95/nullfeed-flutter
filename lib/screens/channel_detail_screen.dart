import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video.dart';
import '../providers/channel_provider.dart';
import '../providers/download_progress_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
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
  Timer? _pollTimer;
  final Set<String> _pendingVideoIds = {};

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
        CachedNetworkImage.evictFromCache(oldBanner);
      }
      if (oldAvatar != null && oldAvatar != updated.avatarUrl) {
        CachedNetworkImage.evictFromCache(oldAvatar);
      }

      ref.invalidate(channelDetailProvider(widget.channelId));
      ref.invalidate(channelsProvider);
    } catch (_) {
      // Non-critical — channel still loads with cached images
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    if (_pollTimer?.isActive ?? false) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(channelVideosProvider(widget.channelId));
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _checkPollingNeeded(List<Video> videos) {
    for (final id in _pendingVideoIds.toList()) {
      final video = videos.where((v) => v.id == id).firstOrNull;
      if (video != null && video.status != VideoStatus.cataloged) {
        _pendingVideoIds.remove(id);
      }
    }

    final hasInProgress =
        videos.any((v) => v.isInProgress) || _pendingVideoIds.isNotEmpty;
    if (hasInProgress) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  List<Video> _applyOptimisticUpdates(List<Video> videos) {
    if (_pendingVideoIds.isEmpty) return videos;
    return videos.map((v) {
      if (_pendingVideoIds.contains(v.id) &&
          v.status == VideoStatus.cataloged) {
        return v.copyWith(status: VideoStatus.pending);
      }
      return v;
    }).toList();
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
    try {
      await Future.wait([
        ref.refresh(channelDetailProvider(widget.channelId).future),
        ref.refresh(channelVideosProvider(widget.channelId).future),
      ]);
    } catch (_) {
      // Errors surface through the providers' error states.
    }
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
    final progressMap = ref.watch(downloadProgressProvider);
    final padding = AdaptiveLayout.contentPadding(context);

    videosAsync.whenData(_checkPollingNeeded);

    return Scaffold(
      // The loaded state brings its own SliverAppBar; loading/error states
      // still need a back button.
      appBar: channelAsync.hasValue && !channelAsync.hasError
          ? null
          : AppBar(backgroundColor: NullFeedTheme.backgroundColor),
      body: channelAsync.when(
        data: (channel) => RefreshIndicator(
          color: NullFeedTheme.primaryColor,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: NullFeedTheme.surfaceColor,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (channel.bannerUrl != null)
                        CachedNetworkImage(
                          imageUrl: channel.bannerUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: NullFeedTheme.cardColor),
                        )
                      else
                        Container(color: NullFeedTheme.cardColor),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              NullFeedTheme.backgroundColor.withValues(
                                alpha: 0.9,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                                channel.avatarUrl!,
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
                                  color: NullFeedTheme.primaryColor,
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
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                              icon: const Icon(Icons.play_arrow, size: 24),
                              label: Text(target.label),
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      if (channel.trackingMode == 'FUTURE_ONLY')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Auto-offline new episodes',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Switch(
                                value: ref
                                    .read(storageServiceProvider)
                                    .isAutoOfflineEnabled(widget.channelId),
                                onChanged: (value) async {
                                  await ref
                                      .read(storageServiceProvider)
                                      .setAutoOffline(widget.channelId, value);
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
                  final displayVideos = _applyOptimisticUpdates(videos);
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
                        downloadProgress: progressMap[video.id],
                        onTap: (video.isPlayable || video.isInProgress)
                            ? () async {
                                await context.push('/player/${video.id}');
                                if (!mounted) return;
                                ref.invalidate(
                                  channelVideosProvider(widget.channelId),
                                );
                                invalidateFeedProviders(ref);
                              }
                            : null,
                        onDownload: video.isDownloadable
                            ? () => _onDownload(video)
                            : null,
                        onCancel: video.isInProgress
                            ? () => _onCancelDownload(video)
                            : null,
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
    );
  }

  void _showVideoMenu(Video video) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NullFeedTheme.cardColor,
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
            if (video.status == VideoStatus.complete)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Re-download'),
                subtitle: const Text('Fetch the video from YouTube again'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _onDownload(video);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: NullFeedTheme.errorColor,
              ),
              title: const Text('Remove from library'),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmRemove(video);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(Video video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NullFeedTheme.cardColor,
        title: const Text('Remove from library?'),
        content: Text(
          '"${video.title}" will be removed from your library. The downloaded '
          'file is deleted from the server once no other profile has it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: NullFeedTheme.errorColor),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(apiServiceProvider).deleteVideo(video.id);
      if (!mounted) return;
      ref.invalidate(channelVideosProvider(widget.channelId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Removed from library')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _onCancelDownload(Video video) async {
    final api = ref.read(apiServiceProvider);
    try {
      await api.cancelDownload(video.id);
      ref.invalidate(channelVideosProvider(widget.channelId));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel download: ${e.message}')),
        );
      }
    }
  }

  Future<void> _onDownload(Video video) async {
    final api = ref.read(apiServiceProvider);
    final quality = ref.read(settingsProvider).preferredQuality;

    setState(() {
      _pendingVideoIds.add(video.id);
    });

    try {
      await api.downloadVideo(video.id, quality: quality);
      if (!mounted) return;
      _startPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingVideoIds.remove(video.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start download: ${e.message}')),
      );
    }
  }
}
