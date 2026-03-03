import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video.dart';
import '../models/channel.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import 'progress_bar.dart';

class VideoCard extends StatefulWidget {
  final Video video;
  final Channel? channel;
  final bool showProgress;

  const VideoCard({
    super.key,
    required this.video,
    this.channel,
    this.showProgress = false,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _isHovered = false;

  String? get _thumbnailUrl {
    if (widget.video.youtubeVideoId.isNotEmpty) {
      return 'https://img.youtube.com/vi/${widget.video.youtubeVideoId}/mqdefault.jpg';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          if (widget.showProgress) {
            context.push('/player/${widget.video.id}');
          } else if (widget.channel != null) {
            context.push('/channel/${widget.channel!.id}');
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: AppConstants.videoCardWidth,
          transform: _isHovered
              ? (Matrix4.identity()..scale(1.05))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: AppConstants.cardAspectRatio,
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
                              size: 40,
                            ),
                          ),
                          placeholder: (_, __) => Container(
                            color: NullFeedTheme.cardColor,
                          ),
                        )
                      else
                        Container(
                          color: NullFeedTheme.cardColor,
                          child: const Icon(
                            Icons.play_circle_outline,
                            color: NullFeedTheme.textMuted,
                            size: 40,
                          ),
                        ),

                      // Duration badge
                      if (widget.video.durationSeconds > 0)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.video.formattedDuration,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      // Play icon overlay on hover
                      if (_isHovered)
                        Container(
                          color: Colors.black38,
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Progress bar
              if (widget.showProgress && widget.video.watchProgress > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: NullFeedProgressBar(
                    progress: widget.video.watchProgress,
                    height: 3,
                  ),
                ),

              // Title & channel
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _isHovered
                        ? NullFeedTheme.textPrimary
                        : NullFeedTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.channel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    widget.channel!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NullFeedTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
