import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/video.dart';
import '../config/theme.dart';
import '../providers/offline_provider.dart';
import '../services/offline_service.dart';
import 'progress_bar.dart';

class VideoListTile extends ConsumerStatefulWidget {
  final Video video;
  final VoidCallback? onTap;

  /// Opens the per-video actions menu (long-press or the ⋯ button).
  final VoidCallback? onMenu;

  const VideoListTile({
    super.key,
    required this.video,
    this.onTap,
    this.onMenu,
  });

  @override
  ConsumerState<VideoListTile> createState() => _VideoListTileState();
}

class _VideoListTileState extends ConsumerState<VideoListTile> {
  bool _isPressed = false;

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  String? get _thumbnailUrl {
    if (widget.video.youtubeVideoId.isNotEmpty) {
      return 'https://img.youtube.com/vi/${widget.video.youtubeVideoId}/mqdefault.jpg';
    }
    return null;
  }

  /// One merged, human-readable label — title, date, watched and download
  /// state — instead of a pile of separate text/icon nodes.
  String _semanticLabel(String? offlineStatus) {
    final v = widget.video;
    final parts = <String>[v.title];
    if (v.uploadedAt != null) {
      parts.add(DateFormat.yMMMd().format(v.uploadedAt!));
    }
    if (v.isWatched) parts.add('watched');
    final state = _downloadStateLabel(offlineStatus);
    if (state != null) parts.add(state);
    return parts.join(', ');
  }

  String? _downloadStateLabel(String? offlineStatus) {
    // Server-side caching is invisible; only the explicit on-device "save
    // offline" state is surfaced (and only for cached/complete videos).
    if (widget.video.status != VideoStatus.complete) return null;
    if (offlineStatus == 'complete') return 'saved offline';
    if (offlineStatus == 'downloading') return 'saving offline';
    return null;
  }

  Widget _buildTrailingWidget() {
    // The only per-video action is "save offline", available once a video is
    // cached (COMPLETE). Un-cached episodes show nothing — caching happens
    // quietly in the background.
    if (widget.video.status != VideoStatus.complete) {
      return const SizedBox.shrink();
    }

    final offlineStatus = ref.watch(offlineStatusProvider(widget.video.id));
    final offlineProgress = ref.watch(offlineProgressProvider);

    if (offlineStatus == 'complete') {
      return const Icon(Icons.offline_pin, color: NullFeedTheme.successColor);
    }
    if (offlineStatus == 'downloading') {
      final progress = offlineProgress[widget.video.id];
      return SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, value: progress),
            ),
            IconButton(
              icon: const Icon(
                Icons.stop_rounded,
                size: 14,
                color: NullFeedTheme.textMuted,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Cancel offline save',
              onPressed: () {
                ref
                    .read(offlineServiceProvider)
                    .cancelDownload(widget.video.id);
                ref.read(offlineVideosProvider.notifier).refresh();
              },
            ),
          ],
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.cloud_download, color: NullFeedTheme.textMuted),
      onPressed: () async {
        final offlineService = ref.read(offlineServiceProvider);
        await offlineService.downloadToDevice(
          widget.video.id,
          channelId: widget.video.channelId,
          title: widget.video.title,
          youtubeVideoId: widget.video.youtubeVideoId,
        );
        ref.read(offlineVideosProvider.notifier).refresh();
      },
      tooltip: 'Save for offline',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTappable = widget.onTap != null;
    final offlineStatus = ref.watch(offlineStatusProvider(widget.video.id));

    return Opacity(
      opacity: isTappable || widget.video.isPlayable ? 1.0 : 0.7,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Play target: thumbnail + info as one labelled node. The
              // trailing controls keep their own nodes so they stay operable.
              Expanded(
                child: Semantics(
                  button: isTappable,
                  label: _semanticLabel(offlineStatus),
                  excludeSemantics: true,
                  onTap: isTappable ? _handleTap : null,
                  child: InkWell(
                    onTap: isTappable ? _handleTap : null,
                    onLongPress: widget.onMenu,
                    onTapDown: isTappable
                        ? (_) => setState(() => _isPressed = true)
                        : null,
                    onTapUp: isTappable
                        ? (_) => setState(() => _isPressed = false)
                        : null,
                    onTapCancel: isTappable
                        ? () => setState(() => _isPressed = false)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        // Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 160,
                            height: 90,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_thumbnailUrl != null)
                                  CachedNetworkImage(
                                    imageUrl: _thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: NullFeedTheme.cardColor,
                                      child: const Icon(
                                        Icons.play_circle_outline,
                                        color: NullFeedTheme.textMuted,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    color: NullFeedTheme.cardColor,
                                    child: const Icon(
                                      Icons.play_circle_outline,
                                      color: NullFeedTheme.textMuted,
                                    ),
                                  ),
                                // Duration
                                if (widget.video.durationSeconds > 0)
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.8,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        widget.video.formattedDuration,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Watch progress bar
                                if (widget.video.watchProgress > 0)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: NullFeedProgressBar(
                                      progress: widget.video.watchProgress,
                                      height: 3,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Video info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.video.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: NullFeedTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (widget.video.uploadedAt != null)
                                    Text(
                                      DateFormat.yMMMd().format(
                                        widget.video.uploadedAt!,
                                      ),
                                      style: const TextStyle(
                                        color: NullFeedTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (widget.video.isWatched) ...[
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: NullFeedTheme.successColor,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Status-aware trailing widget
              _buildTrailingWidget(),
              if (widget.onMenu != null)
                IconButton(
                  icon: const Icon(
                    Icons.more_vert,
                    color: NullFeedTheme.textMuted,
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: widget.onMenu,
                  tooltip: 'More actions',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
