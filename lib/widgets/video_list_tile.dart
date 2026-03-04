import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/video.dart';
import '../config/theme.dart';
import 'progress_bar.dart';

class VideoListTile extends StatefulWidget {
  final Video video;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onCancel;
  final double? downloadProgress;

  const VideoListTile({
    super.key,
    required this.video,
    this.onTap,
    this.onDownload,
    this.onCancel,
    this.downloadProgress,
  });

  @override
  State<VideoListTile> createState() => _VideoListTileState();
}

class _VideoListTileState extends State<VideoListTile> {
  bool _isFocused = false;

  String? get _thumbnailUrl {
    if (widget.video.youtubeVideoId.isNotEmpty) {
      return 'https://img.youtube.com/vi/${widget.video.youtubeVideoId}/mqdefault.jpg';
    }
    return null;
  }

  Widget _buildTrailingWidget() {
    switch (widget.video.status) {
      case VideoStatus.complete:
        return const Icon(
          Icons.play_circle_outline,
          color: NullFeedTheme.textMuted,
        );
      case VideoStatus.downloading:
      case VideoStatus.pending:
        return SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: widget.downloadProgress != null
                      ? widget.downloadProgress! / 100.0
                      : null,
                ),
              ),
              if (widget.onCancel != null)
                InkWell(
                  onTap: widget.onCancel,
                  borderRadius: BorderRadius.circular(18),
                  child: const Icon(
                    Icons.stop_rounded,
                    size: 14,
                    color: NullFeedTheme.textMuted,
                  ),
                ),
            ],
          ),
        );
      case VideoStatus.cataloged:
        return IconButton(
          icon: const Icon(
            Icons.download_rounded,
            color: NullFeedTheme.primaryColor,
          ),
          onPressed: widget.onDownload,
          tooltip: 'Download',
        );
      case VideoStatus.failed:
        return IconButton(
          icon: const Icon(
            Icons.refresh,
            color: NullFeedTheme.errorColor,
          ),
          onPressed: widget.onDownload,
          tooltip: 'Retry download',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDownloaded = widget.video.isPlayable;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          if (isDownloaded) {
            widget.onTap?.call();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Opacity(
        opacity: isDownloaded ? 1.0 : 0.7,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _isFocused
                ? NullFeedTheme.primaryColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _isFocused
                ? Border.all(color: NullFeedTheme.primaryColor, width: 2)
                : null,
          ),
          child: InkWell(
            onTap: isDownloaded ? widget.onTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                  color: Colors.black.withValues(alpha: 0.8),
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
                                DateFormat.yMMMd()
                                    .format(widget.video.uploadedAt!),
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
                  // Status-aware trailing widget
                  _buildTrailingWidget(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
