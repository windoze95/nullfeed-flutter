import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video.dart';
import '../providers/download_progress_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/offline_provider.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../widgets/adaptive_layout.dart';
import '../config/theme.dart';

/// Videos currently downloading on the server (plus just-finished ones).
final activeDownloadsProvider = FutureProvider.autoDispose<List<Video>>((
  ref,
) async {
  final api = ref.watch(apiServiceProvider);
  return api.getActiveDownloads();
});

/// Downloads hub: server-side downloads and on-device offline videos.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // The server list has no push channel for newly queued items, so poll
    // while the screen is visible. Live percentages come over the WebSocket.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(activeDownloadsProvider);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.read(offlineVideosProvider.notifier).refresh();
    try {
      await Future.wait([ref.refresh(activeDownloadsProvider.future)]);
    } catch (_) {
      // The section renders its own inline error state.
    }
  }

  Future<void> _cancelServerDownload(Video video) async {
    try {
      await ref.read(apiServiceProvider).cancelDownload(video.id);
      ref.invalidate(activeDownloadsProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to cancel: ${e.message}')));
    }
  }

  Future<void> _deleteDeviceDownload(Map<String, dynamic> entry) async {
    final videoId = entry['video_id'] as String;
    final title = entry['title'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NullFeedTheme.cardColor,
        title: const Text('Delete from this device?'),
        content: Text(
          title.isEmpty
              ? 'The downloaded file will be removed from this device.'
              : '"$title" will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: NullFeedTheme.errorColor),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(offlineServiceProvider).removeOfflineVideo(videoId);
    ref.read(offlineVideosProvider.notifier).refresh();
  }

  Future<void> _retryDeviceDownload(Map<String, dynamic> entry) async {
    final offlineService = ref.read(offlineServiceProvider);
    final notifier = ref.read(offlineVideosProvider.notifier);
    final future = offlineService.downloadToDevice(
      entry['video_id'] as String,
      channelId: entry['channel_id'] as String?,
      title: entry['title'] as String?,
      youtubeVideoId: entry['youtube_video_id'] as String?,
    );
    notifier.refresh();
    await future;
    notifier.refresh();
  }

  void _cancelDeviceDownload(String videoId) {
    ref.read(offlineServiceProvider).cancelDownload(videoId);
    ref.read(offlineVideosProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final serverDownloads = ref.watch(activeDownloadsProvider);
    final progressMap = ref.watch(downloadProgressProvider);
    final offlineVideos = ref.watch(offlineVideosProvider);
    final offlineProgress = ref.watch(offlineProgressProvider);
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      body: RefreshIndicator(
        color: NullFeedTheme.primaryColor,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverAppBar(
              floating: true,
              title: Text('Downloads'),
              backgroundColor: NullFeedTheme.backgroundColor,
            ),
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Server downloads',
                padding: padding,
              ),
            ),
            serverDownloads.when(
              data: (videos) {
                if (videos.isEmpty) {
                  return SliverToBoxAdapter(
                    child: _EmptyNote(
                      text: 'No active downloads on the server.',
                      padding: padding,
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final video = videos[index];
                    return _ServerDownloadTile(
                      video: video,
                      percentage: progressMap[video.id],
                      onCancel: video.isInProgress
                          ? () => _cancelServerDownload(video)
                          : null,
                    );
                  }, childCount: videos.length),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: padding,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: NullFeedTheme.errorColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$error',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(activeDownloadsProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionHeader(title: 'On this device', padding: padding),
            ),
            if (offlineVideos.isEmpty)
              SliverToBoxAdapter(
                child: _EmptyNote(
                  text:
                      'Nothing saved for offline playback yet. Use the cloud '
                      'icon on a video to save it to this device.',
                  padding: padding,
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final entry = offlineVideos[index];
                  final videoId = entry['video_id'] as String;
                  return _DeviceDownloadTile(
                    entry: entry,
                    liveProgress: offlineProgress[videoId],
                    onPlay: () async {
                      await context.push('/player/$videoId');
                      if (!mounted) return;
                      invalidateFeedProviders(ref);
                    },
                    onDelete: () => _deleteDeviceDownload(entry),
                    onRetry: () => _retryDeviceDownload(entry),
                    onCancel: () => _cancelDeviceDownload(videoId),
                  );
                }, childCount: offlineVideos.length),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final double padding;
  const _SectionHeader({required this.title, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 24, padding, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  final double padding;
  const _EmptyNote({required this.text, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: NullFeedTheme.textMuted),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? youtubeVideoId;
  const _Thumbnail({required this.youtubeVideoId});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: NullFeedTheme.cardColor,
      child: const Icon(
        Icons.play_circle_outline,
        color: NullFeedTheme.textMuted,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 96,
        height: 54,
        child: youtubeVideoId != null && youtubeVideoId!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl:
                    'https://img.youtube.com/vi/$youtubeVideoId/mqdefault.jpg',
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}

class _ServerDownloadTile extends StatelessWidget {
  final Video video;

  /// Live percentage (0–100) from the WebSocket, if any.
  final double? percentage;
  final VoidCallback? onCancel;

  const _ServerDownloadTile({
    required this.video,
    required this.percentage,
    required this.onCancel,
  });

  String get _statusLabel {
    switch (video.status) {
      case VideoStatus.pending:
        return 'Queued';
      case VideoStatus.downloading:
        return percentage != null
            ? 'Downloading ${percentage!.toStringAsFixed(0)}%'
            : 'Downloading…';
      case VideoStatus.complete:
        return 'Completed';
      case VideoStatus.failed:
        return 'Failed';
      case VideoStatus.cataloged:
        return 'Cataloged';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _Thumbnail(youtubeVideoId: video.youtubeVideoId),
      title: Text(
        video.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (video.channelName.isNotEmpty)
            Text(video.channelName, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          if (video.isInProgress)
            LinearProgressIndicator(
              value: percentage != null ? percentage! / 100.0 : null,
              minHeight: 3,
            ),
          const SizedBox(height: 2),
          Text(
            _statusLabel,
            style: const TextStyle(
              fontSize: 12,
              color: NullFeedTheme.textMuted,
            ),
          ),
        ],
      ),
      trailing: onCancel != null
          ? IconButton(
              icon: const Icon(Icons.close, color: NullFeedTheme.textMuted),
              onPressed: onCancel,
              tooltip: 'Cancel download',
            )
          : video.status == VideoStatus.complete
          ? const Icon(Icons.check_circle, color: NullFeedTheme.successColor)
          : null,
    );
  }
}

class _DeviceDownloadTile extends StatelessWidget {
  final Map<String, dynamic> entry;

  /// Live progress (0.0–1.0) while downloading.
  final double? liveProgress;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _DeviceDownloadTile({
    required this.entry,
    required this.liveProgress,
    required this.onPlay,
    required this.onDelete,
    required this.onRetry,
    required this.onCancel,
  });

  String get _status => entry['status'] as String? ?? 'failed';

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final title = entry['title'] as String? ?? '';
    final sizeBytes = (entry['file_size_bytes'] as num?)?.toInt() ?? 0;
    final progress =
        liveProgress ?? (entry['progress'] as num?)?.toDouble() ?? 0.0;

    final String statusLabel;
    switch (_status) {
      case 'downloading':
        statusLabel = 'Downloading ${(progress * 100).toStringAsFixed(0)}%';
      case 'complete':
        final size = _formatBytes(sizeBytes);
        statusLabel = size.isEmpty ? 'Saved on device' : 'Saved · $size';
      default:
        statusLabel = 'Failed';
    }

    return ListTile(
      onTap: _status == 'complete' ? onPlay : null,
      leading: _Thumbnail(youtubeVideoId: entry['youtube_video_id'] as String?),
      title: Text(
        title.isEmpty ? 'Untitled video' : title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_status == 'downloading') ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress, minHeight: 3),
            const SizedBox(height: 2),
          ],
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 12,
              color: _status == 'failed'
                  ? NullFeedTheme.errorColor
                  : NullFeedTheme.textMuted,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_status == 'downloading')
            IconButton(
              icon: const Icon(Icons.close, color: NullFeedTheme.textMuted),
              onPressed: onCancel,
              tooltip: 'Cancel download',
            ),
          if (_status == 'failed')
            IconButton(
              icon: const Icon(Icons.refresh, color: NullFeedTheme.errorColor),
              onPressed: onRetry,
              tooltip: 'Retry download',
            ),
          if (_status == 'complete')
            IconButton(
              icon: const Icon(
                Icons.play_arrow,
                color: NullFeedTheme.primaryColor,
              ),
              onPressed: onPlay,
              tooltip: 'Play',
            ),
          if (_status != 'downloading')
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: NullFeedTheme.textMuted,
              ),
              onPressed: onDelete,
              tooltip: 'Delete from device',
            ),
        ],
      ),
    );
  }
}
