import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/feed_provider.dart';
import '../providers/offline_provider.dart';
import '../services/offline_service.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_ui.dart';
import '../config/theme.dart';

/// Offline library: videos the user has explicitly saved to this device.
///
/// Server-side caching (followed-channel prefetch, cold-press cache) is
/// invisible background plumbing and never appears here — the only thing shown
/// is what the user deliberately saved for offline playback.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Future<void> _refresh() async {
    ref.read(offlineVideosProvider.notifier).refresh();
  }

  Future<void> _deleteDeviceDownload(Map<String, dynamic> entry) async {
    final videoId = entry['video_id'] as String;
    final title = entry['title'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
    final offlineVideos = ref.watch(offlineVideosProvider);
    final offlineProgress = ref.watch(offlineProgressProvider);
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: RefreshIndicator(
          color: NullFeedTheme.primaryColor,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: PageIntro(
                    eyebrow: 'On this device',
                    title: 'Saved for offline',
                    description: offlineVideos.isEmpty
                        ? 'Keep a video on this device for flights, commutes, '
                              'or whenever your server is out of reach.'
                        : '${offlineVideos.length} ${offlineVideos.length == 1 ? 'video' : 'videos'} available without a connection.',
                  ),
                ),
              ),
              if (offlineVideos.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStatePanel(
                    icon: Icons.download_for_offline_outlined,
                    eyebrow: 'Ready when you need it',
                    title: 'Nothing is saved on this device yet',
                    description:
                        'Open a downloaded video in a channel and choose '
                        '“Save for offline.” Server-prepared videos do not use '
                        'device storage until you ask.',
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final entry = offlineVideos[index];
                      final videoId = entry['video_id'] as String;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: _DeviceDownloadTile(
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
                          ),
                        ),
                      );
                    }, childCount: offlineVideos.length),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
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
                    'https://i.ytimg.com/vi/$youtubeVideoId/hqdefault.jpg',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorWidget: (_, __, ___) => placeholder,
              )
            : placeholder,
      ),
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
