import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video.dart';
import '../models/channel.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/feed_provider.dart';
import '../providers/offline_provider.dart';
import 'progress_bar.dart';

class VideoCard extends ConsumerStatefulWidget {
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
  ConsumerState<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends ConsumerState<VideoCard> {
  bool _isPressed = false;

  String? get _thumbnailUrl {
    if (widget.video.youtubeVideoId.isNotEmpty) {
      return 'https://img.youtube.com/vi/${widget.video.youtubeVideoId}/mqdefault.jpg';
    }
    return null;
  }

  Future<void> _onActivate() async {
    HapticFeedback.selectionClick();
    // Every home-feed card plays its video on tap; channel navigation lives
    // on the channel sub-row below (see [_openChannel]).
    await context.push('/player/${widget.video.id}');
    // Watch positions likely changed — refresh the home feed rows.
    if (!mounted) return;
    invalidateFeedProviders(ref);
  }

  void _openChannel() {
    final channel = widget.channel;
    if (channel == null) return;
    HapticFeedback.selectionClick();
    context.push('/channel/${channel.id}');
  }

  @override
  Widget build(BuildContext context) {
    const cardWidth = AppConstants.videoCardWidth;

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail + progress + title are one tap target that plays.
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _onActivate,
                onTapDown: (_) => setState(() => _isPressed = true),
                onTapUp: (_) => setState(() => _isPressed = false),
                onTapCancel: () => setState(() => _isPressed = false),
                borderRadius: BorderRadius.circular(12),
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
                                placeholder: (_, __) =>
                                    Container(color: NullFeedTheme.cardColor),
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

                            // Offline badge
                            if (ref.watch(
                                  offlineStatusProvider(widget.video.id),
                                ) ==
                                'complete')
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.offline_pin,
                                    color: NullFeedTheme.successColor,
                                    size: 16,
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

                    // Title
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: NullFeedTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Channel sub-row → open the channel.
            if (widget.channel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: _openChannel,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        if (widget.channel!.avatarUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: CircleAvatar(
                              radius: 10,
                              backgroundImage: CachedNetworkImageProvider(
                                widget.channel!.avatarUrl!,
                              ),
                              backgroundColor: NullFeedTheme.cardColor,
                            ),
                          ),
                        Expanded(
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
              ),
          ],
        ),
      ),
    );
  }
}
