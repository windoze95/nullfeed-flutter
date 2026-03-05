import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video.dart';
import '../providers/channel_provider.dart';
import '../providers/download_progress_provider.dart';
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
      final api = ref.read(apiServiceProvider);
      await api.refreshChannelImages(widget.channelId);
      ref.invalidate(channelDetailProvider(widget.channelId));
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

  @override
  Widget build(BuildContext context) {
    final channelAsync = ref.watch(channelDetailProvider(widget.channelId));
    final videosAsync = ref.watch(channelVideosProvider(widget.channelId));
    final progressMap = ref.watch(downloadProgressProvider);
    final isTv = AdaptiveLayout.isTv(context);
    final padding = AdaptiveLayout.contentPadding(context);

    videosAsync.whenData(_checkPollingNeeded);

    return Scaffold(
      body: channelAsync.when(
        data: (channel) => CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: isTv ? 280 : 220,
              pinned: true,
              backgroundColor: NullFeedTheme.surfaceColor,
              leading: isTv ? const SizedBox.shrink() : null,
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
                            radius: isTv ? 40 : 32,
                            backgroundImage: CachedNetworkImageProvider(
                              channel.avatarUrl!,
                            ),
                          )
                        else
                          CircleAvatar(
                            radius: isTv ? 40 : 32,
                            backgroundColor: NullFeedTheme.primaryColor
                                .withValues(alpha: 0.2),
                            child: Text(
                              channel.name.isNotEmpty
                                  ? channel.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: isTv ? 34 : 28,
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
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    videosAsync.when(
                      data: (videos) {
                        final completeVideos = videos
                            .where((v) => v.status == VideoStatus.complete)
                            .toList();
                        if (completeVideos.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final firstUnwatched = completeVideos.where(
                          (v) => !v.isWatched,
                        );
                        final resumeVideo = firstUnwatched.isNotEmpty
                            ? firstUnwatched.first
                            : completeVideos.first;
                        final hasProgress =
                            resumeVideo.watchPositionSeconds > 0;
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await context.push('/player/${resumeVideo.id}');
                              ref.invalidate(
                                channelVideosProvider(widget.channelId),
                              );
                            },
                            icon: const Icon(Icons.play_arrow, size: 24),
                            label: Text(hasProgress ? 'Resume' : 'Play Next'),
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
                              onChanged: (value) {
                                ref
                                    .read(storageServiceProvider)
                                    .setAutoOffline(widget.channelId, value);
                                setState(() {});
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
                              ref.invalidate(
                                channelVideosProvider(widget.channelId),
                              );
                            }
                          : null,
                      onDownload: video.isDownloadable
                          ? () => _onDownload(video)
                          : null,
                      onCancel: video.isInProgress
                          ? () => _onCancelDownload(video)
                          : null,
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
                    child: Text(
                      'Failed to load videos',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onCancelDownload(Video video) async {
    final api = ref.read(apiServiceProvider);
    try {
      await api.cancelDownload(video.id);
      ref.invalidate(channelVideosProvider(widget.channelId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel download: $e')),
        );
      }
    }
  }

  Future<void> _onDownload(Video video) async {
    final api = ref.read(apiServiceProvider);

    setState(() {
      _pendingVideoIds.add(video.id);
    });

    try {
      await api.downloadVideo(video.id);
      _startPolling();
    } catch (e) {
      setState(() {
        _pendingVideoIds.remove(video.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start download: $e')));
      }
    }
  }
}
