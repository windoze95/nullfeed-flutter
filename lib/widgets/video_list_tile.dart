import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/video.dart';
import '../config/theme.dart';
import 'progress_bar.dart';

class VideoListTile extends StatelessWidget {
  final Video video;
  final VoidCallback? onTap;

  const VideoListTile({
    super.key,
    required this.video,
    this.onTap,
  });

  String? get _thumbnailUrl {
    if (video.youtubeVideoId.isNotEmpty) {
      return 'https://img.youtube.com/vi/${video.youtubeVideoId}/mqdefault.jpg';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    if (video.durationSeconds > 0)
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
                            video.formattedDuration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    // Progress bar at bottom
                    if (video.watchProgress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: NullFeedProgressBar(
                          progress: video.watchProgress,
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
                    video.title,
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
                      if (video.uploadedAt != null)
                        Text(
                          DateFormat.yMMMd().format(video.uploadedAt!),
                          style: const TextStyle(
                            color: NullFeedTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      if (video.isWatched) ...[
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
            // Status indicator
            if (video.status == VideoStatus.downloading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.chevron_right,
                color: NullFeedTheme.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
